import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/backdrop.dart';
import 'package:notoryx_pro/ui/theme_screen.dart';
import 'package:notoryx_pro/ui/themes.dart';

import 'screens_test.dart' show settle, tearDownApp;
import 'themes_test.dart' show looks;

Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = backdropColors[5],
  );
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  test('glass keeps text readable over black and over bright pictures', () {
    for (final (name, choice, date) in looks()) {
      for (final b in Brightness.values) {
        final t = buildTheme(choice, b, now: date);
        final s = t.colorScheme;
        for (final dim in [0.0, .35, BackdropChoice.maxDim]) {
          final fill = glassFill(t, dim: dim);
          expect(fill.a, lessThanOrEqualTo(1));
          for (final behind in [
            for (var g = 0; g <= 100; g++)
              Color.lerp(
                backdropShade,
                Color.lerp(const Color(0xFFFFFFFF), backdropShade, dim),
                g / 100,
              )!,
            for (final c in backdropColors) Color.lerp(c, backdropShade, dim)!,
          ]) {
            final bg = Color.alphaBlend(fill, behind);
            for (final (what, fg) in [
              ('onSurface', s.onSurface),
              ('onSurfaceVariant', s.onSurfaceVariant),
              ('error', s.error),
              ('meshcore', meshColors(t).meshcore),
              ('meshtastic', meshColors(t).meshtastic),
              ('sos', meshColors(t).sos),
            ]) {
              expect(
                contrastRatio(fg, bg),
                greaterThanOrEqualTo(4.49),
                reason: '$name ${b.name} dim $dim $what',
              );
            }
          }
        }
      }
    }
  });

  test('glass is see-through where it can be', () {
    final t = buildTheme(const ThemeChoice(), Brightness.dark);
    expect(glassFill(t, dim: BackdropChoice.maxDim).a, lessThan(.95));
  });

  test('a saved background round-trips; junk falls back', () {
    const c = BackdropChoice(
      kind: BackdropKind.mesh,
      first: 0xFF112233,
      second: 0xFF445566,
      dim: .5,
      blur: 12,
    );
    expect(BackdropChoice.decode(c.encode()), c);
    expect(BackdropChoice.decode('${c.encode()};12345'), c);
    expect(BackdropChoice.decode(null), const BackdropChoice());
    expect(BackdropChoice.decode('nope').kind, BackdropKind.theme);
    final wild = BackdropChoice.decode('photo;1;2;9;99');
    expect((wild.dim, wild.blur), (BackdropChoice.maxDim, 20.0));
    expect(const BackdropChoice().glass, isFalse);
    expect(c.glass, isTrue);
  });

  test('big photos are shrunk', () async {
    final png = await _png(2000, 1000);
    final small = await shrinkBackdropPhoto(png);
    final codec = await ui.instantiateImageCodec(small);
    final img = (await codec.getNextFrame()).image;
    expect((img.width, img.height), (backdropPhotoSide, 480));
  });

  testWidgets('picking a background saves it; a photo brings sliders', (
    tester,
  ) async {
    final store = MeshStore.memory();
    late Uint8List png;
    await tester.runAsync(() async => png = await _png(40, 30));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [BackdropOptions(store: store, pick: () async => png)],
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Messages stay readable on glass.'), findsNothing);

    await tester.tap(find.byKey(const Key('bg-mesh')));
    await settle(tester);
    late String? saved;
    await tester.runAsync(
      () async => saved = await store.preference(BackdropChoice.prefName),
    );
    expect(BackdropChoice.decode(saved).kind, BackdropKind.mesh);
    expect(find.text('First colour'), findsOneWidget);
    expect(find.text('Second colour'), findsOneWidget);
    expect(find.text('Messages stay readable on glass.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Gold').first);
    await settle(tester);
    await tester.runAsync(
      () async => saved = await store.preference(BackdropChoice.prefName),
    );
    expect(BackdropChoice.decode(saved).first, backdropColors[5].toARGB32());

    await tester.ensureVisible(find.byKey(const Key('bg-photo')));
    await tester.tap(find.byKey(const Key('bg-photo')));
    await settle(tester);
    await settle(tester);
    await tester.runAsync(
      () async => saved = await store.preference(BackdropChoice.prefName),
    );
    expect(BackdropChoice.decode(saved).kind, BackdropKind.photo);
    expect(find.text('Dim'), findsOneWidget);
    expect(find.text('Blur'), findsOneWidget);
    expect(find.byKey(const Key('bg-pick')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });

  testWidgets('main screens sit on glass over the background', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(
      () => const BackdropChoice(kind: BackdropKind.linear).save(app.store),
    );
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    expect(find.byType(BackdropView), findsOneWidget);
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(
      find.textContaining('Connect a radio on the Radios tab'),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Back to the theme default: no background, no glass.
    await tester.runAsync(() => const BackdropChoice().save(app.store));
    await settle(tester);
    expect(find.byType(GlassPanel), findsNothing);
    await tearDownApp(tester, app);
  });
}
