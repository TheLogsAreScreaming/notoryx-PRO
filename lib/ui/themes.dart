import 'dart:math';

import 'package:flutter/material.dart';

import '../radio/radio.dart';
import '../mesh/traffic.dart';
import '../store/mesh_store.dart';

/// The looks the app can wear, in picker order.
enum AppThemeId {
  blackout,
  blaze,
  neonAnarchy,
  tactical,
  bareBeauty,
  okabeIto,
  nightOps,
}

/// What the person picked on the theme screen.
@immutable
class ThemeChoice {
  const ThemeChoice({this.id = AppThemeId.blackout});

  /// Preference the choice is saved under.
  static const prefName = 'theme';

  /// The chosen look.
  final AppThemeId id;

  /// Saved form: the look's name.
  String encode() => id.name;

  /// Reads [encode]'s output. Older saves added `;season;holidays` after the
  /// name; that part is ignored. A look that no longer exists (Seasonal, Pink
  /// Overload) or anything unknown falls back to BLACKOUT.
  static ThemeChoice decode(String? saved) => ThemeChoice(
    id:
        AppThemeId.values.asNameMap()[(saved ?? '').split(';').first] ??
        AppThemeId.blackout,
  );

  /// Saves this choice.
  Future<void> save(MeshStore store) => store.setPreference(prefName, encode());

  /// The saved choice.
  static Future<ThemeChoice> load(MeshStore store) async =>
      decode(await store.preference(prefName));

  /// A copy with another look.
  ThemeChoice copyWith({AppThemeId? id}) => ThemeChoice(id: id ?? this.id);
}

/// Colours specific to this app, carried with the theme.
@immutable
class MeshColors extends ThemeExtension<MeshColors> {
  const MeshColors({
    required this.meshcore,
    required this.meshtastic,
    required this.sos,
    required this.sosContainer,
    required this.onSosContainer,
  });

  /// MeshCore badges and map pins.
  final Color meshcore;

  /// Meshtastic badges and map pins.
  final Color meshtastic;

  /// Emergency messages and SOS controls. Neon green in every theme,
  /// darkened on light backgrounds so it stays readable.
  final Color sos;

  /// Background of the running-beacon banner: full neon green.
  final Color sosContainer;

  /// Text on [sosContainer].
  final Color onSosContainer;

  @override
  MeshColors copyWith({
    Color? meshcore,
    Color? meshtastic,
    Color? sos,
    Color? sosContainer,
    Color? onSosContainer,
  }) => MeshColors(
    meshcore: meshcore ?? this.meshcore,
    meshtastic: meshtastic ?? this.meshtastic,
    sos: sos ?? this.sos,
    sosContainer: sosContainer ?? this.sosContainer,
    onSosContainer: onSosContainer ?? this.onSosContainer,
  );

  @override
  MeshColors lerp(MeshColors? other, double t) => other == null
      ? this
      : MeshColors(
          meshcore: Color.lerp(meshcore, other.meshcore, t)!,
          meshtastic: Color.lerp(meshtastic, other.meshtastic, t)!,
          sos: Color.lerp(sos, other.sos, t)!,
          sosContainer: Color.lerp(sosContainer, other.sosContainer, t)!,
          onSosContainer: Color.lerp(onSosContainer, other.onSosContainer, t)!,
        );
}

/// WCAG contrast ratio between two colours.
double contrastRatio(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (max(x, y) + .05) / (min(x, y) + .05);
}

/// [color] moved towards black or white until it reaches 4.5:1 on every
/// colour in [backgrounds].
Color readableOn(Color color, List<Color> backgrounds) {
  final dark = backgrounds.first.computeLuminance() > .18;
  final target = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  var c = color;
  for (var t = 0.0; t <= 1; t += .02) {
    c = Color.lerp(color, target, t)!;
    if (backgrounds.every((b) => contrastRatio(c, b) >= 4.5)) return c;
  }
  return c;
}

/// MeshCore's colour: fire engine red. Lightened where needed to stay
/// readable on dark backgrounds.
const fireEngineRed = Color(0xFFCE2029);

/// Meshtastic's colour: Ford blue. Lightened where needed to stay readable
/// on dark backgrounds.
const fordBlue = Color(0xFF003478);

/// Emergency colour: neon green.
const neonGreen = Color(0xFF39FF14);

class _Palette {
  const _Palette(
    this.seed, {
    this.variant = DynamicSchemeVariant.tonalSpot,
    this.darkOnly = false,
  });

  final Color seed;
  final DynamicSchemeVariant variant;
  final bool darkOnly;
}

