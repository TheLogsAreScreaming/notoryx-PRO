import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/model.dart';
import '../mesh/topology.dart';
import 'common.dart';
import 'conversation_screen.dart';

/// Lists the relay nodes that forward your outgoing messages, busiest first.
class WhoRepeatsScreen extends StatelessWidget {
  const WhoRepeatsScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.whoRepeatsTitle)),
      body: ListenableBuilder(
        listenable: app.hopNaming,
        builder: (context, _) => StreamBuilder<List<Node>>(
          stream: app.store.watchAllNodes(),
          builder: (context, snap) {
            final nodes = snap.data ?? const [];
            final topo = Topology.build(
              nodes,
              resolve: (n, known) => app.hopNaming.resolve(
                n,
                known,
                from: app.connections
                    .where((c) => c.radio?.id == n.radioId)
                    .map((c) => c.radio?.position)
                    .nonNulls
                    .firstOrNull,
              ),
            );
            final relays = [
              for (final n in topo.nodes.values)
                if (n.id != topologyYou && n.routes > 0) n,
            ]..sort((a, b) => b.routes.compareTo(a.routes));

            if (relays.isEmpty) {
              return Center(child: Text(l.whoRepeatsEmpty));
            }
            return ListView.builder(
              itemCount: relays.length,
              itemBuilder: (context, i) {
                final r = relays[i];
                final node = r.node;
                return ListTile(
                  leading: r.unknown
                      ? const Icon(Icons.device_unknown_outlined)
                      : Icon(
                          node?.kind == NodeKind.relay
                              ? Icons.settings_input_antenna
                              : Icons.person_outline,
                        ),
                  title: Text(r.label.isNotEmpty ? r.label : r.id),
                  subtitle: Text(
                    [
                      l.topologyRoutes(r.routes),
                      l.topologyHops(r.ring - 1),
                    ].join(' · '),
                  ),
                  trailing: node != null && node.canMessage
                      ? IconButton(
                          tooltip: l.topologyMessage,
                          icon: const Icon(Icons.chat_bubble_outline),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ConversationScreen(
                                app: app,
                                conversation: DirectConversation(
                                  node.radioId,
                                  node.key,
                                ),
                                title: node.displayName,
                              ),
                            ),
                          ),
                        )
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
