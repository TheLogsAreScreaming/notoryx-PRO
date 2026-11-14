import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/auto_responder.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/auto_reply_screen.dart';

final radio = RadioId.meshtastic(1);
final node = NodeKey.meshtastic(2);
final dm = DirectConversation(radio, node);
final ch = ChannelConversation(radio, 0);

void main() {
  late DateTime now;
  late List<(Conversation, String)> out;
  late AutoResponder bot;
  late MeshStore store;

  Message msg(
    String text, {
    Conversation? c,
    bool outgoing = false,
    DateTime? sent,
  }) => Message(
    conversation: c ?? dm,
    text: text,
    outgoing: outgoing,
    sentAt: sent ?? now,
    receivedAt: now,
    delivery: const Received(),
    from: node,
    senderName: 'Ann',
    path: const PathFacts(hops: 2, snr: 6.5),
  );

  const ping = AutoRule(id: 1, keyword: 'ping', reply: 'pong {name} {hops}');

  setUp(() {
    store = MeshStore.memory();
    now = DateTime(2026, 11, 9, 14, 5);
    out = [];
    bot = AutoResponder(
      store: store,
      send: (c, t) async {
        out.add((c, t));
        return true;
      },
      now: () => now,
    )..settings = const AutoSettings(on: true, rules: [ping]);
  });
  tearDown(() => store.close());

  test('answers a whole-word match, marked, with details filled in', () async {
    await bot.handle(msg(' PING '));
    expect(out.single, (dm, '[auto] pong Ann 2'));
  });

  test('off by default, and not for partial matches', () async {
    expect(AutoSettings.decode(null).on, isFalse);
    await bot.handle(msg('ping me later'));
    expect(out, isEmpty);
    bot.settings = const AutoSettings(rules: [ping]);
    await bot.handle(msg('ping'));
    expect(out, isEmpty);
  });

  test(
    'never answers emergencies, reactions, bots, itself or backlog',
    () async {
      const all = AutoRule(id: 2, keyword: AutoRule.away, reply: 'away');
      bot.settings = const AutoSettings(on: true, rules: [all]);
      await bot.handle(msg('MECP/0/M01'));
      await bot.handle(msg('[auto] away'));
      await bot.handle(msg('hello', outgoing: true));
      await bot.handle(
        msg('hello', sent: now.subtract(const Duration(minutes: 30))),
      );
      expect(out, isEmpty);
    },
  );

  test('channels only when the rule says so; away never', () async {
    await bot.handle(msg('ping', c: ch));
    expect(out, isEmpty);
    bot.settings = const AutoSettings(
      on: true,
      rules: [AutoRule(id: 3, keyword: 'ping', reply: 'x', channels: true)],
    );
    await bot.handle(msg('ping', c: ch));
    expect(out, hasLength(1));
    final saved = AutoRule.fromJson({'id': 4, 'k': '*', 'r': 'x', 'c': true})!;
    expect(saved.channels, isFalse);
  });

  test('limits per sender and per hour', () async {
    await bot.handle(msg('ping'));
    await bot.handle(msg('ping'));
    expect(out, hasLength(1));
    now = now.add(const Duration(minutes: 6));
    await bot.handle(msg('ping'));
    expect(out, hasLength(2));

    Message from(int n) => Message(
      conversation: DirectConversation(radio, NodeKey.meshtastic(100 + n)),
      text: 'ping',
      outgoing: false,
      sentAt: now,
      receivedAt: now,
      delivery: const Received(),
      from: NodeKey.meshtastic(100 + n),
    );
    for (var i = 0; i < 20; i++) {
      await bot.handle(from(i));
    }
    expect(out, hasLength(AutoResponder.maxPerHour));
  });

  test('settings round trip; junk reads as off', () {
    final back = AutoSettings.decode(
      const AutoSettings(on: true, rules: [ping]).encode(),
    );
    expect((back.on, back.rules.single.keyword), (true, 'ping'));
    expect(AutoSettings.decode('nope').on, isFalse);
  });

  testWidgets('screen: add a rule and switch on', (t) async {
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = MeshStore.memory();
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AutoReplyScreen(store: s),
      ),
    );
    await settle();
    expect(find.text('{name}', findRichText: true), findsNothing);
    await t.tap(find.byKey(const Key('auto-add')));
    await settle();
    await t.enterText(find.byKey(const Key('auto-keyword')), 'ping');
    await t.enterText(find.byKey(const Key('auto-reply')), 'pong');
    await t.pump();
    await t.tap(find.byKey(const Key('auto-save')));
    await settle();
    expect(find.text('pong'), findsOneWidget);
    await t.tap(find.byKey(const Key('auto-on')));
    await settle();
    expect(find.text('You can use'), findsNothing);
    await t.pumpWidget(const SizedBox());
    final closing = s.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });

  test('presets fit the reply limit and use only known fields', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      final presets = AutoPreset.all(l);
      expect(presets.where((p) => p.isAway), hasLength(2));
      for (final p in presets) {
        expect(p.reply.length, lessThanOrEqualTo(120), reason: p.reply);
        final fields = RegExp(r'\{(\w+)\}').allMatches(p.reply);
        for (final f in fields) {
          expect(['name', 'time', 'hops', 'snr'], contains(f.group(1)));
        }
      }
    }
  });

  testWidgets('screen: a preset opens filled in and is added', (t) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = MeshStore.memory();
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AutoReplyScreen(store: s),
      ),
    );
    await settle();
    expect(find.text('Ready-made replies'), findsOneWidget);
    await t.tap(find.byKey(const Key('auto-preset-ping')));
    await settle();
    final reply = t.widget<TextField>(find.byKey(const Key('auto-reply')));
    expect(reply.controller!.text, 'pong. {hops} hops, SNR {snr} dB.');
    await t.tap(find.byKey(const Key('auto-save')));
    await settle();
    expect(find.byKey(const Key('auto-preset-ping')), findsNothing);
    final saved = AutoSettings.decode(
      await t.runAsync<String?>(() => s.preference(AutoResponder.prefName)),
    );
    expect(saved.rules.single.keyword, 'ping');

    await t.tap(find.byKey(const Key('auto-preset-away')));
    await settle();
    await t.tap(find.byKey(const Key('auto-save')));
    await settle();
    expect(find.byKey(const Key('auto-preset-away')), findsNothing);
    expect(find.byKey(const Key('auto-preset-driving')), findsNothing);

    await t.pumpWidget(const SizedBox());
    final closing = s.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
