import 'dart:math';

import 'package:flutter/material.dart';

import '../radio/radio.dart';
import '../store/mesh_store.dart';

/// The eight looks the app can wear, in picker order.
enum AppThemeId {
  blaze,
  neonAnarchy,
  tactical,
  pinkOverload,
  bareBeauty,
  okabeIto,
  nightOps,
  seasonal,
}

/// The four seasons the Seasonal theme moves through.
enum Season { spring, summer, autumn, winter }

/// The season at [date], northern-hemisphere months.
Season seasonOf(DateTime date) => switch (date.month) {
  3 || 4 || 5 => Season.spring,
  6 || 7 || 8 => Season.summer,
  9 || 10 || 11 => Season.autumn,
  _ => Season.winter,
};

/// The optional holiday palettes, each covering a few days.
enum Holiday { independence, halloween, winterHolidays, newYear }

/// The holiday at [date], or null.
Holiday? holidayOf(DateTime date) => switch ((date.month, date.day)) {
  (7, >= 1 && <= 4) => Holiday.independence,
  (10, >= 25) => Holiday.halloween,
  (12, >= 20 && <= 26) => Holiday.winterHolidays,
  (12, 31) || (1, 1) => Holiday.newYear,
  _ => null,
};

/// What the person picked on the theme screen.
@immutable
class ThemeChoice {
  const ThemeChoice({
    this.id = AppThemeId.blaze,
    this.season,
    this.holidays = false,
  });

  /// Preference the choice is saved under.
  static const prefName = 'theme';

  /// The chosen look.
  final AppThemeId id;

  /// For Seasonal: a fixed season, or null to follow the date.
  final Season? season;

  /// For Seasonal: whether holiday palettes may replace the season.
  final bool holidays;

  /// Saved form: `id;season;holidays`.
  String encode() =>
      '${id.name};${season?.name ?? ''};${holidays ? 'on' : 'off'}';

  /// Reads [encode]'s output; anything unknown falls back to the default.
  static ThemeChoice decode(String? saved) {
    final p = (saved ?? '').split(';');
    return ThemeChoice(
      id: AppThemeId.values.asNameMap()[p.first] ?? AppThemeId.blaze,
      season: p.length > 1 ? Season.values.asNameMap()[p[1]] : null,
      holidays: p.length > 2 && p[2] == 'on',
    );
  }

  /// Saves this choice.
  Future<void> save(MeshStore store) => store.setPreference(prefName, encode());

  /// The saved choice.
  static Future<ThemeChoice> load(MeshStore store) async =>
      decode(await store.preference(prefName));

  /// A copy with some settings changed.
  ThemeChoice copyWith({
    AppThemeId? id,
    Season? Function()? season,
    bool? holidays,
  }) => ThemeChoice(
    id: id ?? this.id,
    season: season == null ? this.season : season(),
    holidays: holidays ?? this.holidays,
  );
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
const _pink = _Palette(
  Color(0xFFFF2E93),
  variant: DynamicSchemeVariant.vibrant,
);
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

const _seasons = {
  Season.spring: _Palette(Color(0xFF4CAF50)),
  Season.summer: _Palette(
    Color(0xFFFFB300),
    variant: DynamicSchemeVariant.vibrant,
  ),
  Season.autumn: _Palette(Color(0xFFB5541C)),
  Season.winter: _Palette(Color(0xFF5B9BD5)),
};

const _holidays = {
  Holiday.independence: _Palette(
    Color(0xFF1F3A93),
    variant: DynamicSchemeVariant.vibrant,
  ),
  Holiday.halloween: _Palette(
    Color(0xFFFF7518),
    variant: DynamicSchemeVariant.vibrant,
  ),
  Holiday.winterHolidays: _Palette(Color(0xFF1B7F3B)),
  Holiday.newYear: _Palette(
    Color(0xFFD4AF37),
    variant: DynamicSchemeVariant.fidelity,
  ),
};

_Palette _paletteFor(ThemeChoice c, DateTime now) => switch (c.id) {
  AppThemeId.blaze => _blaze,
  AppThemeId.neonAnarchy => _neon,
  AppThemeId.tactical => _tactical,
  AppThemeId.pinkOverload => _pink,
  AppThemeId.bareBeauty => _bare,
  AppThemeId.okabeIto => _okabe,
  AppThemeId.nightOps => _night,
  AppThemeId.seasonal =>
    (c.holidays && c.season == null ? _holidays[holidayOf(now)] : null) ??
        _seasons[c.season ?? seasonOf(now)]!,
};

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

/// The Material theme for [choice] at [brightness] on the date [now].
ThemeData buildTheme(
  ThemeChoice choice,
  Brightness brightness, {
  DateTime? now,
}) {
  final p = _paletteFor(choice, now ?? DateTime.now());
  final b = p.darkOnly ? Brightness.dark : brightness;
  var scheme = ColorScheme.fromSeed(
    seedColor: p.seed,
    brightness: b,
    dynamicSchemeVariant: p.variant,
  );
  if (choice.id == AppThemeId.nightOps) scheme = _nightOps(scheme);
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
    // A plain MaterialApp has no extension; fall back to the default look.
    theme.extension<MeshColors>() ??
    buildTheme(const ThemeChoice(), theme.brightness).extension<MeshColors>()!;

/// Colour that marks [p]'s mesh in [theme].
Color meshColor(RadioProtocol p, ThemeData theme) {
  final m = meshColors(theme);
  return switch (p) {
    RadioProtocol.meshcore => m.meshcore,
    RadioProtocol.meshtastic => m.meshtastic,
  };
}
