import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/radio_connection.dart';
import '../mesh/diagnostics.dart';
import '../mesh/identity.dart';
import '../mesh/model.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'message_path_card.dart';

/// One conversation: messages with how each arrived, and a composer.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.app,
    required this.conversation,
    required this.title,
  });

  final AppController app;
  final Conversation conversation;
  final String title;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final Stream<List<StoredMessage>> _messages = app.store.watchMessages(
    conversation,
  );
  late final Stream<List<Node>> _nodes = app.store.watchAllNodes();
  late final Stream<Map<NodeKey, Verification>> _verifications = app.store
      .watchVerifications();

  AppController get app => widget.app;
  Conversation get conversation => widget.conversation;
  String get title => widget.title;

  Future<void> _details(Message m) async {
    var hints = const <DeliveryHint>[];
    final c = conversation;
    if (m.outgoing && c is DirectConversation) {
      final recipient = await app.store.node(c.radioId, c.node);
      hints = diagnoseDelivery(m, recipient);
    }
    if (!mounted) return;
    await MessagePathCard.show(context, m, hints: hints);
  }

  /// The connected radio for this conversation, if any.
  RadioConnection? _ready() {
    final c = app.connectionFor(conversation.radioId.protocol);
    final ready =
        c != null &&
        c.radio?.id == conversation.radioId &&
        c.status.phase == SupervisorPhase.connected;
    return ready ? c : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            ProtocolBadge(conversation.radioId.protocol),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<StoredMessage>>(
              stream: _messages,
              builder: (context, snap) {
                final messages = snap.data ?? const <StoredMessage>[];
                if (messages.isEmpty) {
                  return EmptyState(
                    context.l10n.conversationEmpty,
                    icon: Icons.chat_bubble_outline,
                  );
                }
                return StreamBuilder<List<Node>>(
                  stream: _nodes,
                  builder: (context, nodeSnap) =>
                      StreamBuilder<Map<NodeKey, Verification>>(
                        stream: _verifications,
                        builder: (context, vSnap) {
                          final nodes = {
                            for (final n in nodeSnap.data ?? const <Node>[])
                              if (n.radioId == conversation.radioId) n.key: n,
                          };
                          final clashes =
                              nameClashes(nodes.values)[conversation.radioId] ??
                              const <String>{};
                          final verified = vSnap.data ?? const {};
                          return _list(messages, nodes, clashes, verified);
                        },
                      ),
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              return Composer(connection: _ready(), conversation: conversation);
            },
          ),
        ],
      ),
    );
  }

  Widget _list(
    List<StoredMessage> messages,
    Map<NodeKey, Node> nodes,
    Set<String> clashes,
    Map<NodeKey, Verification> verified,
  ) => ListView.builder(
    reverse: true,
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: messages.length,
    itemBuilder: (context, i) {
      final stored = messages[messages.length - 1 - i];
      final m = stored.message;
      final sender = m.from == null ? null : nodes[m.from];
      final label = m.senderName ?? sender?.displayName;
      final verifiedSender =
          m.authenticated &&
          sender != null &&
          trustOf(sender, verified[sender.key]) == TrustStatus.verified;
      final clash =
          !m.outgoing &&
          label != null &&
          clashes.contains(label.trim().toLowerCase());
      return ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = _ready();
          return MessageBubble(
            message: m,
            senderLabel: label,
            verifiedSender: verifiedSender,
            nameClash: clash,
            onResend: c == null ? null : () => c.resend(stored.id),
            onTap: () => _details(m),
          );
        },
      );
    },
  );
}

/// One message, with sender, time, delivery and path facts.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onResend,
    this.onTap,
    this.senderLabel,
    this.verifiedSender = false,
    this.nameClash = false,
  });

  final Message message;

  /// Who sent it, for incoming messages (name, or node name).
  final String? senderLabel;

  /// Proven by encryption to come from a node you verified.
  final bool verifiedSender;

  /// Another node on this mesh uses the same name.
  final bool nameClash;

  /// Opens details; defaults to the path card without hints.
  final VoidCallback? onTap;

  /// Sends a failed message again; null when its radio isn't connected.
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final m = message;
    final (icon, label) = deliveryLook(context, m.delivery);
    final path = pathSummary(context, m.path);
    final meta = [
      if (!m.outgoing && (senderLabel ?? m.senderName) != null)
        senderLabel ?? m.senderName!,
      ago(context, m.receivedAt),
      if (path.isNotEmpty) path,
    ].join(' · ');
    return Align(
      alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap ?? () => MessagePathCard.show(context, m),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: m.outgoing
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (verifiedSender || nameClash)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        verifiedSender ? Icons.verified : Icons.warning_amber,
                        size: 14,
                        color: verifiedSender ? scheme.primary : scheme.error,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          verifiedSender
                              ? context.l10n.trustVerifiedSender
                              : '${context.l10n.nameClash}. ${m.conversation is ChannelConversation ? context.l10n.channelNotProven : ''}',
                          style: text.labelSmall?.copyWith(
                            color: verifiedSender
                                ? scheme.primary
                                : scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(m.text),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      meta,
                      style: text.labelSmall?.copyWith(color: scheme.outline),
                    ),
                  ),
                  if (m.outgoing) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: label,
                      child: Icon(
                        icon,
                        size: 14,
                        semanticLabel: label,
                        color: m.delivery is Failed
                            ? scheme.error
                            : scheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
              if (m.delivery case Failed(:final reason)) ...[
                Text(
                  context.l10n.deliveryFailed(reason),
                  style: text.labelSmall?.copyWith(color: scheme.error),
                ),
                if (onResend != null)
                  TextButton.icon(
                    onPressed: onResend,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(context.l10n.sendAgain),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Text field with a byte counter, since radios limit bytes, not letters.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.connection,
    required this.conversation,
  });

  /// Null when the radio for this conversation isn't connected.
  final RadioConnection? connection;
  final Conversation conversation;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _bytes => utf8.encode(_controller.text).length;

  Future<void> _send() async {
    final c = widget.connection;
    final text = _controller.text.trim();
    if (c == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await c.sendText(widget.conversation, text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.connection;
    if (c == null) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l.composerOffline, textAlign: TextAlign.center),
        ),
      );
    }
    final max = c.maxTextBytes;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final used = _bytes;
            final tooLong = used > max;
            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => tooLong ? null : _send(),
                    decoration: InputDecoration(
                      hintText: l.composerHint,
                      counterText: l.composerBytes(used, max),
                      errorText: tooLong ? l.composerBytes(used, max) : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.composerSend,
                  icon: const Icon(Icons.send),
                  onPressed: tooLong || value.text.trim().isEmpty || _sending
                      ? null
                      : _send,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
