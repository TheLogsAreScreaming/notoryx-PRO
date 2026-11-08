import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/meshtastic_modules_screen.dart';

import '../support/scripted_meshtastic.dart';

class OneLink extends LinkFactory {
  OneLink(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

void main() {
  test('each module asks the node for its own section number', () {
    expect(SectionKind.mqtt.requestType, 0);
    expect(SectionKind.externalNotification.requestType, 2);
    expect(SectionKind.neighborInfo.requestType, 9);
    expect(SectionKind.paxcounter.requestType, 12);
    expect(SectionKind.values.every((k) => !k.module || k.field > 0), isTrue);
  });

  testWidgets('edits one module and leaves unknown fields alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = ScriptedMeshtasticLink();
    final node = FakeAdminNode(link.myNode);
    node.sections[SectionKind.mqtt] =
        (ProtoWriter()
              ..string(2, 'mqtt.example')
              ..bytes(11, [8, 60]))
            .toBytes();
    link.onPacket = (p) => node(p, myNode: link.myNode);
    final store = MeshStore.memory();
    final app = AppController(store: store, links: OneLink(link));
    final c =
        (await tester.runAsync(
              () => app.connect(
                const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
              ),
            ))!
            as MeshtasticConnection;
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
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
        home: MeshtasticModulesScreen(connection: c),
      ),
    );
    await tester.tap(find.text('MQTT'));
    await settle();
    expect(find.text('mqtt.example'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mod-1')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('mod-8')), 'x' * 32);
    await tester.pump();
    expect(find.text('At most 31 bytes'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mod-8')), 'msh/US');
    await tester.pump();

    await tester.tap(find.byKey(const Key('mod-save')));
    await settle();
    await tester.tap(find.text('Save to radio').last);
    await settle();

    final saved = SettingsSection(
      SectionKind.mqtt,
      node.sections[SectionKind.mqtt]!,
    );
    expect(saved.flag(1), isTrue);
    expect(saved.text(2), 'mqtt.example');
    expect(saved.text(8), 'msh/US');
    expect(readFields(saved.raw).where((f) => f.number == 11).single.asBytes, [
      8,
      60,
    ], reason: 'map report settings are kept as received');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(app.shutdown);
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });
}
