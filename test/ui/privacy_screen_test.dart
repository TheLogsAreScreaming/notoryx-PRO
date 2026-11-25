import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/app_lock.dart';
import 'package:notoryx_pro/demo/demo_radio.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/privacy_screen.dart';

void main() {
  testWidgets('a fresh install shares nothing, and says so in words', (
    t,
  ) async {
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MeshStore.memory();
    final app = AppController(store: store, links: DemoLinks());
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyScreen(app: app),
      ),
    );
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();

    String stateOf(String key) {
      final row = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(ListTile),
      );
      expect(row, findsOneWidget, reason: key);
      final tile = t.widget<ListTile>(row);
      return (tile.trailing! as Text).data!;
    }

    expect(find.text('Privacy'), findsOneWidget);
    for (final k in [
      'privacy-coverage',
      'privacy-moderation',
      'privacy-webhooks',
      'privacy-lock',
    ]) {
      expect(stateOf(k), 'Off', reason: k);
    }
    expect(stateOf('privacy-feeds'), 'Off');
    expect(stateOf('privacy-bridge'), 'Off');
    expect(stateOf('privacy-tiles'), 'Always');
    // No vault in tests: encryption isn't available here.
    expect(stateOf('privacy-encryption'), 'Not on this device');

    // Turning App lock on shows straight away.
    await t.runAsync(
      () => store.setPreference(
        LockSettings.prefName,
        const LockSettings(on: true).encode(),
      ),
    );
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();
    expect(stateOf('privacy-lock'), 'On');

    await t.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
  });
}