const _blaze = _Palette(
  Color(0xFFFF5A1F),
  variant: DynamicSchemeVariant.vibrant,
);
const _neon = _Palette(
  Color(0xFFFF00C8),
  variant: DynamicSchemeVariant.vibrant,
  darkOnly: true,
);
const _tactical = _Palette(Color(0xFF6B7A3A));
const _bare = _Palette(
  Color(0xFF808080),
  variant: DynamicSchemeVariant.monochrome,
);

/// The colour-blind-safe set by Okabe and Ito.
const _okabe = _Palette(
  Color(0xFF0072B2),
  variant: DynamicSchemeVariant.fidelity,
);
const _night = _Palette(Color(0xFFB00020), darkOnly: true);

/// BLACKOUT is monochrome; its colours come from [_blackout].
const _blackoutSeed = _Palette(
  Color(0xFF888888),
  variant: DynamicSchemeVariant.monochrome,
  darkOnly: true,
);

_Palette _paletteFor(ThemeChoice c) => switch (c.id) {
  AppThemeId.blackout => _blackoutSeed,
  AppThemeId.blaze => _blaze,
  AppThemeId.neonAnarchy => _neon,
  AppThemeId.tactical => _tactical,
  AppThemeId.bareBeauty => _bare,
  AppThemeId.okabeIto => _okabe,
  AppThemeId.nightOps => _night,
};

/// BLACKOUT brand palette (matte, charcoal, gunmetal, steel, frost).
const blackoutMatte = Color(0xFF080808);
const blackoutCharcoal = Color(0xFF242424);
const blackoutGunmetal = Color(0xFF484848);
const blackoutSteel = Color(0xFF888888);
const blackoutFrost = Color(0xFFE8E8E8);

/// BLACKOUT: frost on matte black, no brand accent. Secondary text is a
/// lighter steel (#9E9E9E) so it stays 4.5:1 on charcoal cards; plain
/// steel #888888 is kept for outlines.
ColorScheme _blackout(ColorScheme s) => s.copyWith(
  surface: blackoutMatte,
  surfaceDim: blackoutMatte,
  surfaceBright: const Color(0xFF2C2C2C),
  surfaceContainerLowest: const Color(0xFF040404),
  surfaceContainerLow: const Color(0xFF101010),
  surfaceContainer: const Color(0xFF181818),
  surfaceContainerHigh: const Color(0xFF1E1E1E),
  surfaceContainerHighest: blackoutCharcoal,
  onSurface: blackoutFrost,
  onSurfaceVariant: const Color(0xFF9E9E9E),
  primary: blackoutFrost,
  onPrimary: blackoutMatte,
  primaryContainer: blackoutGunmetal,
  onPrimaryContainer: blackoutFrost,
  secondary: const Color(0xFFBDBDBD),
  onSecondary: blackoutMatte,
  secondaryContainer: const Color(0xFF363636),
  onSecondaryContainer: blackoutFrost,
  tertiary: const Color(0xFFBDBDBD),
  onTertiary: blackoutMatte,
  tertiaryContainer: const Color(0xFF363636),
  onTertiaryContainer: blackoutFrost,
  outline: blackoutSteel,
  outlineVariant: blackoutGunmetal,
  inverseSurface: blackoutFrost,
  onInverseSurface: blackoutMatte,
  inversePrimary: blackoutGunmetal,
  surfaceTint: blackoutFrost,
  shadow: const Color(0xFF000000),
  scrim: const Color(0xFF000000),
);

/// Night Ops keeps everything red on black, to protect night vision.
ColorScheme _nightOps(ColorScheme s) => s.copyWith(
  surface: const Color(0xFF080000),
  surfaceContainerLowest: const Color(0xFF040000),
  surfaceContainerLow: const Color(0xFF120202),
  surfaceContainer: const Color(0xFF180404),
  surfaceContainerHigh: const Color(0xFF200606),
  surfaceContainerHighest: const Color(0xFF2A0808),
  onSurface: const Color(0xFFFF9E9E),
  onSurfaceVariant: const Color(0xFFE88080),
  primary: const Color(0xFFFF5252),
  onPrimary: const Color(0xFF000000),
  primaryContainer: const Color(0xFF5C0F0F),
  onPrimaryContainer: const Color(0xFFFFB4B4),
  secondaryContainer: const Color(0xFF4A0E0E),
  onSecondaryContainer: const Color(0xFFFFB4B4),
  outline: const Color(0xFFA85050),
  outlineVariant: const Color(0xFF5C2020),
);

