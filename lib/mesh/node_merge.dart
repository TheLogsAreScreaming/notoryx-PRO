import 'model.dart';

/// One node as heard by one or more of your radios.
class MergedNode {
  const MergedNode(this.node, this.radios);

  /// The copy from the radio that heard it most recently; messages to it
  /// go through that radio.
  final Node node;

  /// How many of your radios have heard it.
  final int radios;
}

/// Folds the same node heard by several radios into one entry, keeping
/// the order of [nodes] (most recently heard first).
///
/// Nodes are the same when their keys match: a MeshCore key or a
/// Meshtastic node number. The two meshes are never merged with each
/// other.
List<MergedNode> mergeAcrossRadios(List<Node> nodes) {
  final best = <NodeKey, Node>{};
  final count = <NodeKey, int>{};
  final order = <NodeKey>[];
  for (final n in nodes) {
    final seen = best[n.key];
    count[n.key] = (count[n.key] ?? 0) + 1;
    if (seen == null) {
      order.add(n.key);
      best[n.key] = n;
    } else if (_newer(n, seen)) {
      best[n.key] = _withPosition(n, seen);
    } else if (seen.position == null && n.position != null) {
      best[n.key] = _withPosition(seen, n);
    }
  }
  return [for (final k in order) MergedNode(best[k]!, count[k]!)];
}

bool _newer(Node a, Node b) {
  final (x, y) = (a.lastHeard, b.lastHeard);
  if (x == null) return false;
  return y == null || x.isAfter(y);
}

/// [primary], borrowing [other]'s position if it has none of its own.
Node _withPosition(Node primary, Node other) =>
    primary.position != null || other.position == null
    ? primary
    : primary.copyWith(position: other.position);
