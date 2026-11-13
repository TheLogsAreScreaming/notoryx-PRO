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
  List<Place> _routes = const [];
  final Map<String, bool> _inside = {};
  final Map<String, bool> _offRoute = {};
  final Map<String, DateTime> _last = {};

  /// Writes the notification text; replaced with the person's language.
  String Function(String node, String fence, bool entered) describe =
      (node, fence, entered) => '$node ${entered ? 'entered' : 'left'} $fence';

  /// Writes the off-route notification text.
  String Function(String node, String route, int metres) describeOffRoute =
      (node, route, metres) => '$node is $metres m off $route';

  /// Looks for crossings in [nodes].
  void check(List<Node> nodes) {
    _checkRoutes(nodes);
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

  /// Notifies once when someone who was on a watched route goes farther
  /// off it than its limit. The first position seen only records; coming
  /// back within 70% of the limit re-arms it.
  void _checkRoutes(List<Node> nodes) {
    for (final r in _routes) {
      final limit = r.radiusM!;
      for (final n in nodes) {
        final at = n.position;
        if (at == null) continue;
        final metres = metresFromLine(at, r.points);
        if (metres == null) continue;
        final key = '${r.id}|${n.key}';
        final was = _offRoute[key];
        final off = was == true ? metres > limit * .7 : metres > limit;
        _offRoute[key] = off;
        if (was != false || !off) continue;
        final now = _now();
        final last = _last['route|$key'];
        if (last != null && now.difference(last) < gap) continue;
        _last['route|$key'] = now;
        unawaited(
          notifier.show(
            id: 0x30000000 | (key.hashCode & 0xfffffff),
            title: r.name,
            body: describeOffRoute(n.name, r.name, metres.round()),
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
      final routes = [
        for (final x in p)
          if (x.watchesRoute) x,
      ];
      // A route whose limit changed starts over.
      final limits = {for (final r in routes) r.id: r.radiusM};
      final before = {for (final r in _routes) r.id: r.radiusM};
      for (final id in {...limits.keys, ...before.keys}) {
        if (limits[id] != before[id]) {
          _offRoute.removeWhere((k, _) => k.startsWith('$id|'));
        }
      }
      _routes = routes;
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
