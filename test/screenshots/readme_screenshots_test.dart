// Renders the README screenshots from demo mode with real fonts: the
// store set's main screens plus the newer features (node colours, glass
// background, compass, line of sight with terrain).
//
// Skipped unless SCREENSHOTS=1:
//   SCREENSHOTS=1 flutter test test/screenshots
// PNGs land in build/screenshots/readme/. Copy them to docs/screenshots/.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/elevation.dart';
import 'package:notoryx_pro/app/heading.dart';
import 'package:notoryx_pro/demo/demo_radio.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/node_look.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/compass_screen.dart';
import 'package:notoryx_pro/ui/line_of_sight_sheet.dart';
import 'package:notoryx_pro/ui/map_tiles.dart';
import 'package:notoryx_pro/ui/sarneg/sarneg.dart';
import 'package:notoryx_pro/ui/sarneg/sarneg_ui.dart';
import 'package:notoryx_pro/ui/themes.dart';

final run = Platform.environment['SCREENSHOTS'] == '1';

const size = Size(360, 640);
const ratio = 3.0;

/// A phone just south of the node, facing a little left of it.
class _Sensors implements CompassSensors {
  const _Sensors(this.here);

  final GeoPoint here;

  @override
  Stream<HeadingReading>? headings() =>
      Stream.value((degrees: 340.0, accuracy: 3));

  @override
  Future<double?> declination(GeoPoint at) async => 0;

  @override
  Future<GeoPoint?> phonePositionIfAllowed() async => here;

  @override
  Future<GeoPoint?> phonePosition() async => here;
}

/// A made-up valley between two hills, with a ridge two thirds of the way
/// along that just clips the Fresnel zone.
class _Terrain implements ElevationLookup {
  @override
  Future<List<double>> heights(List<GeoPoint> points) async {
    final n = points.length;
    return [
      for (var i = 0; i < n; i++)
        1300 -
            380 * math.sin(math.pi * i / (n - 1)) +
            315 * math.exp(-math.pow((i / (n - 1) - .66) / .08, 2)),
    ];
  }
}

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // Roboto has no arrows (→) and there is no monospace font in tests; on a
  // Mac, system fonts fill those in (SARNEG code letters are monospace).
  Future<bool> system(String family, String path) async {
    if (!File(path).existsSync()) return false;
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    return true;
  }

  // Tests don't fall back to other fonts on their own, so every theme names
  // this one as its fallback.
  if (await system(
    'ArialUnicode',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  )) {
    debugFontFamilyFallback = const ['ArialUnicode'];
  }
  await system(
    'monospace',
    '/System/Library/Fonts/Supplemental/Andale Mono.ttf',
  );
}

