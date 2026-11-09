import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/model.dart';
import 'common.dart';
import 'conversation_screen.dart';

/// Picks a conversation on a connected radio, then opens it with the
/// forwarded text in the message box. The person still presses Send.
Future<void> showForwardSheet(
  BuildContext context, {
  required AppController app,
  required Message message,
  required Conversation from,
}) async {
  final l = context.l10n;
  final navigator = Navigator.of(context);
  final all = await app.store.conversations();
  final targets = <(Conversation, String)>[];
  for (final s in all) {
    final c = s.conversation;
    if (c == from || app.connectionForRadio(c.radioId) == null) continue;
    targets.add((c, await app.store.conversationTitle(c)));
  }
  if (!context.mounted) return;
  final who = message.outgoing ? null : message.senderName;
  final draft = who == null
      ? 'Fwd: ${message.text}'
      : 'Fwd $who: ${message.text}';
  final picked = await showModalBottomSheet<(Conversation, String)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l.forwardTitle)),
            if (targets.isEmpty) ListTile(title: Text(l.forwardNone)),
            for (final t in targets)
              ListTile(
                title: Text(t.$2),
                trailing: ProtocolBadge(t.$1.radioId.protocol),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ConversationScreen(
        app: app,
        conversation: picked.$1,
        title: picked.$2,
        draft: draft,
      ),
    ),
  );
}
