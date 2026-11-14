import '../radio/radio_link.dart';
import 'model.dart';
import 'node_merge.dart';
import 'signal.dart';

/// Id of the middle of the diagram: your radios.
const topologyYou = 'you';

/// One dot in the network diagram.
class TopoNode {
  const TopoNode({
    required this.id,
    required this.label,
    required this.ring,
    this.node,
    this.routes = 0,
  });

  /// [topologyYou], a node key, or `?<prefix>` for an unknown repeater.
  final String id;
  final String label;

  /// Hops from you; 0 is you.
  final int ring;

  /// The node, when known.
  final Node? node;

  /// How many known routes pass through it.
  final int routes;

  bool get unknown => id.startsWith('?');
}

/// A link seen between two dots.
class TopoLink {
  const TopoLink(this.a, this.b, this.count);
  final String a;
  final String b;

  /// How many routes use it.
  final int count;
}

/// What your radios know about how the mesh fits together.
class Topology {
  const Topology({required this.nodes, required this.links});

  final Map<String, TopoNode> nodes;
  final List<TopoLink> links;

  /// Dots on [ring], busiest first.
  List<TopoNode> ring(int ring) =>
      nodes.values.where((n) => n.ring == ring).toList()
        ..sort((a, b) => b.routes.compareTo(a.routes));

  int get rings => nodes.values.fold(0, (m, n) => n.ring > m ? n.ring : m);

  /// Builds the diagram from every node your radios hold.
  ///
  /// Each node sits on the ring for its last known hop count (nodes with
  /// none are left out). MeshCore routes add links from you through each
  /// repeater to the node; a repeater the route names but no radio knows is
  /// shown by its hash prefix. Nodes heard directly link straight to you.
  /// Meshtastic doesn't report which nodes relayed, so its nodes beyond
  /// one hop sit on their ring without links.
  ///
  /// [resolve] names each route's hops; [resolveRoute] by default.
  factory Topology.build(
    List<Node> all, {
    int maxNodes = 60,
    List<RouteHop> Function(Node target, Iterable<Node> known) resolve =
        resolveRoute,
  }) {
    final merged = mergeAcrossRadios(all).map((m) => m.node).toList();
    final nodes = <String, TopoNode>{
      topologyYou: const TopoNode(id: topologyYou, label: '', ring: 0),
    };
    final counts = <String, int>{};
    final relays = <String, int>{};
    final ringOf = <String, int>{};
    void link(String a, String b) {
      final k = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      counts[k] = (counts[k] ?? 0) + 1;
    }

    for (final n in merged) {
      final hops = n.path.hops;
      if (hops == null) continue;
      final id = n.key.toString();
      ringOf[id] = hops + 1;
      if (hops == 0) {
        link(topologyYou, id);
        continue;
      }
      if (n.protocol != RadioProtocol.meshcore || n.route.isEmpty) continue;
      final route = resolve(n, all.where((k) => k.radioId == n.radioId));
      var prev = topologyYou;
      for (var i = 0; i < route.length; i++) {
        final h = route[i];
        final hopId = h.node?.key.toString() ?? '?${h.prefix}';
        relays[hopId] = (relays[hopId] ?? 0) + 1;
        ringOf[hopId] = ringOf[hopId] == null
            ? i + 1
            : (ringOf[hopId]! < i + 1 ? ringOf[hopId]! : i + 1);
        if (h.node == null) {
          nodes.putIfAbsent(
            hopId,
            () => TopoNode(
              id: hopId,
              label: h.onlineName ?? h.prefix,
              ring: i + 1,
            ),
          );
        }
        link(prev, hopId);
        prev = hopId;
      }
      link(prev, id);
    }

    // Keep the busiest and nearest when there are too many to draw.
    final byKey = {for (final n in merged) n.key.toString(): n};
    final candidates = ringOf.keys.toList()
      ..sort((a, b) {
        final r = (relays[b] ?? 0).compareTo(relays[a] ?? 0);
        return r != 0 ? r : ringOf[a]!.compareTo(ringOf[b]!);
      });
    for (final id in candidates.take(maxNodes)) {
      final n = byKey[id];
      nodes[id] = TopoNode(
        id: id,
        label: n?.displayName ?? nodes[id]?.label ?? id,
        ring: ringOf[id]!,
        node: n,
        routes: relays[id] ?? 0,
      );
    }
    nodes.removeWhere((id, _) => id != topologyYou && !ringOf.containsKey(id));
    nodes.removeWhere(
      (id, _) => id != topologyYou && !candidates.take(maxNodes).contains(id),
    );

    final links = <TopoLink>[
      for (final e in counts.entries)
        if (e.key.split('|') case [
          final a,
          final b,
        ] when nodes.containsKey(a) && nodes.containsKey(b))
          TopoLink(a, b, e.value),
    ]..sort((x, y) => x.count.compareTo(y.count));
    return Topology(nodes: nodes, links: links);
  }
}
