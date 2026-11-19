/// Distance rings around your position on the map: sizes, labels and the
/// points they pass through.
library;

import 'dart:math' as math;

import 'model.dart';

/// How many rings are drawn.
const ringCount = 4;

/// Metres in a statute mile.
const metresPerMile = 1609.344;

/// The smallest ring step: 10 m, or 0.1 mi.
const minMetricStep = 10.0;
const minImperialStepMiles = 0.1;

/// Whether distances read in miles where [countryCode] is (an ISO 3166
/// region such as `US`). Only the US, Liberia and Myanmar use miles.
bool usesMiles(String? countryCode) =>
    const {'US', 'LR', 'MM'}.contains(countryCode?.toUpperCase());

/// [raw] metres rounded down to a 1, 2 or 5 × 10ⁿ step, counted in metres
/// or (with [imperial]) in miles. Never below 10 m / 0.1 mi. Returns metres.
double niceStep(double raw, {bool imperial = false}) {
  final unit = imperial ? metresPerMile : 1.0;
  final min = imperial ? minImperialStepMiles : minMetricStep;
  final value = raw / unit;
  if (!value.isFinite || value <= min) return min * unit;
  // A tiny allowance so float error (log10(1000) = 2.9999…, 0.3 / 0.1 =
  // 2.9999…) can't drop a step.
  final power = math
      .pow(10, (math.log(value) / math.ln10 + 1e-9).floor())
      .toDouble();
  final lead = value / power + 1e-9;
  final step = lead >= 5
      ? 5
      : lead >= 2
      ? 2
      : 1;
  return math.max(step * power, min) * unit;
}

/// The radii, in metres, of [ringCount] rings sized to a view whose
/// nearer edge is [nearEdgeMetres] from its centre.
List<double> ringRadii(double nearEdgeMetres, {bool imperial = false}) {
  final step = niceStep(nearEdgeMetres / ringCount, imperial: imperial);
  return [for (var i = 1; i <= ringCount; i++) step * i];
}

/// A ring's label such as `500 m`, `1.5 km` or `0.2 mi`.
String ringLabel(double metres, {bool imperial = false}) {
  if (imperial) return '${_trim(metres / metresPerMile)} mi';
  if (metres < 1000) return '${metres.round()} m';
  return '${_trim(metres / 1000)} km';
}

/// [v] with up to two decimals and no trailing zeros.
String _trim(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.')
      ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : s;
}

/// Mean Earth radius, metres (the same sphere as the app's distances).
const _earthRadius = 6371000.0;

/// The point [metres] from [from] along [bearing] degrees (0 = north,
/// clockwise), on a sphere.
GeoPoint pointAt(GeoPoint from, double bearing, double metres) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final d = metres / _earthRadius;
  final b = rad(bearing);
  final lat1 = rad(from.latitude);
  final lon1 = rad(from.longitude);
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(b),
  );
  final lon2 =
      lon1 +
      math.atan2(
        math.sin(b) * math.sin(d) * math.cos(lat1),
        math.cos(d) - math.sin(lat1) * math.sin(lat2),
      );
  // Back into -180..180.
  final lon = (deg(lon2) + 540) % 360 - 180;
  return GeoPoint(deg(lat2), lon);
}
