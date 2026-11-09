import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/mesh.dart';
import '../radio/radio_link.dart';
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
      builder: (context, vSnap) => StreamBuilder<Set<String>>(
        stream: app.store.watchAllRadioContacts(),
        builder: (context, cSnap) => StreamBuilder<List<Node>>(
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
                appOnly:
                    cSnap.hasData &&
                    nodes[i].protocol == RadioProtocol.meshcore &&
                    !cSnap.data!.contains(
                      '${nodes[i].radioId}|${nodes[i].key}',
                    ),
              ),
            );
          },
        ),
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
    this.appOnly = false,
  });

  final AppController app;
  final Node node;
  final TrustStatus trust;

  /// A MeshCore node the app keeps but the radio's contact list doesn't
  /// hold; it is added when messaged.
  final bool appOnly;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final n = node;
    final details = [
      nodeKindName(context, n.kind),
      if (n.lastHeard != null) l.lastHeard(ago(context, n.lastHeard!)),
      if (pathSummary(context, n.path) case final p when p.isNotEmpty) p,
      if (!n.canMessage) l.nodeCannotMessage,
      if (appOnly) l.nodeAppOnly,
    ].join(' · ');
    return ListTile(
      leading: Icon(
        nodeKindIcon(n.kind),
        semanticLabel: nodeKindName(context, n.kind),
      ),
      title: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(n.displayName),
          if (n.shortName.isNotEmpty) Text('(${n.shortName})'),
          ProtocolBadge(n.protocol),
          TrustBadge(trust),
          if (n.isFavorite)
            Icon(
              Icons.star,
              size: 16,
              semanticLabel: context.l10n.nodeFavorite,
            ),
          SignalBars(signalBars(n.path)),
        ],
      ),
      subtitle: Text(details),
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
