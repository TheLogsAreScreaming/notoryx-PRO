import 'dart:math' as math;

import 'diagnostics.dart' show haversineKm;
import 'model.dart';

/// Speed of light, m/s.
const double _c = 299792458;

/// Effective Earth radius for normal radio refraction (k = 4/3), metres.
const double effectiveEarthRadiusM = 6371000 * 4 / 3;

/// How the terrain between two antennas affects the first Fresnel zone.
enum TerrainVerdict {
  /// At least 60 % of the zone's radius is free along the whole path.
  clear,

  /// The direct line is free, but terrain reaches into the inner 60 %.
  partial,

  /// Terrain cuts the direct line between the antennas.
  blocked,
}

/// Evenly spaced points from [a] to [b], both ends included.
///
/// Straight interpolation in latitude and longitude, which is close enough
/// for radio paths of a few hundred kilometres. [count] is at least 2.
List<GeoPoint> profilePoints(GeoPoint a, GeoPoint b, {int count = 64}) {
  final n = math.max(2, count);
  return [
    for (var i = 0; i < n; i++)
      GeoPoint(
        a.latitude + (b.latitude - a.latitude) * i / (n - 1),
        a.longitude + (b.longitude - a.longitude) * i / (n - 1),
      ),
  ];
}

/// Radius of the first Fresnel zone, metres, at [d1M] from one end and
/// [d2M] from the other: r = √(λ·d1·d2 / (d1 + d2)), with λ = c / f.
double fresnelRadiusM(double d1M, double d2M, double frequencyMHz) {
  final total = d1M + d2M;
  if (total <= 0 || frequencyMHz <= 0 || d1M <= 0 || d2M <= 0) return 0;
  final lambda = _c / (frequencyMHz * 1e6);
  return math.sqrt(lambda * d1M * d2M / total);
}

/// How far the Earth's curve rises into a straight path at [d1M] and [d2M]
/// from its ends, metres, using the 4/3 effective radius.
double earthBulgeM(double d1M, double d2M) =>
    d1M * d2M / (2 * effectiveEarthRadiusM);

/// One sample along a terrain profile. Heights are metres above sea level.
final class ProfileSample {
  const ProfileSample({
    required this.distanceM,
    required this.groundM,
    required this.bulgeM,
    required this.lineM,
    required this.fresnelM,
  });

  /// Distance from the start of the path.
  final double distanceM;

  /// Ground height from the elevation data.
  final double groundM;

  /// Earth curve rising into the path here.
  final double bulgeM;

  /// Height of the straight line between the two antennas.
  final double lineM;

  /// First Fresnel zone radius here.
  final double fresnelM;

  /// Ground as the radio path sees it: ground height plus the Earth's curve.
  double get effectiveGroundM => groundM + bulgeM;

  /// Distance from the effective ground up to the direct line; negative
  /// when the ground is above the line.
  double get clearanceM => lineM - effectiveGroundM;

  /// [clearanceM] as a share of the zone's radius (0.6 is the usual target).
  /// Null at the ends, where the zone has no width.
  double? get zoneOpen => fresnelM > 0 ? clearanceM / fresnelM : null;
}

/// Ground heights, Earth curve, direct line and Fresnel zone between two
/// antennas, with a verdict.
final class TerrainProfile {
  TerrainProfile._(this.samples, this.frequencyMHz, this.verdict, this.worst);

  /// Builds a profile from [elevationsM], sampled evenly from start to end
  /// over [distanceM]. Antenna heights are above the ground at each end.
  factory TerrainProfile.fromElevations({
    required List<double> elevationsM,
    required double distanceM,
    required double frequencyMHz,
    double startAntennaM = 2,
    double endAntennaM = 2,
  }) {
    if (elevationsM.length < 2) {
      throw ArgumentError.value(elevationsM, 'elevationsM', 'needs 2 or more');
    }
    final n = elevationsM.length;
    final startM = elevationsM.first + startAntennaM;
    final endM = elevationsM.last + endAntennaM;
    final samples = <ProfileSample>[];
    for (var i = 0; i < n; i++) {
      final d1 = distanceM * i / (n - 1);
      final d2 = distanceM - d1;
      samples.add(
        ProfileSample(
          distanceM: d1,
          groundM: elevationsM[i],
          bulgeM: earthBulgeM(d1, d2),
          lineM: startM + (endM - startM) * i / (n - 1),
          fresnelM: fresnelRadiusM(d1, d2, frequencyMHz),
        ),
      );
    }
    ProfileSample? worst;
    for (final s in samples) {
      final open = s.zoneOpen;
      if (open == null) continue;
      if (worst == null || open < worst.zoneOpen!) worst = s;
    }
    final w = worst?.zoneOpen;
    final verdict = w == null || w >= 0.6
        ? TerrainVerdict.clear
        : w >= 0
        ? TerrainVerdict.partial
        : TerrainVerdict.blocked;
    return TerrainProfile._(
      List.unmodifiable(samples),
      frequencyMHz,
      verdict,
      worst,
    );
  }

  /// Builds a profile for [a]→[b] from elevations sampled with
  /// [profilePoints].
  factory TerrainProfile.between(
    GeoPoint a,
    GeoPoint b, {
    required List<double> elevationsM,
    required double frequencyMHz,
    double startAntennaM = 2,
    double endAntennaM = 2,
  }) => TerrainProfile.fromElevations(
    elevationsM: elevationsM,
    distanceM: haversineKm(a, b) * 1000,
    frequencyMHz: frequencyMHz,
    startAntennaM: startAntennaM,
    endAntennaM: endAntennaM,
  );

  final List<ProfileSample> samples;
  final double frequencyMHz;
  final TerrainVerdict verdict;

  /// The sample where the least of the zone is open; null when the path is
  /// too short to have one.
  final ProfileSample? worst;

  double get distanceM => samples.last.distanceM;
}