/// The Material theme for [choice] at [brightness].
ThemeData buildTheme(ThemeChoice choice, Brightness brightness) {
  final p = _paletteFor(choice);
  final b = p.darkOnly ? Brightness.dark : brightness;
  var scheme = ColorScheme.fromSeed(
    seedColor: p.seed,
    brightness: b,
    dynamicSchemeVariant: p.variant,
  );
  if (choice.id == AppThemeId.nightOps) scheme = _nightOps(scheme);
  if (choice.id == AppThemeId.blackout) scheme = _blackout(scheme);
  final backgrounds = [
    scheme.surface,
    scheme.surfaceContainerLow,
    scheme.surfaceContainerHighest,
  ];
  final sos = b == Brightness.light
      ? const Color(0xFFB3261E)
      : const Color(0xFFFF6B5E);
  // Warnings keep their red whatever the theme's own palette makes of it.
  scheme = scheme.copyWith(
    error: readableOn(sos, backgrounds),
    onError: b == Brightness.light
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000),
  );
  return ThemeData(
    colorScheme: scheme,
    extensions: [
      MeshColors(
        meshcore: readableOn(fireEngineRed, backgrounds),
        meshtastic: readableOn(fordBlue, backgrounds),
        sos: readableOn(neonGreen, backgrounds),
        sosContainer: neonGreen,
        onSosContainer: const Color(0xFF000000),
      ),
    ],
  );
}

/// The app's own colours in [theme].
MeshColors meshColors(ThemeData theme) =>
    // A plain MaterialApp has no extension. Fall back to a look that follows
    // its brightness (BLACKOUT is always dark, so its colours would be tuned
    // for the wrong background on a light screen).
    theme.extension<MeshColors>() ??
    buildTheme(
      const ThemeChoice(id: AppThemeId.bareBeauty),
      theme.brightness,
    ).extension<MeshColors>()!;

/// Colour that marks [p]'s mesh in [theme].
Color meshColor(RadioProtocol p, ThemeData theme) {
  final m = meshColors(theme);
  return switch (p) {
    RadioProtocol.meshcore => m.meshcore,
    RadioProtocol.meshtastic => m.meshtastic,
  };
}

/// What sits behind the main screens.
enum BackdropKind {
  /// The theme's own plain surface (no glass).
  theme,

  /// One colour.
  solid,

  /// Two colours, corner to corner.
  linear,

  /// Two colours blended in soft overlapping blobs.
  mesh,

  /// The person's own photo, dimmed and blurred.
  photo,
}

/// Colours offered for backgrounds.
const backdropColors = <Color>[
  Color(0xFF0B1D3A),
  Color(0xFF1E5AA8),
  Color(0xFF0E7C7B),
  Color(0xFF2E7D32),
  Color(0xFF7CB342),
  Color(0xFFF9A825),
  Color(0xFFEF6C00),
  Color(0xFFC62828),
  Color(0xFFAD1457),
  Color(0xFF6A1B9A),
  Color(0xFF37474F),
  Color(0xFF111111),
];

/// Laid over a photo to dim it.
const backdropShade = Color(0xFF000000);

const _brightest = Color(0xFFFFFFFF);

const _strongHues = [
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFFF00),
  Color(0xFF00FFFF),
  Color(0xFFFF00FF),
];

/// The background the person picked, saved as a preference.
@immutable
class BackdropChoice {
  const BackdropChoice({
    this.kind = BackdropKind.theme,
    this.first = 0xFF1E5AA8,
    this.second = 0xFFAD1457,
    this.dim = .35,
    this.blur = 8,
  });

  /// Preference the choice is saved under.
  static const prefName = 'backdrop';

  /// Preference holding the photo, base64 PNG.
  static const photoPrefName = 'backdropPhoto';

  /// Most a photo may be dimmed (0 to 1).
  static const maxDim = .8;

  /// Strongest photo blur, in logical pixels.
  static const maxBlur = 20.0;

  final BackdropKind kind;

  /// First colour, ARGB.
  final int first;

  /// Second colour (gradients), ARGB.
  final int second;

  /// How much a photo is darkened, 0 to [maxDim].
  final double dim;

  /// How much a photo is blurred, 0 to [maxBlur].
  final double blur;

  /// Whether the main screens use glass over a background.
  bool get glass => kind != BackdropKind.theme;

  /// Saved form: `kind;first;second;dim;blur`.
  String encode() =>
      '${kind.name};$first;$second;${dim.toStringAsFixed(2)};'
      '${blur.toStringAsFixed(1)}';

