import 'model.dart';

/// Where one node was at one time.
class TrackPoint {
  const TrackPoint(this.time, this.position);

  final DateTime time;
  final GeoPoint position;
}

/// One node's recorded positions over a stretch of time, oldest first.
class Track {
  const Track({required this.radio, required this.node, required this.points});

  final RadioId radio;
  final NodeKey node;
  final List<TrackPoint> points;

  /// The last place it was seen at or before [t]; null before its first
  /// report.
  TrackPoint? at(DateTime t) {
    // Binary search for the last point not after t.
    var lo = 0, hi = points.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (points[mid].time.isAfter(t)) {
        hi = mid - 1;
      } else {
        found = mid;
        lo = mid + 1;
      }
    }
    return found < 0 ? null : points[found];
  }

  /// The path travelled up to [t].
  List<GeoPoint> trailUntil(DateTime t) => [
    for (final p in points)
      if (!p.time.isAfter(t)) p.position,
  ];
}

/// The start of [day] and the start of the next, in local time.
(DateTime, DateTime) dayBounds(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  return (start, DateTime(day.year, day.month, day.day + 1));
}

/// The first and last report across [tracks]; null when there are none.
(DateTime, DateTime)? timeSpan(Iterable<Track> tracks) {
  DateTime? first, last;
  for (final t in tracks) {
    if (t.points.isEmpty) continue;
    final a = t.points.first.time, b = t.points.last.time;
    if (first == null || a.isBefore(first)) first = a;
    if (last == null || b.isAfter(last)) last = b;
  }
  return first == null ? null : (first, last!);
}
