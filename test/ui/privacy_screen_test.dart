import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/app_lock.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/privacy_screen.dart';

/// Lets the store's streams deliver, then draws. Not pumpAndSettle: the
/// services this page listens to keep timers running, so it never settles.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'a fresh install shares nothing, and says so in words',
    timeout: const Timeout(Duration(minutes: 2)),
    (t) async {
      t.view.physicalSize = const Size(420, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = MeshStore.memory();
      final app = AppController(store: store);
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacyScreen(app: app),
        ),
      );
      await settle(t);

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
      await settle(t);
      expect(stateOf('privacy-lock'), 'On');

      // Unmount first, so no drift stream is open while the store closes.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(() async {
        await app.shutdown();
        await store.close();
      });
    },
  );
}