  /// Reads [encode]'s output; anything unknown falls back to defaults.
  static BackdropChoice decode(String? saved) {
    const d = BackdropChoice();
    final p = (saved ?? '').split(';');
    String? at(int i) => p.length > i ? p[i] : null;
    return BackdropChoice(
      kind: BackdropKind.values.asNameMap()[p.first] ?? d.kind,
      first: int.tryParse(at(1) ?? '') ?? d.first,
      second: int.tryParse(at(2) ?? '') ?? d.second,
      dim: (double.tryParse(at(3) ?? '') ?? d.dim).clamp(0, maxDim),
      blur: (double.tryParse(at(4) ?? '') ?? d.blur).clamp(0, maxBlur),
    );
  }

  /// Saves this choice.
  Future<void> save(MeshStore store) => store.setPreference(prefName, encode());

  /// A copy with some settings changed.
  BackdropChoice copyWith({
    BackdropKind? kind,
    int? first,
    int? second,
    double? dim,
    double? blur,
  }) => BackdropChoice(
    kind: kind ?? this.kind,
    first: first ?? this.first,
    second: second ?? this.second,
    dim: dim ?? this.dim,
    blur: blur ?? this.blur,
  );

  @override
  bool operator ==(Object other) =>
      other is BackdropChoice &&
      other.kind == kind &&
      other.first == first &&
      other.second == second &&
      other.dim == dim &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(kind, first, second, dim, blur);
}

/// The frosted-glass fill for [theme] over any background darkened by
/// [dim]: the theme's surface, made just opaque enough that text and the
/// mesh colours stay at 4.5:1 (or as readable as on the plain surface)
/// whether the background behind is black or as bright as it can be.
Color glassFill(ThemeData theme, {double dim = 0}) {
  final s = theme.colorScheme;
  final m = meshColors(theme);
  // Text is hardest to read when the background's brightness nears its
  // own, so try greys all the way up plus strong hues, all as dimmed.
  final behind = [
    for (var g = 0; g <= 20; g++)
      Color.lerp(backdropShade, _brightest, g / 20)!,
    ..._strongHues,
    ...backdropColors,
  ].map((c) => Color.lerp(c, backdropShade, dim)!).toList();
  final texts = [
    s.onSurface,
    s.onSurfaceVariant,
    s.primary,
    s.error,
    m.meshcore,
    m.meshtastic,
    m.sos,
  ];
  // The best each colour can do is on the plain surface.
  final goal = [for (final t in texts) min(4.5, contrastRatio(t, s.surface))];
  for (var a = .55; a < 1; a += .01) {
    final fill = s.surface.withValues(alpha: a);
    final ok = behind.every((b) {
      final bg = Color.alphaBlend(fill, b);
      for (var i = 0; i < texts.length; i++) {
        if (contrastRatio(texts[i], bg) < goal[i] - .001) return false;
      }
      return true;
    });
    if (ok) return fill;
  }
  return s.surface;
}

/// [theme] for screens laid over a background: see-through scaffold, and
/// app bar and navigation bar filled with [fill].
ThemeData glassTheme(ThemeData theme, Color fill) => theme.copyWith(
  scaffoldBackgroundColor: const Color(0x00000000),
  appBarTheme: theme.appBarTheme.copyWith(
    backgroundColor: fill,
    surfaceTintColor: const Color(0x00000000),
  ),
  navigationBarTheme: theme.navigationBarTheme.copyWith(backgroundColor: fill),
);

/// Black or white, whichever reads better on a colour the person chose
/// (a node's colour, say), since that colour isn't from the theme.
Color onChosenColor(Color fill) => fill.computeLuminance() > 0.4
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

/// The colour each kind of packet is drawn in on the Traffic map. Fixed
/// across themes so the legend always means the same thing.
Color trafficColor(TrafficKind k) => switch (k) {
  TrafficKind.advert => const Color(0xFFFF4FA3),
  TrafficKind.direct => const Color(0xFF4D8DFF),
  TrafficKind.channel => const Color(0xFF3DDC84),
  TrafficKind.ack => const Color(0xFF22D3EE),
  TrafficKind.trace => const Color(0xFFFF9F1C),
  TrafficKind.path => const Color(0xFFB07CFF),
};

/// The bright core of a travelling packet.
const trafficDotCore = Color(0xFFFFFFFF);

/// Hop label text and its backing chip on the Traffic map; light on dark
/// so they read over any map tile.
const trafficLabelInk = Color(0xFFFFFFFF);
const trafficLabelBack = Color(0xFF000000);

/// The ring on pins of nodes heard in the last hour.
const recentRing = Color(0xFF3DDC84);
