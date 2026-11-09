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

  /// Size of a geofence, in metres.
  final double? radiusM;

  /// Whether a geofence notifies.
  final bool alerts;
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
