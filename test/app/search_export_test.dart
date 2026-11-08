import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/message_export.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/mute_menu.dart';
import 'package:notoryx_pro/ui/search_screen.dart';

final radio = RadioId.meshtastic(0xa1b2c3d4);
final bob = NodeKey.meshtastic(0x0badcafe);
final dm = DirectConversation(radio, bob);
final ch = ChannelConversation(radio, 0);
final t0 = DateTime.utc(2026, 11, 8, 12);

Message msg(Conversation c, String text, {int s = 0, bool react = false}) =>
    Message(
      conversation: c,
      text: text,
      outgoing: true,
      sentAt: t0.add(Duration(seconds: s)),
      receivedAt: t0.add(Duration(seconds: s)),
      delivery: const Pending(),
      isReaction: react,
    );

void main() {
  test('search: any conversation, newest first, wildcards are text', () async {
    final store = MeshStore.memory();
    await store.addMessage(msg(dm, 'Meet at the RIDGE', s: 1));
    await store.addMessage(msg(ch, 'ridge is clear', s: 2));
    await store.addMessage(msg(ch, '100% ready', s: 3));
    await store.addMessage(msg(ch, 'ridge', s: 4, react: true));
    expect((await store.searchMessages('ridge')).map((m) => m.message.text), [
      'ridge is clear',
      'Meet at the RIDGE',
    ]);
    expect(await store.searchMessages('%'), hasLength(1));
    expect(await store.searchMessages('_'), isEmpty);
    expect(await store.searchMessages(r'\'), isEmpty);
    await store.close();
  });

  test('delete one message, then a whole conversation', () async {
    final store = MeshStore.memory();
    final a = await store.addMessage(msg(dm, 'one', s: 1));
    await store.addMessage(msg(dm, 'two', s: 2));
    await store.addMessage(msg(ch, 'kept', s: 3));
    await store.deleteMessage(a!);
    expect((await store.messages(dm)).map((m) => m.message.text), ['two']);
    await store.deleteConversation(dm);
    expect(await store.messages(dm), isEmpty);
    expect(await store.allMessages(), hasLength(1));
    await store.close();
  });

  group('export', () {
    test('CSV quotes text and defuses formulas', () {
      expect(csvText('plain'), 'plain');
      expect(csvText('a,"b"'), '"a,""b"""');
      expect(csvText('line\nbreak'), '"line\nbreak"');
      for (final bad in ['=1+1', '+1', '-1', '@x']) {
        expect(csvText(bad), "'$bad");
      }
      expect(csvText('=a,b'), '"\'=a,b"');
    });

    test('CSV and JSON carry the messages, oldest first', () async {
      final store = MeshStore.memory();
      await store.addMessage(msg(dm, '=first', s: 1));
      await store.addMessage(msg(ch, 'second, more', s: 2));
      final all = await store.allMessages();
      final titles = {dm.key: 'Bob', ch.key: 'Primary'};
      final lines = messagesToCsv(all, titles).split('\r\n');
      expect(lines.first, startsWith('﻿received_utc,'));
      expect(lines[1], contains(",Bob,sent,,'=first,pending,"));
      expect(lines[2], contains('"second, more"'));

      final doc =
          jsonDecode(messagesToJson(all, titles, exportedAt: t0))
              as Map<String, dynamic>;
      expect(doc['formatVersion'], 1);
      expect(doc['exportedAtUtc'], '2026-11-08T12:00:00.000Z');
      final rows = doc['messages'] as List<dynamic>;
      expect((rows.first as Map)['text'], '=first');
      expect((rows.first as Map)['conversationTitle'], 'Bob');
      expect(
        (await store.allMessages(only: ch)).single.message.text,
        'second, more',
      );
      await store.close();
    });
  });

  testWidgets('search screen finds a message and says when none', (t) async {
    final app = (await t.runAsync(() async {
      final store = MeshStore.memory();
      await store.addMessage(msg(ch, 'water at the hut'));
      return AppController(store: store);
    }))!;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
    }

    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchScreen(app: app),
      ),
    );
    await t.enterText(find.byKey(const Key('search-field')), 'hut');
    await settle();
    expect(find.text('water at the hut'), findsOneWidget);
    await t.enterText(find.byKey(const Key('search-field')), 'zzz');
    await settle();
    expect(find.text('No messages found'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    final closing = app.store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });

  testWidgets('the bell unmutes', (t) async {
    final store = (await t.runAsync(() async {
      final s = MeshStore.memory();
      await s.setMuted(ch, muteForever);
      return s;
    }))!;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
    }

    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MuteButton(store: store, conversation: ch),
        ),
      ),
    );
    await settle();
    await t.tap(find.byKey(const Key('mute-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Unmute'));
    await settle();
    await t.pump(const Duration(seconds: 1));
    final muted = (await t.runAsync(() => store.isMuted(ch, DateTime.now())))!;
    expect(muted, isFalse);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
