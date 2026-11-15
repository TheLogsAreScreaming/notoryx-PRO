import 'dart:math' as math;

import 'model.dart';

/// Initial great-circle bearing from [from] to [to], degrees from true
/// north (0-360).
double bearingDegrees(GeoPoint from, GeoPoint to) {
  double r(double d) => d * math.pi / 180;
  final (p1, p2) = (r(from.latitude), r(to.latitude));
  final dl = r(to.longitude - from.longitude);
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// How far to turn from [heading] to face [bearing]: negative is left,
/// positive right, always the short way (-180 to 180).
double turnDegrees(double heading, double bearing) {
  final d = (bearing - heading) % 360;
  return d > 180 ? d - 360 : d;
}

/// Moves [current] a [fraction] of the way towards [next], the short way
/// round, so 359° to 1° doesn't spin through 180°.
double smoothHeading(double current, double next, {double fraction = 0.25}) =>
    (current + turnDegrees(current, next) * fraction + 360) % 360;

/// Which of the eight compass points [degrees] is nearest (0 = N, 1 = NE…).
int compassPoint(double degrees) => ((degrees % 360) / 45).round() % 8;

/// Within this many degrees counts as facing the node.
const onTargetDegrees = 10.0;
