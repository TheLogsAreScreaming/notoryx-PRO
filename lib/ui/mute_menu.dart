import 'package:flutter/material.dart';

import '../mesh/model.dart';
import '../store/mesh_store.dart';
import 'common.dart';

/// "Forever": far enough ahead that it never ends in practice.
final muteForever = DateTime.utc(9999);

/// Mute lengths offered.
enum MuteLength { hour, eightHours, week, always }

/// When a mute of [length] starting at [now] ends.
DateTime muteEnd(MuteLength length, DateTime now) => switch (length) {
  MuteLength.hour => now.add(const Duration(hours: 1)),
  MuteLength.eightHours => now.add(const Duration(hours: 8)),
  MuteLength.week => now.add(const Duration(days: 7)),
  MuteLength.always => muteForever,
};

String muteLengthName(BuildContext context, MuteLength length) {
  final l = context.l10n;
  return switch (length) {
    MuteLength.hour => l.muteHour,
    MuteLength.eightHours => l.muteEightHours,
    MuteLength.week => l.muteWeek,
    MuteLength.always => l.muteAlways,
  };
}

/// Whether a mute ending at [until] still applies at [now].
bool mutedAt(DateTime? until, DateTime now) =>
    until != null && until.isAfter(now);

/// A bell button that mutes or unmutes [conversation].
class MuteButton extends StatelessWidget {
  const MuteButton({
    super.key,
    required this.store,
    required this.conversation,
  });

  final MeshStore store;
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return StreamBuilder<Map<String, DateTime>>(
      stream: store.watchMutes(),
      builder: (context, snap) {
        final until = snap.data?[conversation.key];
        final muted = mutedAt(until, DateTime.now());
        return PopupMenuButton<MuteLength?>(
          key: const Key('mute-menu'),
          tooltip: muted ? l.muteUnmute : l.muteTitle,
          icon: Icon(
            muted
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
          ),
          onSelected: (v) => store.setMuted(
            conversation,
            v == null ? null : muteEnd(v, DateTime.now()),
          ),
          itemBuilder: (context) => [
            if (muted) PopupMenuItem<MuteLength?>(child: Text(l.muteUnmute)),
            for (final m in MuteLength.values)
              PopupMenuItem<MuteLength?>(
                value: m,
                child: Text(muteLengthName(context, m)),
              ),
          ],
        );
      },
    );
  }
}

/// Mark read and mute options for a conversation, as a bottom sheet.
Future<void> showConversationOptions(
  BuildContext context, {
  required MeshStore store,
  required Conversation conversation,
  required String title,
  required bool muted,
}) {
  final l = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined),
              title: Text(l.markRead),
              onTap: () {
                Navigator.pop(context);
                store.markRead(conversation);
              },
            ),
            if (muted)
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(l.muteUnmute),
                onTap: () {
                  Navigator.pop(context);
                  store.setMuted(conversation, null);
                },
              ),
            for (final m in MuteLength.values)
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(muteLengthName(context, m)),
                onTap: () {
                  Navigator.pop(context);
                  store.setMuted(conversation, muteEnd(m, DateTime.now()));
                },
              ),
          ],
        ),
      ),
    ),
  );
}
