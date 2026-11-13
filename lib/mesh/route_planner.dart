import 'diagnostics.dart';
import 'model.dart';

/// Where a route choice came from.
enum RouteSource {
  /// The route the radio uses now.
  current,

  /// A route a saved trace measured.
  trace,

  /// Built by hand from known repeaters.
  manual,
}

/// One repeater on a route, with how well each side of its link heard.
class PlannedHop {
  const PlannedHop({
    required this.hash,
    required this.label,
    this.snr,
    this.backSnr,
    this.node,
  });

  /// The repeater's hash prefix as hex.
  final String hash;

  /// Repeater name, or [hash] when it isn't known.
  final String label;

  /// SNR in dB at which this repeater heard the packet on the way out.
  final double? snr;

  /// SNR in dB on the same link on the way back, when measured.
  final double? backSnr;
  final Node? node;

  /// The worse of the two directions, or whichever was measured.
  double? get worstSnr => switch ((snr, backSnr)) {
    (final a?, final b?) => a < b ? a : b,
    (final a?, null) => a,
    (null, final b?) => b,
    _ => null,
  };
}

/// A route to a node, with its link quality where a trace measured it.
class RouteChoice {
  const RouteChoice({required this.hops, required this.source, this.measured});

  /// Repeaters in order from our radio; empty means a direct link.
  final List<PlannedHop> hops;
  final RouteSource source;

  /// When a trace last measured this route; null if never.
  final DateTime? measured;

  /// The route as hex prefixes, for [MeshCoreConnection.setRoute].
  List<String> get hashes => [for (final h in hops) h.hash];

  /// Hops whose link quality nobody has measured.
  int get unmeasured => hops.where((h) => h.worstSnr == null).length;

  /// The weakest measured link, in dB; null if none was measured.
  double? get weakestSnr {
    double? w;
    for (final h in hops) {
      final s = h.worstSnr;
      if (s != null && (w == null || s < w)) w = s;
    }
    return w;
  }

  /// How likely the route is to deliver: higher is better.
  ///
  /// The weakest link matters most (a chain is only as good as it), each
  /// extra hop is another chance to lose the packet, unmeasured links
  /// count as poor, and old measurements count for less.
  double score(DateTime now) {
    final weakest = weakestSnr ?? -12;
    var s = weakest - 1.5 * hops.length - 3.0 * unmeasured;
    final at = measured;
    if (at != null) {
      final days = now.difference(at).inHours / 24;
      s -= (days * 0.5).clamp(0, 5);
    } else {
      s -= 5;
    }
    return s;
  }

  /// Same repeaters in the same order.
  bool sameRoute(RouteChoice other) =>
      hashes.length == other.hashes.length &&
      [
        for (var i = 0; i < hashes.length; i++) hashes[i] == other.hashes[i],
      ].every((x) => x);
}

/// Routes to one MeshCore node: the current one and every other the
/// saved traces measured, best first, with a suggestion when one of them
/// looks clearly better than the current route.
class RoutePlan {
  const RoutePlan({required this.current, required this.others, this.better});

  /// The route the radio uses now; null when it floods.
  final RouteChoice? current;

  /// Measured alternatives, best first (the current route isn't repeated).
  final List<RouteChoice> others;

  /// The alternative worth switching to, if any.
  final RouteChoice? better;

  /// A suggestion must beat the current route by this much score.
  static const margin = 2.0;

