import 'hop_naming.dart';
import 'model.dart';

/// Signal strength as 0–4 bars, from the SNR at our radio; null if unknown.
///
/// LoRa still decodes well below 0 dB, so the scale reaches down to about
/// -10 dB before a link is called poor. For a node heard through repeaters
/// this is the last hop's signal, not the node's own.
int? signalBars(PathFacts path) {
  final snr = path.snr;
  if (snr == null) return null;
  if (snr >= 5) return 4;
  if (snr >= 0) return 3;
  if (snr >= -5) return 2;
  if (snr >= -10) return 1;
  return 0;
}

/// One hop of a MeshCore route.
class RouteHop {
  const RouteHop(this.prefix, this.node, {this.onlineName});

  /// The repeater's hash prefix as hex (1–3 bytes).
  final String prefix;

  /// The repeater, when one known node matches the prefix, or [HopNaming]
  /// picked one of several.
  final Node? node;

  /// A name found online for a prefix no radio knows.
  final String? onlineName;
}

/// Resolves [target]'s MeshCore route into repeaters from [known].
///
/// Each hop names a repeater by the first byte(s) of its public key. A hop
/// matched by exactly one known node from the same radio is that node.
/// Without [naming], a hop several nodes match stays unknown rather than
/// guessing; with it, positions (walking from [from], your radio) or a
/// remembered pick can decide, and unknown hops can carry a name found
/// online.
List<RouteHop> resolveRoute(
  Node target,
  Iterable<Node> known, {
  HopNaming? naming,
  GeoPoint? from,
  DateTime? now,
}) {
  final size = target.routeHashSize;
  final route = target.route;
  if (route.isEmpty) return const [];
  final candidates = [
    for (final n in known)
      if (n.radioId == target.radioId && n.key != target.key) n,
  ];
  final at = now ?? DateTime.now();
  var previous = from;
  final hops = <RouteHop>[];
  for (var i = 0; i + size <= route.length; i += size) {
    final prefix = route
        .sublist(i, i + size)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final matches = [
      for (final n in candidates)
        if (n.key.native.startsWith(prefix)) n,
    ];
    final node = switch (matches.length) {
      1 => matches.single,
      0 => null,
      _ => naming?.choose(prefix, matches, previous, at),
    };
    previous = node?.position;
    hops.add(
      RouteHop(
        prefix,
        node,
        onlineName: matches.isEmpty ? naming?.found[prefix] : null,
      ),
    );
  }
  return hops;
}
