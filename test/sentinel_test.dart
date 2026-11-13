import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/app/sentinel.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

const _coreKey =
    'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';

void main() {
  late Map<String, String> prefs;
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late DateTime now;
  var refs = 0;

  http.Response json(int status, Object body) =>
      http.Response(jsonEncode(body), status);
  Map<String, Object?> decisions(List<Object?> bans) => {
    'advisory': true,
    'bans': bans,
  };

  SentinelService make() => SentinelService(
    read: (n) async => prefs[n],
    write: (n, v) async => prefs[n] = v,
    baseUrl: 'https://relay.test',
    now: () => now,
    newRef: () => 'ref-${++refs}',
    httpClient: MockClient((req) async {
      requests.add(req);
      return respond(req);
    }),
  );

  setUp(() {
    prefs = {};
    requests = [];
    refs = 0;
    now = DateTime.utc(2026, 11, 13, 12);
    respond = (_) => json(200, decisions(const []));
  });

  Message incoming({NodeKey? from, String? name, required RadioId radio}) =>
      Message(
        conversation: ChannelConversation(radio, 0),
        text: 'buy now',
        outgoing: false,
        sentAt: now,
        receivedAt: now,
        delivery: const Received(),
        from: from,
        senderName: name,
      );

  test('off by default: no requests, no labels', () async {
    final s = make();
    await s.start();
    await s.refresh(force: true);
    expect(s.enabled, isFalse);
    expect(requests, isEmpty);
    final r = await s.report(
      network: RadioProtocol.meshcore,
      nodeId: _coreKey,
      reason: SentinelReason.spam,
    );
    expect(r, isA<SentinelReportRejected>());
    expect(requests, isEmpty);
    s.dispose();
  });

  test(
    'syncs both networks and labels keys, names and Meshtastic ids',
    () async {
      respond = (req) => req.url.path.contains('/meshcore/')
          ? json(
              200,
              decisions([
                {'nodeId': _coreKey.toUpperCase(), 'caseRef': 'SNT-1'},
                {'nodeId': 'name:Spammy', 'caseRef': 'SNT-2'},
              ]),
            )
          : json(
              200,
              decisions([
                {
                  'nodeId': '!a1b2c3d4',
                  'caseRef': 'SNT-3',
                  'appealPending': true,
                },
              ]),
            );
      final s = make();
      await s.start();
      await s.setEnabled(true);
      await s.syncDecisions(force: true);
      expect(requests.map((r) => r.url.toString()).toSet(), {
        'https://relay.test/v1/meshcore/decisions',
        'https://relay.test/v1/meshtastic/decisions',
      });
      expect(s.flaggedCount(RadioProtocol.meshcore), 2);
      expect(s.flaggedCount(RadioProtocol.meshtastic), 1);
      expect(s.banFor(NodeKey.meshcore(_coreKey))?.caseRef, 'SNT-1');
      expect(s.banFor(NodeKey.meshtastic(0xa1b2c3d4))?.appealPending, isTrue);
      // A Meshtastic ban never matches a MeshCore node and vice versa.
      expect(s.banForName(RadioProtocol.meshtastic, 'Spammy'), isNull);

      final mc = RadioId.meshcore(_coreKey);
      expect(
        s.banForMessage(incoming(name: 'Spammy', radio: mc))?.caseRef,
        'SNT-2',
      );
      expect(s.hides(incoming(name: 'Spammy', radio: mc)), isFalse);
      await s.setHideFlagged(true);
      expect(s.hides(incoming(name: 'Spammy', radio: mc)), isTrue);
      expect(s.hides(incoming(name: 'Friend', radio: mc)), isFalse);
      s.dispose();

      // Survives a restart with no network.
      respond = (_) => throw Exception('offline');
      final again = make();
      await again.start();
      expect(again.banFor(NodeKey.meshtastic(0xa1b2c3d4))?.caseRef, 'SNT-3');
      await again.setEnabled(false);
      expect(again.banFor(NodeKey.meshtastic(0xa1b2c3d4)), isNull);
      again.dispose();
    },
  );

  test(
    'reports go to their own network; offline ones queue in order',
    () async {
      var online = true;
      respond = (req) {
        if (!online) throw Exception('offline');
        if (req.url.path.endsWith('/reports')) {
          final ref = (jsonDecode(req.body) as Map)['externalRef'];
          return json(201, {'caseRef': 'SNT-$ref'});
        }
        return json(200, decisions(const []));
      };
      final s = make();
      await s.start();
      await s.setEnabled(true);
      final sent = await s.report(
        network: RadioProtocol.meshtastic,
        nodeId: '!a1b2c3d4',
        nodeName: 'Bob',
        reason: SentinelReason.flooding,
        note: ' all day ',
        messageExcerpt: 'x' * 400,
      );
      expect(sent, isA<SentinelReportSent>());
      final post = requests.lastWhere((r) => r.method == 'POST');
      expect(post.url.toString(), 'https://relay.test/v1/meshtastic/reports');
      final body = jsonDecode(post.body) as Map;
      expect(body['reason'], 'Flooding the mesh: all day');
      expect((body['messageExcerpt'] as String).length, 280);
      expect(body.containsKey('network'), isFalse);

      online = false;
      await s.report(
        network: RadioProtocol.meshcore,
        nodeId: _coreKey,
        reason: SentinelReason.spam,
      );
      await s.report(
        network: RadioProtocol.meshtastic,
        nodeId: '!00000002',
        reason: SentinelReason.spam,
      );
      expect(s.queuedCount, 2);
      s.dispose();

      online = true;
      requests.clear();
      final again = make();
      await again.start();
      expect(await again.flushQueue(), 2);
      final posts = requests.where((r) => r.method == 'POST').toList();
      expect(posts.map((r) => r.url.path), [
        '/v1/meshcore/reports',
        '/v1/meshtastic/reports',
      ]);
      expect(posts.map((r) => (jsonDecode(r.body) as Map)['externalRef']), [
        'ref-2',
        'ref-3',
      ]);
      await again.setEnabled(false);
      again.dispose();
    },
  );

  test('400 is dropped; 429 and 5xx are queued', () async {
    var status = 400;
    respond = (req) => req.url.path.endsWith('/reports')
        ? json(status, {'error': 'Invalid report'})
        : json(200, decisions(const []));
    final s = make();
    await s.start();
    await s.setEnabled(true);
    Future<SentinelReportOutcome> go() => s.report(
      network: RadioProtocol.meshcore,
      nodeId: _coreKey,
      reason: SentinelReason.spam,
    );
    expect(await go(), isA<SentinelReportRejected>());
    status = 429;
    expect(await go(), isA<SentinelReportQueued>());
    status = 503;
    expect(await go(), isA<SentinelReportQueued>());
    expect(s.queuedCount, 2);
    await s.setEnabled(false);
    s.dispose();
  });

  test('appeals go to the chosen network and map status codes', () async {
    var status = 201;
    respond = (req) => req.url.path.endsWith('/appeals')
        ? json(status, {})
        : json(200, decisions(const []));
    final s = make();
    await s.start();
    await s.setEnabled(true);
    Future<SentinelAppealOutcome> go() => s.appeal(
      network: RadioProtocol.meshtastic,
      caseRef: 'snt-7',
      statement: 'my beacon',
    );
    expect(await go(), SentinelAppealOutcome.received);
    final post = requests.lastWhere((r) => r.url.path.endsWith('/appeals'));
    expect(post.url.path, '/v1/meshtastic/appeals');
    expect(jsonDecode(post.body), {
      'caseRef': 'SNT-7',
      'statement': 'my beacon',
    });
    for (final (code, want) in [
      (404, SentinelAppealOutcome.unknownCase),
      (409, SentinelAppealOutcome.notAppealable),
      (429, SentinelAppealOutcome.tooMany),
      (500, SentinelAppealOutcome.failed),
    ]) {
      status = code;
      expect(await go(), want);
    }
    await s.setEnabled(false);
    s.dispose();
  });

  test('a forced sync during a running one joins it', () async {
    final s = make();
    await s.start();
    await s.setEnabled(true); // starts a background sync
    await s.syncDecisions(force: true);
    expect(s.syncedAt, isNotNull);
    await s.setEnabled(false);
    s.dispose();
  });
}