  /// Builds the plan for [target] from its [traces] (newest first) and the
  /// [known] nodes of the same radio, as of [now].
  factory RoutePlan.build(
    Node target,
    List<SavedTrace> traces,
    Iterable<Node> known, {
    required DateTime now,
  }) {
    final byPrefix = _Prefixes(target, known);
    final measured = <RouteChoice>[];
    for (final t in traces) {
      final c = fromTrace(t.result, byPrefix.lookup);
      if (c == null || measured.any(c.sameRoute)) continue;
      measured.add(c);
    }
    RouteChoice? current;
    final size = target.routeHashSize;
    if (target.route.isNotEmpty) {
      final hashes = [
        for (var i = 0; i + size <= target.route.length; i += size)
          target.route
              .sublist(i, i + size)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
      ];
      final plain = RouteChoice(
        source: RouteSource.current,
        hops: [
          for (final h in hashes)
            PlannedHop(
              hash: h,
              label: byPrefix.lookup(h)?.displayName ?? h,
              node: byPrefix.lookup(h),
            ),
        ],
      );
      // Borrow the newest measurement of the same route.
      final same = measured.where(plain.sameRoute).firstOrNull;
      current = same == null
          ? plain
          : RouteChoice(
              hops: same.hops,
              source: RouteSource.current,
              measured: same.measured,
            );
    }
    final others = [
      for (final c in measured)
        if (current == null || !c.sameRoute(current)) c,
    ]..sort((a, b) => b.score(now).compareTo(a.score(now)));
    RouteChoice? better;
    final best = others.firstOrNull;
    if (best != null) {
      final bar = current == null ? -1e9 : current.score(now) + margin;
      if (best.score(now) > bar) better = best;
    }
    return RoutePlan(current: current, others: others, better: better);
  }

  /// A route from a MeshCore trace, if every hop kept its hash.
  ///
  /// A trace goes out through hops h0…hk-1 and back through hk-2…h0, then
  /// reaches our radio. `towards[i]` is how hop i heard the link into it;
  /// the same link the other way is `back[k-1-i]`, and for the first link
  /// it is our radio's own SNR, the last entry of `back`.
  static RouteChoice? fromTrace(
    TraceResult r,
    Node? Function(String hash) lookup,
  ) {
    final out = r.towards;
    if (out.isEmpty || out.any((h) => h.hash == null)) return null;
    final size = out.first.hash!.length;
    if (out.any((h) => h.hash!.length != size)) return null;
    final back = r.back;
    final k = out.length;
    double? backFor(int i) {
      // Hop i's link back toward us is heard by hop i-1, or by our radio.
      final j = i == 0 ? back.length - 1 : k - 1 - i;
      if (j < 0 || j >= back.length) return null;
      return back[j].snr;
    }

    return RouteChoice(
      source: RouteSource.trace,
      measured: r.time,
      hops: [
        for (var i = 0; i < k; i++)
          PlannedHop(
            hash: out[i].hash!,
            label: lookup(out[i].hash!)?.displayName ?? out[i].label,
            node: lookup(out[i].hash!),
            snr: out[i].snr,
            backSnr: backFor(i),
          ),
      ],
    );
  }
}

/// Repeaters that can be put on a hand-built route to [target]: relays and
/// rooms of the same radio with a full key, most recently heard first.
List<Node> routeCandidates(Node target, Iterable<Node> known) =>
    [
      for (final n in known)
        if (n.radioId == target.radioId &&
            n.key != target.key &&
            (n.kind == NodeKind.relay || n.kind == NodeKind.room) &&
            n.publicKey.length == 32)
          n,
    ]..sort(
      (a, b) => (b.lastHeard?.millisecondsSinceEpoch ?? 0).compareTo(
        a.lastHeard?.millisecondsSinceEpoch ?? 0,
      ),
    );

/// [node]'s hash prefix of [size] bytes, as hex.
String hopHash(Node node, int size) => node.publicKey
    .take(size)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

class _Prefixes {
  _Prefixes(Node target, Iterable<Node> known)
    : _nodes = [
        for (final n in known)
          if (n.radioId == target.radioId && n.key != target.key) n,
      ];

  final List<Node> _nodes;

  /// The one node whose key starts with [hash], else null.
  Node? lookup(String hash) {
    final m = [
      for (final n in _nodes)
        if (n.key.native.startsWith(hash)) n,
    ];
    return m.length == 1 ? m.single : null;
  }
}
