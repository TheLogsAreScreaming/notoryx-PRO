// Renders the Traffic map screenshot from demo mode with real fonts.
//
// Skipped unless SCREENSHOTS=1:
//   SCREENSHOTS=1 flutter test test/screenshots/traffic_screenshot_test.dart
// The PNG lands in build/screenshots/readme/traffic-map.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/demo/demo_radio.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/map_tiles.dart';
import 'package:notoryx_pro/ui/themes.dart';

import 'readme_screenshots_test.dart' show loadFonts, ratio, run, size;

void main() {
  setUpAll(() async {
    if (run) await loadFonts();
  });

  testWidgets('traffic map', skip: !run, (t) async {
    debugDisableShadows = false;
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    t.platformDispatcher.localesTestValue = [const Locale('en')];
    t.platformDispatcher.localeTestValue = const Locale('en');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);

    // Tests block the network; the map fetches the few OpenStreetMap tiles
    // it shows (the radios are demo).
    final blocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = blocked);
    final tiles = MapTiles.uncached();

    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: DemoLinks(chatter: const Duration(hours: 1)),
    );
    final (mc, nodes) = (await t.runAsync(() async {
      final mc = await app.connect(demoTarget);
      await Future<void>.delayed(const Duration(seconds: 3));
      return (mc, await store.nodes(mc.radio!.id));
    }))!;

    const out = 'build/screenshots/readme';
    Directory(out).createSync(recursive: true);
    final boundary = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: NotoryxProApp(
          app: app,
          initialTheme: const ThemeChoice(),
          tiles: tiles,
        ),
      ),
    );
    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.tap(find.byIcon(Icons.map_outlined));
    await frames(10);
    await t.tap(find.byKey(const Key('map-fit')));
    await frames(25);
    await t.tap(find.byKey(const Key('map-traffic')));
    await frames(2);

    Node named(String name) => nodes.firstWhere((n) => n.name == name);
    String prefix(String name) => named(name).key.native.substring(0, 2);
    mc.traffic.add(
      HeardPacket(
        time: DateTime.now(),
        radioId: mc.radio!.id,
        kind: TrafficKind.channel,
        label: 'Channel message',
        origin: HopId(named('Trailhead').key.native, HopMatch.key),
        hops: [
          HopId(prefix('Ridge Relay'), HopMatch.prefix),
          const HopId('7f', HopMatch.prefix),
          HopId(prefix('Fire Lookout'), HopMatch.prefix),
        ],
        hopCount: 3,
        snr: 9.5,
        rssi: -87,
      ),
    );
    await frames(13);

    final ro =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = (await t.runAsync(() async {
      final image = await ro.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }))!;
    File('$out/traffic-map.png').writeAsBytesSync(bytes);

    await t.tap(find.byKey(const Key('map-traffic')));
    await frames(2);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 2));
    await t.runAsync(app.shutdown);
    debugDisableShadows = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
