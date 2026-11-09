import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/geofence_alerts.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/gpx.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/places.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/places_screen.dart';

import 'alerts_test.dart' show FakeNotifier;

const sample = '''<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="45.5" lon="-122.5"><ele>100</ele><name>Hut &amp; spring</name></wpt>
  <wpt lat="999" lon="0"><name>bad</name></wpt>
  <rte><name>Up</name><rtept lat="1" lon="2"/><rtept lat="3" lon="4"/></rte>
  <trk><name>T</name><trkseg><trkpt lat="5" lon="6"/></trkseg>
  <trkseg><trkpt lat="7" lon="8"/></trkseg></trk>
</gpx>''';

Node node(double lat) => Node(
  key: NodeKey.meshtastic(1),
  radioId: RadioId.meshtastic(2),
  name: 'Ann',
  position: GeoPoint(lat, 0),
);

void main() {
  group('GPX', () {
    test('reads waypoints, routes and joined track segments', () {
      final p = parseGpx(sample);
      expect(p.map((x) => (x.kind, x.name)), [
        (PlaceKind.waypoint, 'Hut & spring'),
        (PlaceKind.route, 'Up'),
        (PlaceKind.route, 'T'),
      ]);
      expect(p.first.points.single.altitude, 100);
      expect(p.last.points, hasLength(2));
    });

    test('round trips, with geofences', () {
      final back = parseGpx(
        writeGpx([
          ...parseGpx(sample),
          const Place(
            kind: PlaceKind.geofence,
            name: 'Camp',
            points: [GeoPoint(1, 2)],
            radiusM: 250,
          ),
        ]),
      );
      expect(
        back.where((x) => x.kind == PlaceKind.geofence).single.radiusM,
        250,
      );
      expect(back.where((x) => x.kind == PlaceKind.route), hasLength(2));
      expect(back.map((x) => x.name), contains('Hut & spring'));
    });

    test('refuses other files', () {
      expect(() => parseGpx('nope'), throwsA(isA<NotGpx>()));
      expect(() => parseGpx('<kml/>'), throwsA(isA<NotGpx>()));
    });

    test('long tracks are capped', () {
      final pts = List.filled(6000, '<trkpt lat="1" lon="2"/>').join();
      final p = parseGpx('<gpx><trk><trkseg>$pts</trkseg></trk></gpx>');
      expect(p.single.points, hasLength(maxRoutePoints));
    });
  });

  test('link budget matches the free-space formula', () {
    final b = LinkBudget.estimate(
      distanceKm: 10,
      frequencyMHz: 915,
      txDbm: 22,
      antennaGainDb: 4,
      sensitivityDbm: -124,
    );
    expect(b.pathLossDb, closeTo(111.67, .05));
    expect(b.marginDb, closeTo(38.33, .05));
  });

  group('geofence alerts', () {
    late MeshStore store;
    late FakeNotifier n;
    late GeofenceAlerts g;
    late DateTime now;

    setUp(() async {
      store = MeshStore.memory();
      await store.addPlaces(const [
        Place(
          kind: PlaceKind.geofence,
          name: 'Camp',
          points: [GeoPoint(0, 0)],
          radiusM: 1000,
        ),
      ]);
      n = FakeNotifier();
      now = DateTime(2026);
      g = GeofenceAlerts(store: store, notifier: n, now: () => now)..start();
      await pumpEventQueue(times: 200);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    tearDown(() async {
      g.stop();
      await store.close();
    });

    // 0.001 degrees is about 111 m.
    test('first sighting is silent, then crossings notify', () {
      g.check([node(.05)]);
      expect(n.shown, isEmpty);
      g.check([node(.001)]);
      expect(n.shown.single.body, 'Ann entered Camp');
      now = now.add(const Duration(minutes: 6));
      g.check([node(.05)]);
      expect(n.shown.last.body, 'Ann left Camp');
    });

    test('hovering at the edge does not flap', () {
      g.check([node(.001)]);
      g.check([node(.0095)]); // 1056 m: past the edge, within the 10%.
      expect(n.shown, isEmpty);
    });

    test('rapid crossings are limited', () {
      g.check([node(.05)]);
      g.check([node(.001)]);
      g.check([node(.05)]);
      expect(n.shown, hasLength(1));
    });
  });

  testWidgets('screen: import a file, delete a place', (t) async {
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MeshStore.memory();
    final app = AppController(store: store);
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlacesScreen(app: app, pick: () async => sample),
      ),
    );
    await settle();
    await t.tap(find.text('Import GPX file'));
    await settle();
    expect(find.text('Hut & spring'), findsOneWidget);
    await t.tap(find.byTooltip('Delete Up'));
    await settle();
    expect(find.text('Up'), findsNothing);
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
