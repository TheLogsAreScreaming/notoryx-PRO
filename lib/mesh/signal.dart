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
  const RouteHop(this.prefix, this.node);

  /// The repeater's hash prefix as hex (1–3 bytes).
  final String prefix;

  /// The repeater, when exactly one known node matches the prefix.
  final Node? node;
}

/// Resolves [target]'s MeshCore route into repeaters from [known].
///
/// Each hop names a repeater by the first byte(s) of its public key. A hop
/// is only matched when exactly one known node from the same radio starts
/// with that prefix; otherwise it stays unknown rather than guessing.
List<RouteHop> resolveRoute(Node target, Iterable<Node> known) {
  final size = target.routeHashSize;
  final route = target.route;
  if (route.isEmpty) return const [];
  final candidates = [
    for (final n in known)
      if (n.radioId == target.radioId && n.key != target.key) n,
  ];
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
    hops.add(RouteHop(prefix, matches.length == 1 ? matches.single : null));
  }
  return hops;
}
