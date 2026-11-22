import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/themes.dart';

import 'accessibility_test.dart' show walk;
import 'screens_test.dart' show settle, tearDownApp;

/// Every distinct look.
List<(String, ThemeChoice)> looks() => [
  for (final id in AppThemeId.values) (id.name, ThemeChoice(id: id)),
];

void main() {
  group('colours stay readable', () {
    for (final (name, choice) in looks()) {
      for (final b in Brightness.values) {
        test('$name ${b.name}', () {
          final t = buildTheme(choice, b);
          final s = t.colorScheme;
          void aa(Color fg, Color bg, String what) => expect(
            contrastRatio(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: what,
          );
          for (final bg in [
            s.surface,
            s.surfaceContainerLow,
            s.surfaceContainerHighest,
          ]) {
            aa(s.onSurface, bg, 'onSurface');
            aa(s.onSurfaceVariant, bg, 'onSurfaceVariant');
            aa(s.error, bg, 'error');
            for (final p in RadioProtocol.values) {
              aa(meshColor(p, t), bg, p.name);
            }
          }
          aa(s.onPrimary, s.primary, 'onPrimary');
          aa(s.onPrimaryContainer, s.primaryContainer, 'onPrimaryContainer');
          aa(s.onError, s.error, 'onError');
        });
      }
    }

    test('emergency messages are neon green in every theme', () {
      for (final (name, choice) in looks()) {
        for (final b in Brightness.values) {
          final t = buildTheme(choice, b);
          final g = meshColors(t);
          final hue = HSLColor.fromColor(g.sos).hue;
          expect(hue, inInclusiveRange(90, 130), reason: '$name ${b.name}');
          expect(g.sosContainer, neonGreen);
          expect(
            contrastRatio(g.onSosContainer, g.sosContainer),
            greaterThanOrEqualTo(4.5),
          );
          for (final bg in [
            t.colorScheme.surface,
            t.colorScheme.surfaceContainerHighest,
          ]) {
            expect(contrastRatio(g.sos, bg), greaterThanOrEqualTo(4.5));
          }
        }
      }
    });

    test('emergency red stays red in every theme', () {
      for (final (name, choice) in looks()) {
        for (final b in Brightness.values) {
          final e = buildTheme(choice, b).colorScheme.error;
          final hsl = HSLColor.fromColor(e);
          expect(
            hsl.hue < 15 || hsl.hue > 345,
            isTrue,
            reason: '$name ${b.name} hue ${hsl.hue}',
          );
          expect(hsl.saturation, greaterThan(.5), reason: name);
        }
      }
    });
  });

  test('a saved choice round-trips; junk and removed looks fall back', () {
    for (final id in AppThemeId.values) {
      expect(ThemeChoice.decode(ThemeChoice(id: id).encode()).id, id);
    }
    // Saves from before BLACKOUT carried `;season;holidays`.
    expect(ThemeChoice.decode('nightOps;;off').id, AppThemeId.nightOps);
    expect(ThemeChoice.decode('blaze;winter;on').id, AppThemeId.blaze);
    // Looks that were removed land on BLACKOUT.
    expect(ThemeChoice.decode('seasonal;autumn;on').id, AppThemeId.blackout);
    expect(ThemeChoice.decode('pinkOverload;;off').id, AppThemeId.blackout);
    expect(ThemeChoice.decode('nope;x').id, AppThemeId.blackout);
    expect(ThemeChoice.decode('').id, AppThemeId.blackout);
    expect(ThemeChoice.decode(null).id, AppThemeId.blackout);
  });

  test('BLACKOUT is the default and uses the brand greys', () {
    expect(const ThemeChoice().id, AppThemeId.blackout);
    for (final b in Brightness.values) {
      final s = buildTheme(const ThemeChoice(), b).colorScheme;
      expect(s.brightness, Brightness.dark);
      expect(s.surface, blackoutMatte);
      expect(s.surfaceContainerHighest, blackoutCharcoal);
      expect(s.outlineVariant, blackoutGunmetal);
      expect(s.outline, blackoutSteel);
      expect(s.onSurface, blackoutFrost);
      expect(s.primary, blackoutFrost);
    }
  });

  test('dark-only themes ignore a light system setting', () {
    for (final id in [
      AppThemeId.blackout,
      AppThemeId.neonAnarchy,
      AppThemeId.nightOps,
    ]) {
      expect(
        buildTheme(ThemeChoice(id: id), Brightness.light).brightness,
        Brightness.dark,
      );
    }
  });

  test('screens take colours from the theme', () {
    final allowed = {'lib/ui/themes.dart'};
    final bad = <String>[];
    for (final f in Directory('lib/ui').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (allowed.contains(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        // QR codes need a white quiet zone to scan, whatever the theme.
        if (l.contains('Colors.white') &&
            lines
                .sublist(i, (i + 4).clamp(0, lines.length))
                .any((x) => x.contains('padding'))) {
          continue;
        }
        if (RegExp(r'\bColors\.|\bColor\(0x').hasMatch(l)) {
          bad.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty);
  });

  for (final id in AppThemeId.values) {
    for (final b in Brightness.values) {
      testWidgets('${id.name} ${b.name}: screens pass contrast', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = b;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final handle = tester.ensureSemantics();
        final problems = <String>[];
        await walk(tester, (where) async {
          final r = await textContrastGuideline.evaluate(tester);
          if (!r.passed) problems.add('$where: ${r.reason}');
        }, theme: ThemeChoice(id: id));
        handle.dispose();
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }

  testWidgets('picking a theme saves it and recolours the app', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.byKey(const Key('inbox-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final before = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .colorScheme
        .primary;
    await tester.tap(find.byKey(const Key('theme-blaze')));
    await settle(tester);
    expect(
      await tester
          .runAsync(() => ThemeChoice.load(app.store))
          .then((c) => c!.id),
      AppThemeId.blaze,
    );
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      isNot(before),
    );
    expect(tester.takeException(), isNull);
    await tearDownApp(tester, app);
  });
}
