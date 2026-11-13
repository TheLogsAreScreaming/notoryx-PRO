import 'dart:math' as math;

import 'model.dart';

/// What a saved place is.
enum PlaceKind { waypoint, route, geofence }

/// A saved point, line or circle on the map.
class Place {
  const Place({
    this.id = 0,
    required this.kind,
    required this.name,
    required this.points,
    this.radiusM,
    this.alerts = true,
  });

  final int id;
  final PlaceKind kind;
  final String name;

  /// One point, or the whole line for a route.
  final List<GeoPoint> points;

  /// Size of a geofence, in metres. For a route: how far off it someone
  /// can go before an off-route alert; null when the route isn't watched.
  final double? radiusM;

  /// Whether a geofence (or a watched route) notifies.
  final bool alerts;

  /// A route with an off-route alert set.
  bool get watchesRoute =>
      kind == PlaceKind.route && alerts && radiusM != null && points.length > 1;
}

/// Shortest distance from [p] to the line through [line], in metres.
///
/// Each segment is flattened around [p], accurate to well under a metre at
/// trail scales. Null for an empty line.
double? metresFromLine(GeoPoint p, List<GeoPoint> line) {
  if (line.isEmpty) return null;
  const earth = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final k = math.cos(rad(p.latitude));
  ({double x, double y}) local(GeoPoint q) => (
    x: rad(q.longitude - p.longitude) * k * earth,
    y: rad(q.latitude - p.latitude) * earth,
  );
  var a = local(line.first);
  var best = math.sqrt(a.x * a.x + a.y * a.y);
  for (var i = 1; i < line.length; i++) {
    final b = local(line[i]);
    final dx = b.x - a.x, dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(a.x * dx + a.y * dy) / len2).clamp(0.0, 1.0);
    final px = a.x + t * dx, py = a.y + t * dy;
    best = math.min(best, math.sqrt(px * px + py * py));
    a = b;
  }
  return best;
}

/// A rough radio link estimate between two points on open ground.
class LinkBudget {
  const LinkBudget({
    required this.distanceKm,
    required this.pathLossDb,
    required this.receivedDbm,
    required this.marginDb,
  });

  /// Works it out. Knows nothing of hills, trees or buildings.
  factory LinkBudget.estimate({
    required double distanceKm,
    required double frequencyMHz,
    required double txDbm,
    required double antennaGainDb,
    required double sensitivityDbm,
  }) {
    double log10(double x) => math.log(x) / math.ln10;
    final d = math.max(distanceKm, .001);
    final loss = 32.44 + 20 * log10(d) + 20 * log10(frequencyMHz);
    final rx = txDbm + antennaGainDb - loss;
    return LinkBudget(
      distanceKm: distanceKm,
      pathLossDb: loss,
      receivedDbm: rx,
      marginDb: rx - sensitivityDbm,
    );
  }

  final double distanceKm;

  /// Free-space path loss.
  final double pathLossDb;
  final double receivedDbm;

  /// Signal to spare; below zero, the radio can't hear it.
  final double marginDb;
}
