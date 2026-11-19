import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/ignored_nodes.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/stale.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/range_rings_layer.dart';

import 'screens_test.dart' show settle, tearDownApp;

final mt = RadioId.meshtastic(0xa1b2c3d4);
final fresh = NodeKey.meshtastic(0x0a);
final old = NodeKey.meshtastic(0x0b);

Future<void> seedNodes(MeshStore store) async {
  final now = DateTime.now();
  await store.upsertNodes([
    Node(
      key: fresh,
      radioId: mt,
      name: 'Fresh Fern',
      kind: NodeKind.person,
      position: const GeoPoint(46.0, -121.0),
      lastHeard: now.subtract(const Duration(minutes: 5)),
    ),
    Node(
      key: old,
      radioId: mt,
      name: 'Old Oak',
      kind: NodeKind.person,
      position: const GeoPoint(46.6, -121.9),
      lastHeard: now.subtract(const Duration(days: 3, hours: 2)),
    ),
  ]);
}

void main() {
  testWidgets('a node unheard for a day is marked stale, with an icon', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seedNodes(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Nodes'));
    await settle(tester);
    expect(find.text('stale · 3 d'), findsOneWidget);
    expect(find.byIcon(Icons.history_toggle_off), findsOneWidget);

    // Off: nothing is stale.
    await tester.runAsync(
      () => app.store.setPreference(StaleAfter.pref, StaleAfter.encode(null)),
    );
    await settle(tester);
    expect(find.textContaining('stale'), findsNothing);

    // 1 h: only Old Oak; Fresh Fern was heard 5 minutes ago.
    await tester.runAsync(
      () => app.store.setPreference(
        StaleAfter.pref,
        StaleAfter.encode(const Duration(hours: 1)),
      ),
    );
    await settle(tester);
    expect(find.textContaining('stale'), findsOneWidget);

    // On the map its pin is faded.
    await tester.tap(find.text('Map'));
    await settle(tester);
    expect(find.byKey(const Key('pin-stale')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Old Oak.*stale')), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('ignore from the node sheet hides it; show again restores', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seedNodes(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Map'));
    await settle(tester);

    // Open its details through map search.
    await tester.tap(find.byKey(const Key('map-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('map-search-field')), 'Fern');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Fresh Fern'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sheet-ignore')));
    await tester.tap(find.byKey(const Key('sheet-ignore')));
    await tester.pumpAndSettle();
    expect(find.text('Ignore Fresh Fern?'), findsOneWidget);
    expect(find.textContaining('still saved'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ignore-confirm')));
    await settle(tester);
    expect(await tester.runAsync(() => IgnoredNodes.read(app.store)), {
      fresh.toString(),
    });
    expect(find.text('Stop ignoring'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.bySemanticsLabel('Fresh Fern, Meshtastic'), findsNothing);

    await tester.tap(find.text('Nodes'));
    await settle(tester);
    expect(find.text('Fresh Fern'), findsNothing);
    expect(find.text('Old Oak'), findsOneWidget);

    // Settings → Ignored nodes → Show again.
    await tester.tap(find.byKey(const Key('inbox-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-ignored-nodes')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Fresh Fern'), findsOneWidget);
    await tester.tap(find.byKey(Key('show-again-$fresh')));
    await settle(tester);
    expect(find.text("You aren't ignoring any nodes."), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Fresh Fern'), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('stale setting is picked from the menu', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.byKey(const Key('inbox-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-stale-after')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Mark nodes stale after'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('7 d'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stale-${3 * 24 * 60}')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(
      await tester.runAsync(() => app.store.preference(StaleAfter.pref)),
      '${3 * 24 * 60}',
    );
    await tearDownApp(tester, app);
  });

  testWidgets('range rings without your position say so', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await tester.tap(find.text('Map'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('map-rings')));
    await settle(tester);
    expect(find.textContaining('range rings'), findsOneWidget);
    expect(
      await tester.runAsync(() => app.store.preference('map.rangeRings')),
      '1',
    );
    expect(find.byKey(const Key('range-rings')), findsNothing);
    await tearDownApp(tester, app);
  });

  testWidgets('range rings label each ring and the compass points', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const at = LatLng(45, -122);
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          options: const MapOptions(initialCenter: at, initialZoom: 14),
          children: const [RangeRingsLayer(center: at)],
        ),
      ),
    );
    await tester.pump();
    final view = find.byKey(const Key('range-rings'));
    expect(view, findsOneWidget);
    expect(find.byType(CircleLayer), findsOneWidget);
    for (final t in ['N', 'E', 'S', 'W']) {
      expect(find.text(t), findsOneWidget);
    }
    final labels = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^\d+(\.\d+)? k?m$')))
        .map((t) => t.data)
        .toList();
    expect(labels, hasLength(4));
  });
}
