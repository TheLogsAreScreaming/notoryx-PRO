import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mesh/mesh.dart';
import '../store/mesh_store.dart';

/// Where a followed node was, and whether it answered a request or came
/// from its own broadcast.
class FollowFix {
  const FollowFix(this.time, this.position, {required this.asked});

  final DateTime time;
  final GeoPoint position;
  final bool asked;
}

/// Follows one node for a short time: asks it for its position every few
/// minutes (where the protocol can), takes the positions it broadcasts,
/// and keeps its trail in memory. Stops by itself after [length].
class FollowTracker extends ChangeNotifier {
  FollowTracker({
    required this.store,
    required this.ask,
    this.length = const Duration(minutes: 15),
    this.askEvery = const Duration(minutes: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MeshStore store;

  /// Asks [node] for its position; returns null without asking when its
  /// radio can't (not connected, or a protocol without requests).
  final Future<GeoPoint?>? Function(Node node) ask;

  final Duration length;
  final Duration askEvery;
  final DateTime Function() _now;

  /// Moves shorter than this only refresh the last point.
  static const minMoveMetres = 5.0;

  Node? _node;
  DateTime? _started;
  final List<FollowFix> _trail = [];
  int _asked = 0;
  int _answered = 0;
  Timer? _askTimer;
  Timer? _endTimer;
  StreamSubscription<List<Node>>? _nodes;

  Node? get node => _node;
  bool get active => _node != null;
  List<FollowFix> get trail => List.unmodifiable(_trail);
  int get asked => _asked;
  int get answered => _answered;
  DateTime get now => _now();

  Duration get remaining {
    final s = _started;
    if (s == null) return Duration.zero;
    final left = s.add(length).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isFollowing(Node n) =>
      _node?.key == n.key && _node?.radioId == n.radioId;

  /// Starts following [n]; any other node stops first.
  void start(Node n) {
    stop(notify: false);
    _node = n;
    _started = now;
    if (n.position case final p?) _add(p, asked: false);
    _nodes = store.watchNodes(n.radioId).listen(_onNodes);
    _endTimer = Timer(length, stop);
    _askTimer = Timer.periodic(askEvery, (_) => unawaited(askNow()));
    notifyListeners();
    unawaited(askNow());
  }

  /// Stops and forgets the trail.
  void stop({bool notify = true}) {
    if (_node == null) return;
    _askTimer?.cancel();
    _endTimer?.cancel();
    unawaited(_nodes?.cancel());
    _nodes = null;
    _node = null;
    _started = null;
    _trail.clear();
    _asked = 0;
    _answered = 0;
    if (notify) notifyListeners();
  }

  /// Asks the node for its position now, where its radio can.
  Future<void> askNow() async {
    final n = _node;
    if (n == null) return;
    final reply = ask(n);
    if (reply == null) return;
    _asked++;
    notifyListeners();
    try {
      final p = await reply;
      if (!isFollowing(n)) return;
      _answered++;
      if (p != null) _add(p, asked: true);
      notifyListeners();
    } on Object catch (_) {
      // No answer this time; the next ask tries again.
    }
  }

  void _onNodes(List<Node> nodes) {
    final n = _node;
    if (n == null) return;
    for (final m in nodes) {
      if (m.key != n.key) continue;
      final p = m.position;
      if (p == null) return;
      if (_trail.isNotEmpty && _trail.last.position == p) return;
      _add(p, asked: false);
      notifyListeners();
      return;
    }
  }

  void _add(GeoPoint p, {required bool asked}) {
    final fix = FollowFix(now, p, asked: asked);
    if (_trail.isNotEmpty &&
        haversineKm(_trail.last.position, p) * 1000 < minMoveMetres) {
      _trail[_trail.length - 1] = fix;
      return;
    }
    _trail.add(fix);
  }

  @override
  void dispose() {
    stop(notify: false);
    super.dispose();
  }
}
