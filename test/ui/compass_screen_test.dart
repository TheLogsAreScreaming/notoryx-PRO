import 'dart:async';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/heading.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/compass_screen.dart';

class _Sensors implements CompassSensors {
  _Sensors({this.compass = true, this.allowed, this.asked});

  final bool compass;
  final GeoPoint? allowed;
  final GeoPoint? asked;
  final heading = StreamController<HeadingReading>.broadcast(sync: true);
  var prompts = 0;

  @override
  Stream<HeadingReading>? headings() => compass ? heading.stream : null;

  @override
  Future<double?> declination(GeoPoint at) async => 0;

  @override
  Future<GeoPoint?> phonePositionIfAllowed() async => allowed;

  @override
  Future<GeoPoint?> phonePosition() async {
    prompts++;
    return asked;
  }
}

void main() {
  final node = Node(
    key: NodeKey.meshtastic(0x22),
    radioId: RadioId.meshtastic(0xa1),
    name: 'Ann',
    // About 1.1 km due east of the phone.
    position: const GeoPoint(0, 0.01),
  );

  Future<void> open(WidgetTester tester, CompassSensors sensors) async {
    late AppController app;
    await tester.runAsync(() async {
      app = AppController(store: MeshStore.memory());
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CompassScreen(app: app, node: node, sensors: sensors),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets('tells you which way to turn, and when you are on target', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final s = _Sensors(allowed: const GeoPoint(0, 0));
    await open(tester, s);
    expect(find.text('1.1 km'), findsOneWidget);
    expect(find.text("Measured from your phone's location"), findsOneWidget);
    expect(find.byKey(const Key('compass-use-phone')), findsNothing);

    s.heading.add((degrees: 0, accuracy: 3));
    await tester.pump();
    expect(find.text('Turn right 90°'), findsOneWidget);
    expect(find.text('Bearing 90° E'), findsOneWidget);

    s.heading.add((degrees: 180, accuracy: 3));
    await tester.pump();
    // Smoothed, so it moves part of the way; it still says to turn.
    expect(find.textContaining('Turn'), findsOneWidget);

    for (var i = 0; i < 40; i++) {
      s.heading.add((degrees: 88, accuracy: 3));
      await tester.pump();
    }
    expect(find.text('On target'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Ann, 1.1 km, On target')),
      findsOneWidget,
    );

    s.heading.add((degrees: 88, accuracy: 1));
    await tester.pump();
    expect(find.textContaining('needs calibrating'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
    await s.heading.close();
  });

  testWidgets('never prompts on open; the button asks', (tester) async {
    final s = _Sensors(compass: false, asked: const GeoPoint(0, 0));
    await open(tester, s);
    expect(s.prompts, 0);
    expect(find.textContaining("position isn't known"), findsOneWidget);

    await tester.tap(find.byKey(const Key('compass-use-phone')));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(s.prompts, 1);
    // No compass: north-up with a note, and the bearing in words.
    expect(find.text('Bearing 90° E'), findsOneWidget);
    expect(find.textContaining('No compass on this device'), findsOneWidget);
  });
}
