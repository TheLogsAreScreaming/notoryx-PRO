import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/message_alerts.dart';
import 'package:notoryx_pro/app/regional_presets.dart';
import 'package:notoryx_pro/app/meshcore_settings.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/radio/radio.dart';

import '../support/scripted_meshtastic.dart';

final mt = RadioId.meshtastic(0xa1b2c3d4);
final relay = NodeKey.meshtastic(0x0badcafe);
final dm = DirectConversation(mt, relay);
final channel = ChannelConversation(mt, 0);

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

/// Records notifications instead of showing them.
class FakeNotifier implements Notifier {
  final shown = <({int id, String title, String body, String payload})>[];
  final cancelled = <int>[];
  final _taps = StreamController<String>.broadcast();

  @override
  Future<bool> init() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async => shown.add((id: id, title: title, body: body, payload: payload));

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Stream<String> get taps => _taps.stream;

  void tap(String payload) => _taps.add(payload);

  final kept = <(bool, String)>[];

  @override
  Future<void> keepAlive(
    bool on, {
    String title = '',
    String body = '',
  }) async => kept.add((on, body));
}

Message received(
  Conversation c,
  String text, {
  int? id,
  String? sender,
  bool reaction = false,
}) {
  final now = DateTime.now();
  return Message(
    conversation: c,
    text: text,
    outgoing: false,
    sentAt: now,
    receivedAt: now,
    delivery: const Received(),
    from: c is DirectConversation ? c.node : null,
    senderName: sender,
    nativeId: id,
    isReaction: reaction,
  );
}

Message sent(Conversation c, String text) {
  final now = DateTime.now();
  return Message(
    conversation: c,
    text: text,
    outgoing: true,
    sentAt: now,
    receivedAt: now,
    delivery: const Pending(),
  );
}

