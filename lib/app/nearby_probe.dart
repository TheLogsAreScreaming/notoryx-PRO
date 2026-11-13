import '../mesh/model.dart';

/// A node in direct radio range, found by a nearby test.
class NearbyNode {
  const NearbyNode({
    required this.id,
    required this.name,
    required this.kind,
    this.answered = true,
    this.snr,
    this.rssi,
    this.heardUsSnr,
    this.node,
    this.lastHeard,
  });

  /// Node key (or key prefix) as text, for telling answers apart.
  final String id;
  final String name;
  final NodeKind kind;

  /// It answered this test; false when it was only heard directly a
  /// little earlier and kept quiet now.
  final bool answered;

  /// How our radio heard it: SNR in dB and RSSI in dBm.
  final double? snr;
  final int? rssi;

  /// MeshCore: the SNR in dB at which it heard our request.
  final double? heardUsSnr;

  /// The stored node, when the app knows it.
  final Node? node;

  /// When it was last heard, for nodes that didn't answer.
  final DateTime? lastHeard;

  /// Repeaters and other infrastructure.
  bool get isInfrastructure => kind == NodeKind.relay || kind == NodeKind.room;
}

/// How long a node heard directly still counts as "nearby, kept quiet".
const nearbyRecent = Duration(minutes: 30);

/// Puts a test's [answers] first, then the [known] nodes of the same radio
/// heard directly (0 hops) within [nearbyRecent] that didn't answer.
/// Infrastructure comes before other nodes, stronger signal first.
List<NearbyNode> mergeNearby(
  List<NearbyNode> answers,
  Iterable<Node> known, {
  required DateTime now,
  bool infrastructureOnly = false,
}) {
  final seen = {for (final a in answers) a.id};
  final quiet = [
    for (final n in known)
      if (n.path.hops == 0 &&
          !n.path.viaMqtt &&
          n.lastHeard != null &&
          now.difference(n.lastHeard!) <= nearbyRecent &&
          !seen.contains(n.key.native))
        NearbyNode(
          id: n.key.native,
          name: n.displayName,
          kind: n.kind,
          answered: false,
          snr: n.path.snr,
          rssi: n.path.rssi,
          node: n,
          lastHeard: n.lastHeard,
        ),
  ];
  int order(NearbyNode a, NearbyNode b) {
    if (a.answered != b.answered) return a.answered ? -1 : 1;
    if (a.isInfrastructure != b.isInfrastructure) {
      return a.isInfrastructure ? -1 : 1;
    }
    return (b.snr ?? -99).compareTo(a.snr ?? -99);
  }

  return [
    for (final n in [...answers, ...quiet])
      if (!infrastructureOnly || n.isInfrastructure) n,
  ]..sort(order);
}
