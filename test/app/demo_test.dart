import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/ui/demo_screen.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/demo/demo_radio.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

void main() {
  test('the demo radio connects, sends, confirms and replies', () async {
    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: DemoLinks(chatter: const Duration(hours: 1), random: Random(1)),
    );
    final c = await app.connect(demoTarget);
    expect(c.radio!.name, 'Demo Radio');
    final nodes = await store.nodes(c.radio!.id);
    expect(nodes.map((n) => n.name), contains('Camp North'));
    expect(nodes.where((n) => n.position != null), hasLength(5));
    final channels = await store.channels(c.radio!.id);
    expect(channels.map((ch) => ch.name), containsAll(['Public', '#trail']));

    final camp = nodes.firstWhere((n) => n.name == 'Camp North');
    final dm = DirectConversation(c.radio!.id, camp.key);
    final id = await c.sendText(dm, 'hello from the demo');
    await Future<void>.delayed(const Duration(seconds: 9));
    final msgs = await store.messages(dm);
    expect(
      msgs.firstWhere((m) => m.id == id).message.delivery,
      isA<Delivered>(),
    );
    expect(msgs.where((m) => !m.message.outgoing), hasLength(1));
    await app.shutdown();
    await store.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the Meshtastic demo connects, acknowledges and replies', () async {
    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: DemoLinks(chatter: const Duration(hours: 1), random: Random(2)),
    );
    final c = await app.connect(demoMeshtasticTarget);
    expect(c.radio!.name, 'Demo Base');
    expect((c as MeshtasticConnection).regionUnset, isFalse);
    final nodes = await store.nodes(c.radio!.id);
    final hut = nodes.firstWhere((n) => n.name == 'Summit Hut');
    expect(hut.position, isNotNull);
    final dm = DirectConversation(c.radio!.id, hut.key);
    final id = await c.sendText(dm, 'hello mesh');
    await Future<void>.delayed(const Duration(seconds: 9));
    final msgs = await store.messages(dm);
    expect(
      msgs.firstWhere((m) => m.id == id).message.delivery,
      isA<Delivered>(),
    );
    expect(msgs.where((m) => !m.message.outgoing), hasLength(1));
    await app.shutdown();
    await store.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the demo never uses a real link', () {
    final link = DemoLinks().create(demoTarget);
    expect(link, isA<DemoMeshCoreLink>());
  });

  testWidgets('screen: the demo opens with its banner and closes', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DemoScreen(
                  links: DemoLinks(chatter: const Duration(hours: 1)),
                ),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('pretend radio'), findsOneWidget);
    expect(find.textContaining('Public'), findsWidgets);
    await t.tap(find.byKey(const Key('demo-exit')));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('go'), findsOneWidget);
  });
}