Future<void> seedNames(MeshStore store) async {
  await store.upsertNode(Node(key: relay, radioId: mt, name: 'Ridge Relay'));
  await store.replaceChannels(mt, [
    Channel(
      radioId: mt,
      index: 0,
      name: 'Trail',
      kind: ChannelKind.public,
      isPrimary: true,
    ),
  ]);
}

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('unread and mutes', () {
    late MeshStore store;
    setUp(() => store = MeshStore.memory());
    tearDown(() => store.close());

    test('counts received messages after the last read one', () async {
      await store.addMessage(received(dm, 'one', id: 1));
      await store.addMessage(received(dm, 'two', id: 2));
      await store.addMessage(sent(dm, 'mine'));
      await store.addMessage(received(dm, '👍', id: 3, reaction: true));
      await store.addMessage(received(channel, 'hi', sender: 'Ann'));
      expect(await store.watchUnread().first, {dm.key: 2, channel.key: 1});

      await store.markRead(dm);
      expect(await store.watchUnread().first, {channel.key: 1});
      await store.addMessage(received(dm, 'three', id: 4));
      expect((await store.watchUnread().first)[dm.key], 1);

      await store.markAllRead();
      expect(await store.watchUnread().first, isEmpty);
    });

    test('mute until a time; marking read keeps the mute', () async {
      final now = DateTime(2026, 11, 7, 12);
      await store.setMuted(dm, now.add(const Duration(hours: 1)));
      await store.markRead(dm);
      expect(await store.isMuted(dm, now), isTrue);
      expect(
        await store.isMuted(dm, now.add(const Duration(hours: 2))),
        isFalse,
      );
      expect((await store.watchMutes().first).keys, [dm.key]);
      await store.setMuted(dm, null);
      expect(await store.isMuted(dm, now), isFalse);
      expect(await store.watchMutes().first, isEmpty);
    });

    test('incoming announces new received messages once', () async {
      final seen = <String>[];
      final sub = store.incoming.listen((m) => seen.add(m.message.text));
      await store.addMessage(received(dm, 'once', id: 9));
      await store.addMessage(received(dm, 'once', id: 9)); // repeat
      await store.addMessage(sent(dm, 'mine'));
      await drain();
      await sub.cancel();
      expect(seen, ['once']);
    });

    test('preferences', () async {
      expect(await store.preference('x'), isNull);
      await store.setPreference('x', 'off');
      await store.setPreference('x', 'on');
      expect(await store.preference('x'), 'on');
    });
  });

  group('notifications', () {
    late MeshStore store;
    late FakeNotifier notifier;
    late MessageAlerts alerts;

    setUp(() async {
      store = MeshStore.memory();
      await seedNames(store);
      notifier = FakeNotifier();
      alerts = MessageAlerts(store: store, notifier: notifier);
    });

    tearDown(() async {
      await alerts.dispose();
      await store.close();
    });

    test('one per conversation, counting up, with names', () async {
      await store.addMessage(received(dm, 'are you there?', id: 1));
      await drain();
      await store.addMessage(received(dm, 'hello?', id: 2));
      await store.addMessage(received(channel, 'trail open', sender: 'Ann'));
      await drain();
      expect(notifier.shown.map((n) => (n.title, n.body)), [
        ('Ridge Relay', 'are you there?'),
        ('Ridge Relay (2)', 'hello?'),
        ('Trail', 'Ann: trail open'),
      ]);
      expect(notifier.shown.first.id, MessageAlerts.idFor(dm));
      expect(notifier.shown.first.payload, dm.key);

      await alerts.clear(dm);
      expect(notifier.cancelled, [MessageAlerts.idFor(dm)]);
      await store.addMessage(received(dm, 'again', id: 3));
      await drain();
      expect(notifier.shown.last.title, 'Ridge Relay', reason: 'count reset');
    });

    test('quiet for muted, open, reactions and turned-off kinds', () async {
      await store.setMuted(dm, DateTime.now().add(const Duration(hours: 1)));
      await store.addMessage(received(dm, 'muted', id: 1));
      alerts.open = channel;
      await store.addMessage(received(channel, 'on screen', sender: 'Ann'));
      await store.addMessage(received(dm, '👍', id: 2, reaction: true));
      await drain();
      expect(notifier.shown, isEmpty);

      // The open conversation notifies once the app is in the background.
      alerts.foreground = false;
      await store.addMessage(received(channel, 'later', sender: 'Ann'));
      await drain();
      expect(notifier.shown.single.body, 'Ann: later');

      await store.setPreference(AlertPrefs.channels, 'off');
      await store.addMessage(received(channel, 'off now', sender: 'Bo'));
      await drain();
      expect(notifier.shown, hasLength(1));
    });

    group('MAYDAY through mute', () {
      const real = 'MECP/0/R01 2pax';
      setUp(() async {
        await store.setMuted(dm, DateTime.now().add(const Duration(hours: 1)));
      });

      test('a real one gets through, marked', () async {
        await store.addMessage(received(dm, real, id: 1));
        await drain();
        expect(notifier.shown.single.title, 'MAYDAY: Ridge Relay');
      });

      test('drills, lower severities and plain text stay muted', () async {
        await store.addMessage(received(dm, 'MECP/0/D01 R01', id: 1));
        await store.addMessage(received(dm, 'MECP/1/R01', id: 2));
        await store.addMessage(received(dm, 'MAYDAY help', id: 3));
        await drain();
        expect(notifier.shown, isEmpty);
      });

      test('can be turned off', () async {
        await store.setPreference(AlertPrefs.mayday, 'off');
        await store.addMessage(received(dm, real, id: 1));
        await drain();
        expect(notifier.shown, isEmpty);
      });

      test('repeats within 10 minutes stay muted', () async {
        var now = DateTime.now();
        final timed = MessageAlerts(
          store: store,
          notifier: notifier,
          now: () => now,
        );
        await alerts.dispose();
        Message m(int id) => received(dm, '$real n$id', id: id);
        await timed.breaksMute(m(1));
        expect(await timed.breaksMute(m(2)), isFalse);
        now = now.add(const Duration(minutes: 11));
        expect(await timed.breaksMute(m(3)), isTrue);
        await timed.dispose();
      });
    });

    test('a tapped notification names its conversation', () {
      expect(MessageAlerts.conversationFor(dm.key), dm);
      expect(MessageAlerts.conversationFor('nonsense'), isNull);
    });
  });

  group('regional presets', () {
    test('every preset is a valid radio setting', () {
      for (final p in [
        ...MeshCorePresets.suggested,
        ...MeshCorePresets.local,
      ]) {
        expect(p.frequencyMHz, inInclusiveRange(150, 2500), reason: p.name);
        expect(
          MeshCoreSettings.bandwidths.any(
            (b) => (b - p.bandwidthKHz).abs() < 0.05,
          ),
          isTrue,
          reason: '${p.name} bandwidth ${p.bandwidthKHz}',
        );
        expect(p.spreadingFactor, inInclusiveRange(5, 12), reason: p.name);
        expect(p.codingRate, inInclusiveRange(5, 8), reason: p.name);
      }
      expect(MeshCorePresets.suggested, hasLength(27));
      expect(MeshCorePresets.local, hasLength(27));
    });

    test('the US preset and nearby local meshes', () {
      final us = MeshCorePresets.suggested.firstWhere((p) => p.name == 'USA');
      expect(us.matches(910.525, 62.5, 7, 5), isTrue);
      // Downtown Phoenix.
      final near = MeshCorePresets.near(33.45, -112.07);
      expect(near.first.name, startsWith('Phoenix'));
      expect(near.first.frequencyMHz, 908.205);
      expect(MeshCorePresets.near(0, -150), isEmpty, reason: 'mid-ocean');
      // Retired presets sort last.
      expect(MeshCorePresets.suggestedSorted().last.retired, isTrue);
    });

    test('distance', () {
      // Phoenix to Tucson is about 180 km.
      expect(greatCircleKm(33.45, -112.07, 32.22, -110.97), closeTo(173, 10));
    });
  });

  group('screens', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    Future<void> close(WidgetTester tester, AppController app) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(app.shutdown);
      final closing = app.store.close();
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => closing);
    }

    testWidgets('inbox badges, mute, opening marks read, tap opens', (
      tester,
    ) async {
      final notifier = FakeNotifier();
      // Built outside the test clock: the alerts query the database as
      // messages arrive, and the database runs on real time.
      final app = (await tester.runAsync(
        () async =>
            AppController(store: MeshStore.memory(), notifier: notifier),
      ))!;
      await tester.runAsync(() async {
        await seedNames(app.store);
        await app.store.addMessage(received(dm, 'one', id: 1));
        await app.store.addMessage(received(dm, 'two', id: 2));
        await app.store.addMessage(
          received(channel, 'trail open', sender: 'Ann'),
        );
      });
      await tester.pumpWidget(NotoryxProApp(app: app));
      await settle(tester);
      expect(find.text('2'), findsOneWidget, reason: 'DM badge');
      expect(find.text('3'), findsOneWidget, reason: 'inbox tab badge');

      // Long-press the channel: mute it; the tab badge drops to 2.
      await tester.longPress(find.text('Trail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Mute until I unmute'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2), reason: 'DM and tab');

      // Opening the DM marks it read and clears its notification.
      await tester.tap(find.text('Ridge Relay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(notifier.cancelled, contains(MessageAlerts.idFor(dm)));
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text('2'), findsNothing);
      expect(await tester.runAsync(() => app.store.watchUnread().first), {
        channel.key: 1,
      });

      // A tapped notification opens its conversation.
      notifier.tap(channel.key);
      await settle(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('trail open'), findsOneWidget);
      await close(tester, app);
    });

    testWidgets('stays connected in the background while radios are', (
      tester,
    ) async {
      final notifier = FakeNotifier();
      final app = (await tester.runAsync(
        () async => AppController(
          store: MeshStore.memory(),
          notifier: notifier,
          links: FakeLinks(ScriptedMeshtasticLink()),
        ),
      ))!;
      await tester.pumpWidget(NotoryxProApp(app: app));
      await settle(tester);
      expect(notifier.kept, isEmpty, reason: 'nothing connected');
      // Not awaited: the mounted screens' queries need pumps to finish, and
      // connecting needs those queries out of the way.
      var connected = false;
      await tester.runAsync(() async {
        unawaited(
          app
              .connect(
                const TcpTarget(host: 'n', protocol: RadioProtocol.meshtastic),
              )
              .whenComplete(() => connected = true),
        );
      });
      for (var i = 0; i < 100 && !connected; i++) {
        await settle(tester);
      }
      expect(connected, isTrue);
      await settle(tester);
      expect(notifier.kept.last, (true, 'Connected to 1 radio'));
      await tester.runAsync(
        () => app.store.setPreference(AlertPrefs.background, 'off'),
      );
      await settle(tester);
      expect(notifier.kept.last.$1, isFalse, reason: 'turned off');
      await tester.runAsync(
        () => app.store.setPreference(AlertPrefs.background, 'on'),
      );
      await settle(tester);
      expect(notifier.kept.last.$1, isTrue);
      await tester.runAsync(() => app.disconnect(app.connections.single));
      await settle(tester);
      expect(notifier.kept.last.$1, isFalse, reason: 'no radios left');
      await close(tester, app);
    });

    testWidgets('notification settings switch a kind off', (tester) async {
      final app = (await tester.runAsync(
        () async =>
            AppController(store: MeshStore.memory(), notifier: FakeNotifier()),
      ))!;
      await tester.pumpWidget(NotoryxProApp(app: app));
      await settle(tester);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      await tester.tap(find.byKey(const Key(AlertPrefs.channels)));
      await settle(tester);
      expect(
        await tester.runAsync(() => app.store.preference(AlertPrefs.channels)),
        'off',
      );
      await tester.ensureVisible(find.text('Allow notifications'));
      await tester.pump();
      await tester.tap(find.text('Allow notifications'));
      await tester.pump();
      expect(find.text('Notifications are on.'), findsOneWidget);
      await close(tester, app);
    });
  });
}
