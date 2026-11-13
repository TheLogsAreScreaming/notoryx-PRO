import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/trusted_nodes.dart';
import '../mesh/mesh.dart';
import '../radio/radio_link.dart';
import '../mesh/node_merge.dart';
import 'common.dart';
import '../app/sentinel.dart';
import 'conversation_screen.dart';
import 'sentinel_screen.dart';
import 'verify_screen.dart';

/// Every node both radios have heard, most recent first.
class NodesScreen extends StatelessWidget {
  const NodesScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TrustState>(
      stream: TrustedNodes.watch(app.store),
      builder: (context, tSnap) => StreamBuilder<Set<String>>(
        stream: app.store.watchAllRadioContacts(),
        builder: (context, cSnap) => StreamBuilder<List<Node>>(
          stream: app.store.watchAllNodes(),
          builder: (context, snap) {
            final all = snap.data ?? const <Node>[];
            final trust = tSnap.data ?? const TrustState();
            final favorites = favoriteKeys(all);
            var merged = mergeAcrossRadios(all);
            if (trust.onlyTrusted && merged.isNotEmpty) {
              merged = [
                for (final m in merged)
                  if (trust.trusts(m.node, favorites: favorites)) m,
              ];
              if (merged.isEmpty) {
                return EmptyState(
                  context.l10n.trustedEmpty,
                  icon: Icons.star_outline,
                );
              }
            }
            if (merged.isEmpty) {
              return EmptyState(
                context.l10n.nodesEmpty,
                icon: Icons.hub_outlined,
              );
            }
            final verified = trust.verifications;
            return ListView.builder(
              itemCount: merged.length,
              itemBuilder: (context, i) {
                final n = merged[i].node;
                return NodeTile(
                  app: app,
                  node: n,
                  radios: merged[i].radios,
                  trust: trustOf(n, verified[n.key]),
                  marked: trust.isMarked(n.key),
                  trusted: trust.trusts(n, favorites: favorites),
                  appOnly:
                      cSnap.hasData &&
                      n.protocol == RadioProtocol.meshcore &&
                      !cSnap.data!.contains('${n.radioId}|${n.key}'),
                );
              },
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
    this.radios = 1,
    this.marked = false,
    this.trusted = false,
  });

  /// Marked trusted in the app (the star button's state).
  final bool marked;

  /// Trusted for any reason: marked, a radio favourite, or verified.
  final bool trusted;

  final AppController app;
  final Node node;
  final TrustStatus trust;

  /// A MeshCore node the app keeps but the radio's contact list doesn't
  /// hold; it is added when messaged.
  final bool appOnly;

  /// How many of your radios hear this node.
  final int radios;

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
      if (radios > 1) l.nodeHeardBy(radios),
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
          if (app.sentinel.banFor(n.key) case final ban?) SentinelFlag(ban),
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
      trailing: IconButton(
        key: Key('trust-${n.key}'),
        tooltip: marked ? l.trustedUnmark : l.trustedMark,
        isSelected: marked,
        icon: Icon(trusted ? Icons.star_half : Icons.star_border),
        selectedIcon: const Icon(Icons.star),
        onPressed: () =>
            TrustedNodes.setMarked(app.store, n.key, trusted: !marked),
      ),
      onLongPress: () => showSentinelReportSheet(
        context,
        sentinel: app.sentinel,
        network: n.protocol,
        nodeId: sentinelNodeId(n.key),
        nodeName: n.displayName,
      ),
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
