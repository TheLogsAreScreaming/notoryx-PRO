import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/export_crypto.dart';
import 'package:notoryx_pro/app/message_export.dart';
import 'package:notoryx_pro/app/message_import.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/restore_sheet.dart';

final radio = RadioId.meshtastic(0xa1b2c3d4);
final ch = ChannelConversation(radio, 0);

Message msg(
  String text,
  int minute, {
  bool outgoing = false,
  DeliveryState? delivery,
  bool authenticated = false,
}) => Message(
  conversation: ch,
  text: text,
  outgoing: outgoing,
  sentAt: DateTime.utc(2026, 11, 1, 10, minute),
  receivedAt: DateTime.utc(2026, 11, 1, 10, minute, 5),
  delivery: delivery ?? (outgoing ? const Sent() : const Received()),
  senderName: outgoing ? null : 'Ann',
  authenticated: authenticated,
);

Future<String> exported(MeshStore s) async => messagesToJson(
  await s.allMessages(),
  const {},
  exportedAt: DateTime.utc(2026, 11, 2),
);

void main() {
  test('an export restores onto an empty device', () async {
    final a = MeshStore.memory();
    await a.addMessage(msg('hello', 1));
    await a.addMessage(
      msg('out', 2, outgoing: true, delivery: const Failed('No route')),
    );
    final b = MeshStore.memory();
    final parsed = parseExport(await exported(a));
    expect(await b.restoreMessages(parsed.messages), 2);
    final got = await b.messages(ch);
    expect(got.map((m) => m.message.text), ['hello', 'out']);
    expect((got.last.message.delivery as Failed).reason, 'No route');
    expect(got.first.message.senderName, 'Ann');
    await a.close();
    await b.close();
  });

  test('restoring twice adds nothing', () async {
    final a = MeshStore.memory();
    await a.addMessage(msg('hello', 1));
    final parsed = parseExport(await exported(a));
    expect(await a.restoreMessages(parsed.messages), 0);
    final b = MeshStore.memory();
    expect(await b.restoreMessages(parsed.messages), 1);
    expect(await b.restoreMessages(parsed.messages), 0);
    await a.close();
    await b.close();
  });

  test(
    'old messages slot in by time, and the inbox keeps the newest',
    () async {
      final a = MeshStore.memory();
      await a.addMessage(msg('old', 1));
      final file = await exported(a);
      final b = MeshStore.memory();
      await b.addMessage(msg('new', 30));
      await b.restoreMessages(parseExport(file).messages);
      expect((await b.messages(ch)).map((m) => m.message.text), ['old', 'new']);
      expect((await b.conversations()).single.last.message.text, 'new');
      await a.close();
      await b.close();
    },
  );

  test('restored messages are not unread and do not notify', () async {
    final a = MeshStore.memory();
    await a.addMessage(msg('hello', 1));
    final file = await exported(a);
    final b = MeshStore.memory();
    final heard = <StoredMessage>[];
    final sub = b.incoming.listen(heard.add);
    await b.restoreMessages(parseExport(file).messages);
    await pumpEventQueue();
    expect(heard, isEmpty);
    expect(await b.watchUnread().first, isEmpty);
    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('a file cannot claim a verified sender', () async {
    final a = MeshStore.memory();
    await a.addMessage(msg('hello', 1, authenticated: true));
    final parsed = parseExport(await exported(a));
    expect(parsed.messages.single.authenticated, isFalse);
    await a.close();
  });

  test('a message still waiting comes back failed', () {
    final d = MeshStore.deliveryFromExport('pending', null, outgoing: true);
    expect(d, isA<Failed>());
  });

  group('bad files', () {
    void refused(String text, RestoreProblem p) => expect(
      () => parseExport(text),
      throwsA(isA<RestoreRefused>().having((e) => e.problem, 'problem', p)),
    );

    test('are refused', () {
      refused('not json', RestoreProblem.notAnExport);
      refused('[]', RestoreProblem.notAnExport);
      refused('{"format":"other"}', RestoreProblem.notAnExport);
      refused(
        '{"format":"notoryx-pro-messages","formatVersion":2,"messages":[]}',
        RestoreProblem.tooNew,
      );
    });

    test('broken entries are counted and left out', () {
      final p = parseExport(
        jsonEncode({
          'format': 'notoryx-pro-messages',
          'formatVersion': 1,
          'messages': [
            7,
            {'conversation': 'nope', 'text': 'x'},
            {
              'conversation': ch.key,
              'text': 'ok',
              'outgoing': false,
              'sentAtUtc': '2026-11-01T10:00:00Z',
              'receivedAtUtc': '2026-11-01T10:00:01Z',
              'hops': 'three',
            },
          ],
        }),
      );
      expect(p.unreadable, 2);
      expect(p.messages.single.path.hops, isNull);
    });
  });

  testWidgets('screen: confirm, then report the result', (t) async {
    final (store, file) = (await t.runAsync(() async {
      final a = MeshStore.memory();
      await a.addMessage(msg('hello', 1));
      final f = await exported(a);
      await a.close();
      return (MeshStore.memory(), f);
    }))!;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => restoreFromExport(
                context,
                store: store,
                pick: () async => file,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.tap(find.text('go'));
    await settle();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Restore'));
    await settle();
    expect(find.textContaining('Added 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });

  testWidgets('screen: a protected backup asks for its password', (t) async {
    final (store, file) = (await t.runAsync(() async {
      final a = MeshStore.memory();
      await a.addMessage(msg('hello', 1));
      final f = await encryptExport(
        await exported(a),
        'trailhead42',
        iterations: 1000,
      );
      await a.close();
      return (MeshStore.memory(), f);
    }))!;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => restoreFromExport(
                context,
                store: store,
                pick: () async => file,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.tap(find.text('go'));
    await settle();
    await t.enterText(find.byKey(const Key('password-1')), 'wrong');
    await t.pump();
    await t.tap(find.byKey(const Key('password-ok')));
    await settle();
    expect(find.textContaining('Wrong password'), findsOneWidget);

    await t.tap(find.text('go'));
    await settle();
    await t.enterText(find.byKey(const Key('password-1')), 'trailhead42');
    await t.pump();
    await t.tap(find.byKey(const Key('password-ok')));
    await settle();
    await t.tap(find.text('Restore'));
    await settle();
    expect(find.textContaining('Added 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
