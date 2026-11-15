import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/elevation.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/ui/line_of_sight_sheet.dart';

class _FakeLookup implements ElevationLookup {
  _FakeLookup(this.answer);

  final List<double> Function(int count) answer;
  final asked = <List<GeoPoint>>[];
  Completer<void>? gate;

  @override
  Future<List<double>> heights(List<GeoPoint> points) async {
    asked.add(points);
    if (gate case final g?) await g.future;
    return answer(points.length);
  }
}

class _FailingLookup implements ElevationLookup {
  @override
  Future<List<double>> heights(List<GeoPoint> points) async =>
      throw const ElevationException('offline');
}

const _ends = [
  ('Your radio', GeoPoint(45.0, 7.0)),
  ('Ridge', GeoPoint(45.05, 7.05)),
  ('Valley', GeoPoint(45.1, 7.0)),
];

Future<void> _pump(WidgetTester tester, ElevationLookup lookup) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LineOfSightSheet(
          ends: _ends,
          frequencyMHz: 869.5,
          elevation: lookup,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('fetches nothing until Check terrain is tapped', (tester) async {
    final lookup = _FakeLookup((n) => List.filled(n, 100));
    await _pump(tester, lookup);
    expect(find.text('Line of sight'), findsOneWidget);
    expect(find.textContaining('Nothing is sent until you tap'), findsOne);
    expect(lookup.asked, isEmpty);
    expect(find.byKey(const Key('los-profile')), findsNothing);
  });

  testWidgets('flat ground with masts shows clear and the profile', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final lookup = _FakeLookup((n) => List.filled(n, 100));
    await _pump(tester, lookup);
    await tester.enterText(find.byKey(const Key('los-antenna-from')), '40');
    await tester.enterText(find.byKey(const Key('los-antenna-to')), '40');
    await tester.tap(find.byKey(const Key('los-check-terrain')));
    await tester.pumpAndSettle();
    expect(lookup.asked, hasLength(1));
    expect(lookup.asked.single.first.latitude, 45.0);
    expect(lookup.asked.single.last.latitude, closeTo(45.05, 1e-9));
    expect(find.byKey(const Key('los-profile')), findsOneWidget);
    expect(find.textContaining('Clear:'), findsOneWidget);
    expect(find.textContaining('Open-Meteo (Copernicus'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a hill in the middle is blocked', (tester) async {
    final lookup = _FakeLookup(
      (n) => [for (var i = 0; i < n; i++) i == n ~/ 2 ? 600.0 : 100.0],
    );
    await _pump(tester, lookup);
    await tester.tap(find.byKey(const Key('los-check-terrain')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Blocked:'), findsOneWidget);
    expect(find.textContaining('Ground rises'), findsOneWidget);
  });

  testWidgets('changing an end drops a stale profile', (tester) async {
    final lookup = _FakeLookup((n) => List.filled(n, 100));
    await _pump(tester, lookup);
    await tester.tap(find.byKey(const Key('los-check-terrain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('los-profile')), findsOneWidget);
    await tester.tap(find.text('Ridge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valley').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('los-profile')), findsNothing);
  });

  testWidgets('a failed lookup says so', (tester) async {
    await _pump(tester, _FailingLookup());
    await tester.tap(find.byKey(const Key('los-check-terrain')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't get ground heights"), findsOne);
  });
}
