import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/app_lock.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/auto_reply_screen.dart';
import 'package:notoryx_pro/ui/lock_gate.dart';
import 'package:notoryx_pro/ui/places_screen.dart';
import 'package:notoryx_pro/ui/theme_screen.dart';
import 'package:notoryx_pro/ui/themes.dart';

class NoAuth implements DeviceAuth {
  @override
  Future<bool> available() async => true;
  @override
  Future<UnlockResult> unlock(String reason) async => UnlockResult.failed;
}

void main() {
  final screens = <String, Widget Function(AppController)>{
    'places': (a) => PlacesScreen(app: a),
    'themes': (a) => ThemeScreen(store: a.store),
    'auto-replies': (a) => AutoReplyScreen(store: a.store),
    'app lock': (a) => LockSettingsScreen(store: a.store, auth: NoAuth()),
  };

  Future<void> show(
    WidgetTester t,
    AppController app,
    Widget Function(AppController) build,
    Brightness b,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(const ThemeChoice(), b),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: build(app),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> finish(WidgetTester t, MeshStore store) async {
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  }

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final b in Brightness.values) {
      testWidgets('$name ${b.name}: tap size, labels, contrast', (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final handle = t.ensureSemantics();
        final store = MeshStore.memory();
        await show(t, AppController(store: store), build, b);
        final problems = <String>[];
        for (final g in [
          androidTapTargetGuideline,
          labeledTapTargetGuideline,
          textContrastGuideline,
        ]) {
          final r = await g.evaluate(t);
          if (!r.passed) problems.add(r.reason ?? '');
        }
        handle.dispose();
        await finish(t, store);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }

    testWidgets('$name: double-size text fits', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearAllTestValues);
      final store = MeshStore.memory();
      await show(t, AppController(store: store), build, Brightness.light);
      expect(t.takeException(), isNull);
      await finish(t, store);
    });
  }
}
