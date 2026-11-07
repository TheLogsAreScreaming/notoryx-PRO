import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/model.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'conversation_screen.dart';

/// Every channel and direct conversation, on both meshes, in one list.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final store = app.store;
    return StreamBuilder<List<Channel>>(
      stream: store.watchAllChannels(),
      builder: (context, channelSnap) =>
          StreamBuilder<List<ConversationSummary>>(
            stream: store.watchConversations(),
            builder: (context, convSnap) => StreamBuilder<List<Node>>(
              stream: store.watchAllNodes(),
              builder: (context, nodeSnap) => _InboxList(
                app: app,
                channels: channelSnap.data ?? const [],
                summaries: convSnap.data ?? const [],
                nodes: nodeSnap.data ?? const [],
              ),
            ),
          ),
    );
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.app,
    required this.channels,
    required this.summaries,
    required this.nodes,
  });

  final AppController app;
  final List<Channel> channels;
  final List<ConversationSummary> summaries;
  final List<Node> nodes;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final latest = {for (final s in summaries) s.conversation: s.last};
    final names = {for (final n in nodes) '${n.radioId}|${n.key}': n};
    final direct = summaries
        .where((s) => s.conversation is DirectConversation)
        .toList();
    if (channels.isEmpty && direct.isEmpty) {
      return EmptyState(l.inboxEmpty);
    }
    final channelRows = [...channels]
      ..sort((a, b) {
        final ia = latest[ChannelConversation(a.radioId, a.index)]?.id ?? -1;
        final ib = latest[ChannelConversation(b.radioId, b.index)]?.id ?? -1;
        return ib.compareTo(ia);
      });
    return ListView(
      children: [
        if (channelRows.isNotEmpty) _Header(l.inboxChannelsHeader),
        for (final c in channelRows)
          _ConversationTile(
            app: app,
            conversation: ChannelConversation(c.radioId, c.index),
            title: c.name,
            icon: c.isPrimary ? Icons.public : Icons.tag,
            last: latest[ChannelConversation(c.radioId, c.index)],
          ),
        if (direct.isNotEmpty) _Header(l.inboxDirectHeader),
        for (final s in direct)
          _ConversationTile(
            app: app,
            conversation: s.conversation,
            title: _directTitle(s.conversation as DirectConversation, names),
            icon: Icons.person_outline,
            last: s.last,
          ),
      ],
    );
  }

  static String _directTitle(DirectConversation c, Map<String, Node> names) =>
      names['${c.radioId}|${c.node}']?.displayName ?? c.node.short;
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.app,
    required this.conversation,
    required this.title,
    required this.icon,
    required this.last,
  });

  final AppController app;
  final Conversation conversation;
  final String title;
  final IconData icon;
  final StoredMessage? last;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = last?.message;
    final preview = m == null
        ? l.inboxNoMessages
        : m.outgoing
        ? l.youPrefix(m.text)
        : (m.senderName != null ? '${m.senderName}: ${m.text}' : m.text);
    return ListTile(
      leading: Icon(icon),
      title: Row(
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          ProtocolBadge(conversation.radioId.protocol),
        ],
      ),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: m == null ? null : Text(ago(context, m.receivedAt)),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(
            app: app,
            conversation: conversation,
            title: title,
          ),
        ),
      ),
    );
  }
}
