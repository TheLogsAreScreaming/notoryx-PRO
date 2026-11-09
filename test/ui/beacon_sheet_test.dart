import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/beacon_sheet.dart';

import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

void main() {
  testWidgets('needs a second confirm; banner shows it and stops it', (
    t,
  ) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: FakeLinks(ScriptedMeshtasticLink()),
    );
    final RadioConnection c = (await t.runAsync(
      () => app.connect(
        const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
      ),
    ))!;
    final chat = ChannelConversation(c.radio!.id, 0);
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
        home: Scaffold(
          body: Column(
            children: [
              BeaconBanner(app: app),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showBeaconSheet(
                    context,
                    app: app,
                    connection: c,
                    conversation: chat,
                  ),
                  child: const Text('go'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await settle();
    await t.tap(find.byKey(const Key('beacon-drill')));
    await settle();
    await t.tap(find.byKey(const Key('beacon-start')));
    await settle();
    expect(app.beacon.value, isNull, reason: 'not before confirming');
    await t.tap(find.byKey(const Key('beacon-confirm')));
    await settle();
    expect(app.beacon.value, isNotNull);
    expect(find.byKey(const Key('beacon-stop')), findsOneWidget);
    final sent = (await t.runAsync(() => store.messages(chat)))!;
    expect(MecpMessage.tryParse(sent.last.message.text)!.isDrill, isTrue);

    await t.tap(find.byKey(const Key('beacon-stop')));
    await settle();
    expect(app.beacon.value, isNull);
    expect(find.byKey(const Key('beacon-stop')), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.runAsync(app.shutdown);
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
