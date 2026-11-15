import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../store/mesh_store.dart';
import 'themes.dart';

/// Longest side a background photo is kept at. It's blurred and dimmed,
/// so more would only cost storage.
const backdropPhotoSide = 960;

/// The background and its photo, as saved.
typedef BackdropState = ({BackdropChoice choice, Uint8List? photo});

/// Watches the saved background.
Stream<BackdropState> watchBackdrop(MeshStore store) async* {
  // Two preferences; combine by re-reading the photo when either changes.
  await for (final saved in store.watchPreference(BackdropChoice.prefName)) {
    final choice = BackdropChoice.decode(saved);
    Uint8List? photo;
    if (choice.kind == BackdropKind.photo) {
      final b64 = await store.preference(BackdropChoice.photoPrefName);
      photo = b64 == null ? null : base64Decode(b64);
    }
    yield (choice: choice, photo: photo);
  }
}

/// Saves [png] as the background photo and switches to it.
Future<void> saveBackdropPhoto(
  MeshStore store,
  BackdropChoice choice,
  Uint8List png,
) async {
  await store.setPreference(BackdropChoice.photoPrefName, base64Encode(png));
  // A changing extra field makes watchers re-read the photo even if the
  // choice was already "photo"; decode ignores it.
  await store.setPreference(
    BackdropChoice.prefName,
    '${choice.copyWith(kind: BackdropKind.photo).encode()};'
    '${DateTime.now().microsecondsSinceEpoch}',
  );
}

/// Asks for a photo and returns it shrunk to [backdropPhotoSide] as PNG,
/// or null if none was picked or it couldn't be read.
Future<Uint8List?> pickBackdropPhoto() async {
  final picked = await FilePicker.pickFiles(type: FileType.image);
  final path = picked.firstOrNull?.path;
  if (path == null) return null;
  try {
    return await shrinkBackdropPhoto(await File(path).readAsBytes());
  } on Exception {
    return null;
  }
}

/// [bytes] (any format Flutter reads) as a PNG no larger than
/// [backdropPhotoSide] on its longest side.
Future<Uint8List> shrinkBackdropPhoto(Uint8List bytes) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final full = (await probe.getNextFrame()).image;
  final (w, h) = (full.width, full.height);
  full.dispose();
  final scale = backdropPhotoSide / (w > h ? w : h);
  final codec = scale >= 1
      ? await ui.instantiateImageCodec(bytes)
      : await ui.instantiateImageCodec(
          bytes,
          targetWidth: (w * scale).round(),
          targetHeight: (h * scale).round(),
        );
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Paints the chosen background, filling its parent.
class BackdropView extends StatelessWidget {
  const BackdropView({super.key, required this.choice, this.photo});

  final BackdropChoice choice;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final a = Color(choice.first);
    final b = Color(choice.second);
    return ExcludeSemantics(
      child: switch (choice.kind) {
        BackdropKind.theme => const SizedBox.expand(),
        BackdropKind.solid => SizedBox.expand(child: ColoredBox(color: a)),
        BackdropKind.linear => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [a, b],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        BackdropKind.mesh => Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: a),
            _blob(const Alignment(.9, -.9), b, 1.1),
            _blob(const Alignment(-1, .8), Color.lerp(a, b, .5)!, 1),
            _blob(
              const Alignment(.6, 1),
              Color.lerp(b, backdropShade, .35)!,
              .9,
            ),
            _blob(const Alignment(-.7, -.6), Color.lerp(a, b, .2)!, .7),
          ],
        ),
        BackdropKind.photo => Stack(
          fit: StackFit.expand,
          children: [
            if (photo case final p?)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: choice.blur,
                  sigmaY: choice.blur,
                  tileMode: TileMode.clamp,
                ),
                child: Image.memory(
                  p,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ColoredBox(color: backdropShade.withValues(alpha: choice.dim)),
          ],
        ),
      },
    );
  }

  static Widget _blob(Alignment at, Color c, double radius) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: at,
        radius: radius,
        colors: [c, c.withValues(alpha: 0)],
      ),
    ),
  );
}

/// A frosted-glass panel: blurs what's behind, a translucent fill that
/// keeps text readable (see [glassFill]) and a hairline border.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.fill,
    required this.child,
    this.radius = 16,
    this.margin = EdgeInsets.zero,
  });

  final Color fill;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outlineVariant;
    final shape = BorderRadius.circular(radius);
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: shape,
              border: Border.all(
                color: border.withValues(alpha: .6),
                width: .5,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}
