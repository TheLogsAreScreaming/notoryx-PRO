import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/nearby_sheet.dart';

import '../support/scripted_meshcore.dart';

class _Links extends LinkFactory {
  _Links(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

void main() {
  testWidgets('one tap lists the repeaters that answered', (tester) async {
    final handle = tester.ensureSemantics();
    final link = ScriptedMeshCoreLink(
      responder: (cmd) => switch (cmd.first) {
        Cmd.appStart => [RadioFrames.selfInfo()],
        Cmd.deviceQuery => [RadioFrames.deviceInfo()],
        Cmd.setDeviceTime => [RadioFrames.ok()],
        Cmd.getContacts => [
          RadioFrames.contactsStart(1),
          RadioFrames.contact(seed: 0x30, name: 'Peak', type: 2),
          RadioFrames.endOfContacts(1),
        ],
        Cmd.getChannel => [RadioFrames.err(2)],
        Cmd.syncNextMessage => [RadioFrames.noMore()],
        Cmd.sendControlData => [
          RadioFrames.ok(),
          (ByteWriter()
                ..u8(Push.controlData)
                ..u8(24)
                ..u8(-90)
                ..u8(0)
                ..u8(0x92)
                ..u8(-8)
                ..bytes(cmd.sublist(3, 7))
                ..bytes(RadioFrames.key(0x30)))
              .toBytes(),
        ],
        _ => [RadioFrames.err(1)],
      },
    );
    final store = MeshStore.memory();
    late AppController app;
    late RadioConnection c;
    await tester.runAsync(() async {
      app = AppController(store: store, links: _Links(link));
      c = await app.connect(
        const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NearbySheet(
            connection: c,
            listen: const Duration(milliseconds: 50),
          ),
        ),
      ),
    );
    expect(find.text('Nearby repeater test'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.text('Test now'));
    await tester.pump();
    expect(find.textContaining('Listening for answers'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('1 answer'), findsOneWidget);
    expect(find.text('Peak'), findsOneWidget);
    expect(find.textContaining('it hears you: SNR -2.0 dB'), findsOneWidget);
    expect(
      find.textContaining('you hear it: SNR 6.0 dB, -90 dBm'),
      findsOneWidget,
    );
    // Spaced out so repeaters aren't asked too often.
    expect(find.textContaining('Wait'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
    handle.dispose();
  });
}
