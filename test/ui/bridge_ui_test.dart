import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/bridge_screen.dart';

import '../app/channels_test.dart' show ChannelCompanion;
import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

class BothLinks extends LinkFactory {
  BothLinks(this.meshCore, this.meshtastic);
  final RadioLink meshCore;
  final RadioLink meshtastic;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) =>
      target.protocol == RadioProtocol.meshcore ? meshCore : meshtastic;
}

void main() {
  testWidgets('add a bridge, confirm it, and a message crosses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: BothLinks(
        ScriptedMeshCoreLink(responder: ChannelCompanion().call),
        ScriptedMeshtasticLink(),
      ),
    );
    final mc = (await tester.runAsync(
      () => app.connect(
        const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
      ),
    ))!;
    final mt = (await tester.runAsync(
      () => app.connect(
        const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
      ),
    ))!;
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BridgeScreen(app: app),
      ),
    );
    await settle();
    expect(find.text('No bridges yet.'), findsOneWidget);

    await tester.tap(find.byTooltip('Add a bridge'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('bridge-meshcore-false')));
    await settle();
    await tester.tap(find.text('Public').last);
    await settle();
    await tester.tap(find.byKey(const ValueKey('bridge-meshtastic-false')));
    await settle();
    await tester.tap(find.text('Trail').last);
    await settle();
    await tester.tap(find.text('Save'));
    await settle();

    expect(find.text('Public ↔ Trail'), findsOneWidget);
    expect(app.bridge.links.single.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await settle();
    expect(find.text('Turn on this bridge?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();
    expect(app.bridge.links.single.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await settle();
    await tester.tap(find.text('Turn on'));
    await settle();
    expect(app.bridge.links.single.enabled, isTrue);

    final link = app.bridge.links.single;
    final now = DateTime.now();
    await tester.runAsync(() async {
      await store.addMessage(
        Message(
          conversation: link.a,
          text: 'over the ridge',
          outgoing: false,
          sentAt: now,
          receivedAt: now,
          delivery: const Received(),
          senderName: 'Ann',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await app.bridge.idle;
    });
    await settle();
    expect(link.a.radioId, mc.radio!.id);
    expect(link.b.radioId, mt.radio!.id);
    final sent = (await tester.runAsync(() => store.messages(link.b)))!;
    expect(sent.single.message.text, '[MC Ann] over the ridge');
    expect(sent.single.message.outgoing, isTrue);
    expect(find.textContaining('1 copied, 0 held back'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(app.shutdown);
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });
}
