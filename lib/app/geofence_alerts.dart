import 'dart:async';

import '../mesh/diagnostics.dart' show haversineKm;
import '../mesh/model.dart';
import '../mesh/places.dart';
import '../store/mesh_store.dart';
import 'message_alerts.dart';

/// Notifies when a node crosses a geofence.
///
/// The first position seen for a node only sets where it is, so opening the
/// app doesn't announce everything. A node must go 10% past the edge to
/// count as having left, so a noisy GPS can't flap in and out, and each
/// node and fence alerts at most once per [gap].
class GeofenceAlerts {
  GeofenceAlerts({
    required this.store,
    required this.notifier,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The shortest time between alerts for one node and fence.
  static const gap = Duration(minutes: 5);

  final MeshStore store;
  final Notifier notifier;
  final DateTime Function() _now;
  StreamSubscription<List<Place>>? _places;
  StreamSubscription<List<Node>>? _nodes;
  List<Place> _fences = const [];
  final Map<String, bool> _inside = {};
  final Map<String, DateTime> _last = {};

  /// Writes the notification text; replaced with the person's language.
  String Function(String node, String fence, bool entered) describe =
      (node, fence, entered) => '$node ${entered ? 'entered' : 'left'} $fence';

  /// Looks for crossings in [nodes].
  void check(List<Node> nodes) {
    for (final f in _fences) {
      final radius = f.radiusM;
      if (radius == null) continue;
      for (final n in nodes) {
        final at = n.position;
        if (at == null) continue;
        final metres = haversineKm(f.points.first, at) * 1000;
        final key = '${f.id}|${n.key}';
        final was = _inside[key];
        final inside = was == true ? metres <= radius * 1.1 : metres <= radius;
        _inside[key] = inside;
        if (was == null || was == inside) continue;
        final now = _now();
        final last = _last[key];
        if (last != null && now.difference(last) < gap) continue;
        _last[key] = now;
        unawaited(
          notifier.show(
            id: 0x20000000 | (key.hashCode & 0xfffffff),
            title: f.name,
            body: describe(n.name, f.name, inside),
            payload: 'geofence',
          ),
        );
      }
    }
  }

  /// Starts watching.
  void start() {
    _places ??= store.watchPlaces().listen((p) {
      _fences = [
        for (final x in p)
          if (x.kind == PlaceKind.geofence && x.alerts) x,
      ];
    });
    _nodes ??= store.watchAllNodes().listen(check);
  }

  /// Stops watching.
  void stop() {
    unawaited(_places?.cancel());
    unawaited(_nodes?.cancel());
    _places = null;
    _nodes = null;
  }
}
