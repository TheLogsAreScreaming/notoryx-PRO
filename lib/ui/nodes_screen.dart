import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/mesh.dart';
import 'common.dart';
import 'conversation_screen.dart';
import 'verify_screen.dart';

/// Every node both radios have heard, most recent first.
class NodesScreen extends StatelessWidget {
  const NodesScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<NodeKey, Verification>>(
      stream: app.store.watchVerifications(),
      builder: (context, vSnap) => StreamBuilder<List<Node>>(
        stream: app.store.watchAllNodes(),
        builder: (context, snap) {
          final nodes = snap.data ?? const <Node>[];
          if (nodes.isEmpty) {
            return EmptyState(
              context.l10n.nodesEmpty,
              icon: Icons.hub_outlined,
            );
          }
          final verified = vSnap.data ?? const {};
          return ListView.builder(
            itemCount: nodes.length,
            itemBuilder: (context, i) => NodeTile(
              app: app,
              node: nodes[i],
              trust: trustOf(nodes[i], verified[nodes[i].key]),
            ),
          );
        },
      ),
    );
  }
}

/// One node: kind, mesh, how it was last heard.
class NodeTile extends StatelessWidget {
  const NodeTile({
    super.key,
    required this.app,
    required this.node,
    this.trust = TrustStatus.unverified,
  });

  final AppController app;
  final Node node;
  final TrustStatus trust;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final n = node;
    final details = [
      nodeKindName(context, n.kind),
      if (n.lastHeard != null) l.lastHeard(ago(context, n.lastHeard!)),
      if (pathSummary(context, n.path) case final p when p.isNotEmpty) p,
      if (!n.canMessage) l.nodeCannotMessage,
    ].join(' · ');
    return ListTile(
      leading: Icon(
        nodeKindIcon(n.kind),
        semanticLabel: nodeKindName(context, n.kind),
      ),
      title: Row(
        children: [
          Flexible(child: Text(n.displayName, overflow: TextOverflow.ellipsis)),
          if (n.shortName.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text('(${n.shortName})'),
          ],
          const SizedBox(width: 8),
          ProtocolBadge(n.protocol),
          const SizedBox(width: 4),
          TrustBadge(trust),
          if (n.isFavorite) const Icon(Icons.star, size: 16),
          const SizedBox(width: 8),
          SignalBars(signalBars(n.path)),
        ],
      ),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: n.canMessage && n.kind != NodeKind.relay
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ConversationScreen(
                  app: app,
                  conversation: DirectConversation(n.radioId, n.key),
                  title: n.displayName,
                ),
              ),
            )
          : null,
    );
  }
}
