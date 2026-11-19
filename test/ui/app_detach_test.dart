import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';

import '../support/scripted_meshtastic.dart';
import 'screens_test.dart' show FakeLinks, tearDownApp;

void main() {
  testWidgets('radios are disconnected when the app is detached', (
    tester,
  ) async {
    final link = ScriptedMeshtasticLink();
    final app = AppController(
      store: MeshStore.memory(),
      links: FakeLinks(link),
    );
    await tester.runAsync(
      () => app.connect(
        const TcpTarget(host: 'node', protocol: RadioProtocol.meshtastic),
      ),
    );
    await tester.pumpWidget(
      DisconnectOnDetach(app: app, child: const SizedBox()),
    );
    expect(app.connections, hasLength(1));
    expect(link.state, LinkState.connected);

    // What Android reports when Back finishes the activity and its engine.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(app.connections, isEmpty);
    expect(link.state, LinkState.disconnected);
    await tearDownApp(tester, app);
  });

  test('Bluetooth links are closed when the engine detaches', () {
    expect(
      UniversalBleBackend.connectOptions.android?.closeGattOnDetach,
      isTrue,
    );
  });
}
