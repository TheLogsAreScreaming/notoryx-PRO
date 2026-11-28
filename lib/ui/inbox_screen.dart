import 'package:flutter/material.dart' hide Radio;

import '../app/app_controller.dart';
import '../mesh/model.dart';
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'node_avatar.dart';
import 'conversation_screen.dart';
import 'mute_menu.dart';

/// Every channel and direct conversation, on both meshes, in one list,
/// sorted by the time of the most recent message.
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
              builder: (context, nodeSnap) => StreamBuilder<Map<String, int>>(
                stream: store.watchUnread(),
                builder: (context, unreadSnap) =>
                    StreamBuilder<Map<String, DateTime>>(
                      stream: store.watchMutes(),
                      builder: (context, muteSnap) =>
                          StreamBuilder<List<Radio>>(
                            stream: store.watchRadios(),
                            builder: (context, radioSnap) => _InboxList(
                              app: app,
                              radios: radioSnap.data ?? const [],
                              channels: channelSnap.data ?? const [],
                              summaries: convSnap.data ?? const [],
                              nodes: nodeSnap.data ?? const [],
                              unread: unreadSnap.data ?? const {},
                              mutes: muteSnap.data ?? const {},
                            ),
                          ),
                    ),
              ),
            ),
          ),
    );
  }
}

/// A single entry in the unified conversation list.
class _Entry {
  _Entry({
    required this.conversation,
    required this.title,
    required this.icon,
    required this.last,
    required this.unread,
    required this.muted,
    this.via,
  });

  final Conversation conversation;
  final String title;
  final IconData icon;
  final StoredMessage? last;
  final int unread;
  final bool muted;
  final String? via;

  /// Database row ID of the last message; null = no messages yet, sorted last.
  int get _sortKey => last?.id ?? -1;
}

class _InboxList extends StatefulWidget {
  const _InboxList({
    required this.app,
    required this.channels,
    required this.summaries,
    required this.nodes,
    required this.unread,
    required this.mutes,
    this.radios = const [],
  });

  final List<Radio> radios;
  final AppController app;
  final List<Channel> channels;
  final List<ConversationSummary> summaries;
  final List<Node> nodes;
  final Map<String, int> unread;
  final Map<String, DateTime> mutes;

  @override
  State<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<_InboxList> {
  final _scroll = ScrollController();
  /// True once we have scrolled to the first unread on initial load.
  bool _initialScrollDone = false;
  /// Keys for each row, so we can scroll to one.
  final _keys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Builds the unified sorted entry list from current widget data.
  List<_Entry> _entries() {
    final now = DateTime.now();
    final latest = {
      for (final s in widget.summaries) s.conversation: s.last,
    };
    final names = {
      for (final n in widget.nodes) '${n.radioId}|${n.key}': n,
    };
    final perMesh = <RadioProtocol, int>{};
    for (final r in widget.radios) {
      perMesh[r.protocol] = (perMesh[r.protocol] ?? 0) + 1;
    }
    final radioNames = {for (final r in widget.radios) r.id: r.name};
    String? via(RadioId id) =>
        (perMesh[id.protocol] ?? 0) > 1 ? radioNames[id] : null;

    final entries = <_Entry>[];

    for (final c in widget.channels) {
      final conv = ChannelConversation(c.radioId, c.index);
      entries.add(
        _Entry(
          conversation: conv,
          title: c.name,
          icon: c.isPrimary ? Icons.public : Icons.tag,
          last: latest[conv],
          unread: widget.unread[conv.key] ?? 0,
          muted: mutedAt(widget.mutes[conv.key], now),
          via: via(c.radioId),
        ),
      );
    }

    for (final s in widget.summaries) {
      if (s.conversation is! DirectConversation) continue;
      final c = s.conversation as DirectConversation;
      final title =
          names['${c.radioId}|${c.node}']?.displayName ?? c.node.short;
      entries.add(
        _Entry(
          conversation: c,
          title: title,
          icon: Icons.person_outline,
          last: s.last,
          unread: widget.unread[c.key] ?? 0,
          muted: mutedAt(widget.mutes[c.key], now),
          via: via(c.radioId),
        ),
      );
    }

    // Most-recent-first; conversations with no messages go last.
    entries.sort((a, b) => b._sortKey.compareTo(a._sortKey));
    return entries;
  }

  void _scrollToFirstUnread(List<_Entry> entries) {
    if (_initialScrollDone) return;
    _initialScrollDone = true;
    final firstUnread = entries.indexWhere((e) => e.unread > 0);
    if (firstUnread <= 0) return;
    // Scroll after the first frame so layout is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _keys[entries[firstUnread].conversation.key];
      if (key?.currentContext case final ctx?) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entries = _entries();
    if (entries.isEmpty) {
      return EmptyState(l.inboxEmpty);
    }
    _scrollToFirstUnread(entries);
    // Ensure a GlobalKey exists for every entry.
    for (final e in entries) {
      _keys.putIfAbsent(e.conversation.key, GlobalKey.new);
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return _ConversationTile(
          key: _keys[e.conversation.key],
          app: widget.app,
          conversation: e.conversation,
          title: e.title,
          icon: e.icon,
          last: e.last,
          via: e.via,
          unread: e.unread,
          muted: e.muted,
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    super.key,
    required this.app,
    required this.conversation,
    required this.title,
    required this.icon,
    required this.last,
    this.unread = 0,
    this.muted = false,
    this.via,
  });

  /// Which radio, when one mesh has several.
  final String? via;
  final int unread;
  final bool muted;

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
    // Large text needs the row's full width, so the time joins the preview.
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final bold = unread > 0
        ? const TextStyle(fontWeight: FontWeight.bold)
        : null;
    return ListTile(
      leading: switch (conversation) {
        DirectConversation(:final node) => NodeAvatar(
          app: app,
          nodeKey: node.toString(),
          icon: icon,
        ),
        _ => Icon(icon),
      },
      title: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: bold),
          ProtocolBadge(conversation.radioId.protocol),
          if (via case final name?)
            Text(
              l.inboxVia(name),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (muted)
            Icon(
              Icons.notifications_off_outlined,
              size: 16,
              semanticLabel: l.mutedLabel,
            ),
          if (unread > 0)
            Semantics(
              label: l.unreadCount(unread),
              child: ExcludeSemantics(
                child: Badge(
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  backgroundColor: muted
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        m != null && largeText
            ? '${ago(context, m.receivedAt)} · $preview'
            : preview,
        maxLines: largeText ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: bold,
      ),
      trailing: m == null || largeText
          ? null
          : Text(ago(context, m.receivedAt)),
      onLongPress: () => showConversationOptions(
        context,
        store: app.store,
        conversation: conversation,
        title: title,
        muted: muted,
      ),
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
