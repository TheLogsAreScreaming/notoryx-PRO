import 'dart:math';

part 'regional_presets_data.dart';

/// Radio settings for a MeshCore mesh in some country or area.
class MeshCorePreset {
  const MeshCorePreset({
    required this.name,
    required this.frequencyMHz,
    required this.bandwidthKHz,
    required this.spreadingFactor,
    required this.codingRate,
    this.latitude,
    this.longitude,
    this.radiusKm,
    this.fromMap = false,
    this.retired = false,
    this.notes = '',
  });

  final String name;
  final double frequencyMHz;
  final double bandwidthKHz;
  final int spreadingFactor;
  final int codingRate;

  /// Centre and reach of a local mesh; null for country-wide presets.
  final double? latitude;
  final double? longitude;
  final double? radiusKm;

  /// Worked out from the public MeshCore map, not confirmed on air.
  final bool fromMap;

  /// Superseded by a newer preset for the same place.
  final bool retired;
  final String notes;

  bool get isLocal => latitude != null && longitude != null;

  /// Kilometres from ([lat], [lon]) to this mesh's centre; null if it has
  /// none.
  double? distanceKm(double lat, double lon) {
    final la = latitude, lo = longitude;
    if (la == null || lo == null) return null;
    return greatCircleKm(lat, lon, la, lo);
  }

  /// Whether ([lat], [lon]) is inside this local mesh's area.
  bool covers(double lat, double lon) {
    final d = distanceKm(lat, lon);
    return d != null && d <= (radiusKm ?? 0);
  }

  /// Whether a radio set to these values already uses this preset.
  bool matches(double freq, double bw, int sf, int cr) =>
      (freq - frequencyMHz).abs() < 0.0005 &&
      (bw - bandwidthKHz).abs() < 0.05 &&
      sf == spreadingFactor &&
      cr == codingRate;
}

/// Great-circle distance in kilometres.
double greatCircleKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * r * asin(sqrt(a));
}

/// MeshCore presets, grouped for choosing.
abstract final class MeshCorePresets {
  /// Country-wide presets the MeshCore project suggests.
  static const suggested = _suggested;

  /// Settings particular local meshes use.
  static const local = _local;

  /// Local meshes whose area includes ([lat], [lon]), nearest first.
  static List<MeshCorePreset> near(double lat, double lon) => [
    for (final p in local)
      if (p.covers(lat, lon)) p,
  ]..sort((a, b) => a.distanceKm(lat, lon)!.compareTo(b.distanceKm(lat, lon)!));

  /// Every local mesh, nearest first when a position is known, otherwise
  /// by name.
  static List<MeshCorePreset> localSorted({double? lat, double? lon}) {
    final list = [...local];
    if (lat != null && lon != null && (lat != 0 || lon != 0)) {
      list.sort(
        (a, b) => a.distanceKm(lat, lon)!.compareTo(b.distanceKm(lat, lon)!),
      );
    } else {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  /// Suggested presets by name, retired ones last.
  static List<MeshCorePreset> suggestedSorted() => [...suggested]
    ..sort((a, b) {
      if (a.retired != b.retired) return a.retired ? 1 : -1;
      return a.name.compareTo(b.name);
    });
}
