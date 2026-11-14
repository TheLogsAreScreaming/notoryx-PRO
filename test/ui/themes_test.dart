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

/// Every distinct look: each theme, each season, each holiday.
List<(String, ThemeChoice, DateTime)> looks() => [
  for (final id in AppThemeId.values)
    if (id != AppThemeId.seasonal)
      (id.name, ThemeChoice(id: id), DateTime(2026)),
  for (final s in Season.values)
    (s.name, ThemeChoice(id: AppThemeId.seasonal, season: s), DateTime(2026)),
  for (final (h, d) in [
    ('independence', DateTime(2026, 7, 4)),
    ('halloween', DateTime(2026, 10, 31)),
    ('winter holidays', DateTime(2026, 12, 25)),
    ('new year', DateTime(2027)),
  ])
    (h, const ThemeChoice(id: AppThemeId.seasonal, holidays: true), d),
];

void main() {
  group('colours stay readable', () {
    for (final (name, choice, date) in looks()) {
      for (final b in Brightness.values) {
        test('$name ${b.name}', () {
          final t = buildTheme(choice, b, now: date);
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
      for (final (name, choice, date) in looks()) {
        for (final b in Brightness.values) {
          final t = buildTheme(choice, b, now: date);
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
      for (final (name, choice, date) in looks()) {
        for (final b in Brightness.values) {
          final e = buildTheme(choice, b, now: date).colorScheme.error;
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

  group('seasons', () {
    test('months map to seasons', () {
      expect(seasonOf(DateTime(2026, 3)), Season.spring);
      expect(seasonOf(DateTime(2026, 8, 31)), Season.summer);
      expect(seasonOf(DateTime(2026, 11, 30)), Season.autumn);
      expect(seasonOf(DateTime(2026, 12)), Season.winter);
      expect(seasonOf(DateTime(2026, 2, 28)), Season.winter);
    });

    test('holidays are off unless asked for, and yield to a fixed season', () {
      final halloween = DateTime(2026, 10, 31);
      expect(holidayOf(halloween), Holiday.halloween);
      expect(holidayOf(DateTime(2026, 10, 24)), isNull);
      Color seed(ThemeChoice c) =>
          buildTheme(c, Brightness.light, now: halloween).colorScheme.primary;
      const auto = ThemeChoice(id: AppThemeId.seasonal);
      const fixed = ThemeChoice(
        id: AppThemeId.seasonal,
        season: Season.autumn,
        holidays: true,
      );
      const on = ThemeChoice(id: AppThemeId.seasonal, holidays: true);
      expect(seed(auto), seed(fixed));
      expect(seed(on), isNot(seed(auto)));
    });
  });

  test('a saved choice round-trips; junk falls back to Blaze', () {
    const c = ThemeChoice(
      id: AppThemeId.seasonal,
      season: Season.winter,
      holidays: true,
    );
    final back = ThemeChoice.decode(c.encode());
    expect((back.id, back.season, back.holidays), (c.id, c.season, true));
    expect(ThemeChoice.decode('nope;x').id, AppThemeId.blaze);
    expect(ThemeChoice.decode(null).id, AppThemeId.blaze);
  });

  test('dark-only themes ignore a light system setting', () {
    for (final id in [AppThemeId.neonAnarchy, AppThemeId.nightOps]) {
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
    await tester.tap(find.byKey(const Key('theme-seasonal')));
    await settle(tester);
    expect(
      await tester
          .runAsync(() => ThemeChoice.load(app.store))
          .then((c) => c!.id),
      AppThemeId.seasonal,
    );
    expect(find.text('Holiday colours'), findsOneWidget);
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