void main() {
  setUpAll(() async {
    if (run) await loadFonts();
  });

  testWidgets('readme', skip: !run, (t) async {
    debugDisableShadows = false;
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    t.platformDispatcher.localesTestValue = [const Locale('en')];
    t.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);

    // Tests block the network; the map shot fetches the few OpenStreetMap
    // tiles it shows (nothing else here goes online: the radios are demo).
    final blocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = blocked);
    final tiles = MapTiles.uncached();

    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: DemoLinks(chatter: const Duration(seconds: 2)),
    );
    final (mc, mt, nodes) = (await t.runAsync(() async {
      final mc = await app.connect(demoTarget);
      final mt = await app.connect(demoMeshtasticTarget);
      final nodes = await store.nodes(mt.radio!.id);
      final hut = nodes.firstWhere((n) => n.name == 'Summit Hut');
      await mt.sendText(
        DirectConversation(mt.radio!.id, hut.key),
        'Made it to the ridge, heading down at 4',
      );
      await Future<void>.delayed(const Duration(seconds: 9));
      return (mc, mt, nodes);
    }))!;

    const out = 'build/screenshots/readme';
    Directory(out).createSync(recursive: true);
    final boundary = GlobalKey();

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    }

    Future<void> shot(String name) async {
      await settle();
      final ro =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = (await t.runAsync(() async {
        final image = await ro.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }))!;
      File('$out/$name.png').writeAsBytesSync(bytes);
    }

    // Colours for a few nodes, and a mesh-gradient glass background.
    await t.runAsync(() async {
      const colours = [0xFF2E7D32, 0xFFF9A825, 0xFF6A1B9A, 0xFF00838F];
      for (final (i, n) in nodes.take(colours.length).indexed) {
        await store.setNodeLook(n.key.toString(), NodeLook(color: colours[i]));
      }
      await const ThemeChoice().save(store);
    });

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
    final nav = (t.widget(find.byType(NotoryxProApp)) as NotoryxProApp)
        .navigatorKey
        .currentState!;

    await t.tap(find.byIcon(Icons.hub_outlined));
    await shot('node-colours');

    await t.runAsync(
      () => store.setPreference(
        BackdropChoice.prefName,
        const BackdropChoice(
          kind: BackdropKind.mesh,
          first: 0xFF0D47A1,
          second: 0xFF00897B,
        ).encode(),
      ),
    );
    await t.tap(find.byIcon(Icons.chat_bubble_outline).first);
    await shot('glass-background');
    await t.runAsync(
      () => store.setPreference(
        BackdropChoice.prefName,
        const BackdropChoice().encode(),
      ),
    );
    await settle();

    final hut = nodes.firstWhere((n) => n.name == 'Summit Hut');
    final here = GeoPoint(
      hut.position!.latitude - .03,
      hut.position!.longitude + .004,
    );
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CompassScreen(app: app, node: hut, sensors: _Sensors(here)),
        ),
      ),
    );
    await shot('compass');
    nav.pop();
    await settle();

    final ends = [
      for (final n in nodes)
        if (n.position case final p?) (n.name, p),
    ];
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(),
            body: LineOfSightSheet(
              ends: ends,
              initialFrom: ends.indexWhere((e) => e.$1 == 'Lake Camp'),
              initialTo: ends.indexWhere((e) => e.$1 == 'Ridge Repeater'),
              frequencyMHz: 906.875,
              elevation: _Terrain(),
            ),
          ),
        ),
      ),
    );
    await settle();
    await t.ensureVisible(find.byKey(const Key('los-check-terrain')));
    await settle();
    await t.tap(find.byKey(const Key('los-check-terrain')));
    await settle();
    await t.ensureVisible(find.textContaining('Ground heights:'));
    await shot('line-of-sight');
    nav.pop();
    await settle();

    // The map with both meshes, on real OpenStreetMap tiles.
    await t.tap(find.byIcon(Icons.map_outlined));
    await settle();
    await t.tap(find.byKey(const Key('map-fit')));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    await shot('map');
    await t.tap(find.byIcon(Icons.chat_bubble_outline).first);
    await settle();

    // SARNEG with the example word from the docs, never a real team's word.
    SarnegKeys.instance = SarnegKeys(storage: MemorySarnegStorage());
    await t.runAsync(
      () => SarnegKeys.instance.save(SarnegKeySet(word: 'BLACKHORSE')),
    );
    unawaited(
      nav.push(MaterialPageRoute<void>(builder: (_) => const SarnegScreen())),
    );
    await shot('sarneg');
    nav.pop();
    await settle();
    unawaited(showSarnegComposeSheet(nav.context, initial: '17S 4823'));
    await shot('sarneg-compose');
    nav.pop();
    await settle();

    // The Inbox menu: settings and tools.
    await t.tap(find.byKey(const Key('inbox-menu')));
    await shot('menu');
    await t.tapAt(const Offset(20, 600));
    await settle();

    expect([mc.radio, mt.radio], everyElement(isNotNull));

    await t.pumpWidget(const SizedBox());
    // Lets the tile client's retry and reload timers run out.
    await t.pump(const Duration(minutes: 2));
    await t.runAsync(app.shutdown);
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
    debugDisableShadows = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
