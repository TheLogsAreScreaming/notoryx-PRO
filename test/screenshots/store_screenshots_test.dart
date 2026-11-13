// Renders store screenshots from demo mode with real fonts.
//
// Skipped unless SCREENSHOTS=1, so normal test runs stay fast:
//   SCREENSHOTS=1 flutter test test/screenshots
// PNGs land in build/screenshots/<size>/<language>/.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/demo/demo_radio.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/diagnostics_screen.dart';
import 'package:notoryx_pro/ui/mecp_widgets.dart';
import 'package:notoryx_pro/ui/theme_screen.dart';
import 'package:notoryx_pro/ui/themes.dart';

final run = Platform.environment['SCREENSHOTS'] == '1';

/// Store sizes: name, logical size and pixel ratio.
const sizes = [
  ('play-phone', Size(360, 640), 3.0), // 1080x1920
  ('iphone-6.9', Size(440, 956), 3.0), // 1320x2868
];

const languages = ['en', 'es', 'fr', 'de'];

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
}

void main() {
  setUpAll(() async {
    if (run) await loadFonts();
  });

  for (final (sizeName, size, ratio) in sizes) {
    for (final lang in languages) {
      testWidgets('$sizeName $lang', skip: !run, (t) async {
        debugDisableShadows = false;
        t.view.physicalSize = size * ratio;
        t.view.devicePixelRatio = ratio;
        t.platformDispatcher.localesTestValue = [Locale(lang)];
        t.platformDispatcher.localeTestValue = Locale(lang);
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearAllTestValues);

        final store = MeshStore.memory();
        final app = AppController(
          store: store,
          links: DemoLinks(chatter: const Duration(seconds: 2)),
        );
        final radios = (await t.runAsync(() async {
          final mc = await app.connect(demoTarget);
          final mt = await app.connect(demoMeshtasticTarget);
          final nodes = await store.nodes(mt.radio!.id);
          final hut = nodes.firstWhere((n) => n.name == 'Summit Hut');
          await mt.sendText(
            DirectConversation(mt.radio!.id, hut.key),
            'Made it to the ridge, heading down at 4',
          );
          await Future<void>.delayed(const Duration(seconds: 9));
          return (mc, mt);
        }))!;

        final out = 'build/screenshots/$sizeName/$lang';
        Directory(out).createSync(recursive: true);
        final boundary = GlobalKey();
        var theme = const ThemeChoice();

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
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final bytes = (await t.runAsync(() async {
            final image = await ro.toImage(pixelRatio: ratio);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            return data!.buffer.asUint8List();
          }))!;
          File('$out/$name.png').writeAsBytesSync(bytes);
        }

        Future<void> show() async {
          await t.runAsync(() => theme.save(store));
          final widget = NotoryxProApp(app: app, initialTheme: theme);
          await t.pumpWidget(RepaintBoundary(key: boundary, child: widget));
        }

        await show();
        await shot('1-inbox');

        final nav = (t.widget(find.byType(NotoryxProApp)) as NotoryxProApp)
            .navigatorKey
            .currentState!;
        await t.tap(find.textContaining('Summit Hut').first);
        await shot('2-conversation');
        nav.pop();
        await settle();

        await t.tap(find.byIcon(Icons.hub_outlined));
        await shot('3-nodes');

        await t.tap(find.byIcon(Icons.settings_input_antenna));
        await shot('4-radios');

        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => DiagnosticsScreen(connection: radios.$1),
            ),
          ),
        );
        await shot('5-diagnostics');
        nav.pop();
        await settle();

        unawaited(showMecpComposer(nav.context, maxBytes: 200));
        await shot('6-emergency');
        nav.pop();
        await settle();

        unawaited(
          nav.push(
            MaterialPageRoute<void>(builder: (_) => ThemeScreen(store: store)),
          ),
        );
        await shot('7-themes');
        nav.pop();
        await settle();

        theme = const ThemeChoice(id: AppThemeId.nightOps);
        await show();
        await shot('8-night-ops');

        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        await t.runAsync(app.shutdown);
        final closing = store.close();
        await t.pump(const Duration(seconds: 1));
        await t.runAsync(() => closing);
        debugDisableShadows = true;
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  }
}
