import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/common.dart';

import 'screens_test.dart' show seed, settle, tearDownApp;

/// Opens each tab and a conversation, running [check] on each.
Future<void> walk(
  WidgetTester tester,
  Future<void> Function(String where) check,
) async {
  final app = AppController(store: MeshStore.memory());
  await tester.runAsync(() => seed(app.store));
  await tester.pumpWidget(NotoryxProApp(app: app));
  await settle(tester);
  await check('inbox');
  for (final tab in ['Nodes', 'Map', 'Radios']) {
    await tester.tap(find.text(tab).last);
    await settle(tester);
    await check(tab);
  }
  await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
  await settle(tester);
  await tester.scrollUntilVisible(find.text('Ridge Relay'), 150);
  await tester.tap(find.text('Ridge Relay').first);
  await settle(tester);
  await check('conversation');
  await tearDownApp(tester, app);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: tap targets, labels and contrast', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final handle = tester.ensureSemantics();
      final problems = <String>[];
      await walk(tester, (where) async {
        for (final (name, guide) in [
          ('tap size', androidTapTargetGuideline),
          ('label', labeledTapTargetGuideline),
          ('contrast', textContrastGuideline),
        ]) {
          final r = await guide.evaluate(tester);
          if (!r.passed) problems.add('$where/$name: ${r.reason}');
        }
      });
      handle.dispose();
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  test('mesh colours are readable as text in both themes', () {
    double ratio(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (max(x, y) + .05) / (min(x, y) + .05);
    }

    for (final b in Brightness.values) {
      final s = ColorScheme.fromSeed(seedColor: notoryxBlue, brightness: b);
      for (final p in RadioProtocol.values) {
        expect(
          ratio(protocolColor(p, s), s.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${p.name} on ${b.name}',
        );
      }
    }
  });

  testWidgets('double-size text fits on a small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await walk(tester, (where) async {
      expect(tester.takeException(), isNull, reason: where);
    });
  });
}
