import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/themes.dart';
import 'package:notoryx_pro/ui/traffic_layer.dart';

import 'screens_test.dart' show settle, tearDownApp;

final mc = RadioId.meshcore('aa' * 32);
final t0 = DateTime.utc(2026, 11, 18, 12);

TrafficRoute sampleRoute({TrafficKind kind = TrafficKind.direct}) {
  Node n(String k, String name, {GeoPoint? at}) => Node(
    key: NodeKey.meshcore(k.padRight(64, '0')),
    radioId: mc,
    name: name,
    position: at,
  );
  return buildTrafficRoute(
    HeardPacket(
      time: t0,
      radioId: mc,
      kind: kind,
      label: 'Request',
      origin: const HopId('ee', HopMatch.prefix),
      hops: const [HopId('a1', HopMatch.prefix), HopId('b2', HopMatch.prefix)],
      hopCount: 2,
      snr: 12.25,
      rssi: -38,
    ),
    [
      n('ee', 'Solar 1', at: const GeoPoint(39.3, -77.3)),
      n('a1', 'Redden', at: const GeoPoint(39.2, -77.2)),
      n('b2', 'Hidden Hill'),
    ],
    selfLabel: 'Base',
    selfAt: const GeoPoint(39, -77),
  );
}

Widget wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('route card shows route, type, signal and hops off the map', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TrafficCard(
          route: sampleRoute(),
          now: t0.add(const Duration(seconds: 3)),
        ),
      ),
    );
    expect(find.text('Solar 1 → Redden → Hidden Hill → Base'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Heard from Hidden Hill · 12.25 dB'), findsOneWidget);
    expect(
      find.text('Flood 2 · -38 dBm · SNR 12.25 · 1 not on map · 3s'),
      findsOneWidget,
    );
    expect(find.text('Not on map: Hidden Hill'), findsOneWidget);
    for (final label in [
      'Advert',
      'Direct message',
      'Channel message',
      'Acknowledgement',
      'Trace',
      'Path',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('route card waits for packets', (tester) async {
    await tester.pumpWidget(wrap(TrafficCard(route: null, now: t0)));
    expect(find.text('Listening for packets…'), findsOneWidget);
  });

  test('each packet kind has its own colour', () {
    final colours = TrafficKind.values.map(trafficColor).toSet();
    expect(colours.length, TrafficKind.values.length);
  });

  testWidgets('player runs three routes at once and queues the rest', (
    tester,
  ) async {
    final player = TrafficPlayer(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    for (var i = 0; i < 5; i++) {
      player.play(sampleRoute());
    }
    expect(player.active.length, 3);
    expect(player.queued, 2);
    await tester.pump(); // tickers start on the next frame
    await tester.pump(const Duration(milliseconds: 1100));
    expect(player.active.length, 2);
    expect(player.queued, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(player.active, isEmpty);
  });

  test('a route with one located stop is not played', () {
    final player = TrafficPlayer(vsync: const TestVSync());
    addTearDown(player.dispose);
    final lonely = buildTrafficRoute(
      HeardPacket(time: t0, radioId: mc, kind: TrafficKind.ack, label: 'Ack'),
      const [],
      selfLabel: 'Base',
      selfAt: const GeoPoint(39, -77),
    );
    player.play(lonely);
    expect(player.active, isEmpty);
  });

  group('animation frames', () {
    test('the packet crosses each leg in turn, then fades', () {
      final start = RouteFrame(0, legs: 3);
      expect(start.leg, 0);
      expect(start.opacity, 1);
      expect(start.arrived, isFalse);
      final mid = RouteFrame(.3, legs: 3); // halfway through travel
      expect(mid.leg, 1);
      expect(mid.legProgress, closeTo(.5, 1e-9));
      final there = RouteFrame(.6, legs: 3);
      expect(there.arrived, isTrue);
      expect(there.opacity, 1);
      final fading = RouteFrame(.8, legs: 3);
      expect(fading.opacity, closeTo(.5, 1e-9));
      expect(RouteFrame(1, legs: 3).opacity, 0);
    });

    test('reduce motion draws the whole line at once and fades it', () {
      final f = RouteFrame(0, legs: 3, reduceMotion: true);
      expect(f.arrived, isTrue);
      expect(f.opacity, 1);
      expect(RouteFrame(.5, legs: 3, reduceMotion: true).opacity, .5);
    });
  });

  testWidgets('map toolbar turns Traffic on and filters packet types', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await tester.tap(find.text('Map'));
    await settle(tester);
    for (final key in [
      'map-locate',
      'map-advert',
      'map-filter',
      'map-traffic',
      'map-search',
      'map-fit',
      'map-options',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('traffic-card')), findsNothing);

    await tester.tap(find.byKey(const Key('map-traffic')));
    await tester.pump();
    expect(find.byKey(const Key('traffic-card')), findsOneWidget);
    expect(find.text('Listening for packets…'), findsOneWidget);
    expect(find.byType(TrafficMapLayer), findsOneWidget);

    await tester.tap(find.byKey(const Key('map-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Packet types to show'), findsOneWidget);
    await tester.tap(find.byKey(const Key('traffic-kind-advert')));
    await tester.pump();
    final box = tester.widget<CheckboxListTile>(
      find.byKey(const Key('traffic-kind-advert')),
    );
    expect(box.value, isFalse);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('map-traffic')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('traffic-card')), findsNothing);
    await tearDownApp(tester, app);
  });
}
