import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/app/hop_naming_service.dart';
import 'package:notoryx_pro/mesh/hop_naming.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/signal.dart';
import 'package:notoryx_pro/mesh/topology.dart';

final _radio = RadioId.meshcore('ff' * 32);
const _you = GeoPoint(47.6, -122.3);
final _now = DateTime.utc(2026, 11, 13);

Node _relay(String key, String name, [GeoPoint? at]) => Node(
  key: NodeKey.meshcore(key),
  radioId: _radio,
  name: name,
  kind: NodeKind.relay,
  position: at,
);

Node _target(List<int> route) => Node(
  key: NodeKey.meshcore('99' * 32),
  radioId: _radio,
  name: 'Friend',
  path: PathFacts(hops: route.length),
  route: route,
);

final _north = _relay('3d${'aa' * 31}', 'North', const GeoPoint(47.7, -122.3));
final _south = _relay('3d${'bb' * 31}', 'South', const GeoPoint(47.95, -122.3));

void main() {
  test('without naming, a shared ID stays unknown', () {
    final hops = resolveRoute(_target([0x3d]), [_north, _south]);
    expect(hops.single.node, isNull);
  });

  test('the nearer repeater wins and is remembered for later', () {
    final naming = HopNaming();
    final hops = resolveRoute(
      _target([0x3d]),
      [_north, _south],
      naming: naming,
      from: _you,
      now: _now,
    );
    expect(hops.single.node?.name, 'North');
    expect(naming.unsaved, isTrue);
    final later = resolveRoute(
      _target([0x3d]),
      [_north, _south],
      naming: naming,
      now: _now,
    );
    expect(later.single.node?.name, 'North');
  });

  test('a remembered pick expires', () {
    final naming = HopNaming(tieDays: 30)
      ..remember('3d', _north.key.native, _now);
    expect(naming.pickFor('3d', _now.add(const Duration(days: 29))), isNotNull);
    expect(naming.pickFor('3d', _now.add(const Duration(days: 31))), isNull);
  });

  test('a near tie goes to the remembered pick; a clear win does not', () {
    final near = _relay(
      '3d${'aa' * 31}',
      'North',
      const GeoPoint(47.6999, -122.3),
    );
    final south = _relay(
      '3d${'bb' * 31}',
      'South',
      const GeoPoint(47.5, -122.3),
    );
    final naming = HopNaming()..remember('3d', south.key.native, _now);
    expect(naming.choose('3d', [near, south], _you, _now)?.name, 'South');
    final close = _relay(
      '3d${'aa' * 31}',
      'Close',
      const GeoPoint(47.61, -122.3),
    );
    expect(naming.choose('3d', [close, south], _you, _now)?.name, 'Close');
  });

  test('all out of range: no guess', () {
    final far1 = _relay('3d${'aa' * 31}', 'A', const GeoPoint(40, -75));
    final far2 = _relay('3d${'bb' * 31}', 'B', const GeoPoint(39, -105));
    expect(HopNaming().choose('3d', [far1, far2], _you, _now), isNull);
  });

  test('unknown hops carry a name found online', () {
    final naming = HopNaming(found: {'7f': 'Ridge'});
    final hops = resolveRoute(_target([0x7f]), [_north], naming: naming);
    expect(hops.single.node, isNull);
    expect(hops.single.onlineName, 'Ridge');
    final t = Topology.build([
      _target([0x7f]),
    ], resolve: (n, k) => resolveRoute(n, k, naming: naming));
    expect(t.nodes.values.map((n) => n.label), contains('Ridge'));
  });

  group('online reply', () {
    final reply = {
      'resolved': {
        '3D': {
          'name': 'Far Away',
          'ambiguous': true,
          'candidates': [
            {'name': 'Far Away', 'lat': 51.4, 'lon': 6.9},
            {'name': 'Close By', 'lat': 47.62, 'lon': -122.31},
          ],
        },
        'AB': {'name': 'Only One', 'ambiguous': false},
      },
    };

    test('nearest candidate within range of you', () {
      expect(onlineHopName(reply, '3d', you: _you), 'Close By');
      expect(onlineHopName(reply, 'ab', you: _you), isNull);
    });

    test('without a position only a sure answer', () {
      expect(onlineHopName(reply, '3d'), isNull);
      expect(onlineHopName(reply, 'ab'), 'Only One');
      expect(onlineHopName(42, 'ab'), isNull);
    });
  });

  test('settings round trip, clamped, https only', () {
    final n = HopNaming(online: true, tieDays: 12, tieMargin: 7)
      ..remember('3d', 'abc', _now);
    final back = HopNaming.fromJson(jsonDecode(jsonEncode(n.toJson(_now))));
    expect(back.online, isTrue);
    expect(back.tieDays, 12);
    expect(back.tieMargin, 7);
    expect(back.pickFor('3d', _now), 'abc');
    final odd = HopNaming.fromJson({
      'tieDays': 999,
      'tieMargin': -1,
      'server': 'http://plain.example',
    });
    expect(odd.tieDays, HopNaming.maxTieDays);
    expect(odd.tieMargin, 0);
    expect(odd.server, HopNaming.defaultServer);
  });

  test('the service looks up unknown IDs once, only when turned on', () async {
    final prefs = <String, String>{};
    final asked = <Uri>[];
    final service = HopNamingService(
      read: (k) async => prefs[k],
      write: (k, v) async => prefs[k] = v,
      clock: () => _now,
      httpClient: MockClient((r) async {
        asked.add(r.url);
        return http.Response(
          jsonEncode({
            'resolved': {
              '7F': {'name': 'Ridge', 'ambiguous': false},
            },
          }),
          200,
        );
      }),
    );
    service.want(['7f']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(asked, isEmpty);

    await service.setOnline(true);
    service
      ..want(['7f'])
      ..want(['7F']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(asked, hasLength(1));
    expect(asked.single.path, '/api/resolve-hops');
    expect(asked.single.queryParameters['hops'], '7F');
    expect(service.value.found['7f'], 'Ridge');
    expect(jsonDecode(prefs[HopNaming.prefName]!)['online'], isTrue);
    service.dispose();
  });
}
