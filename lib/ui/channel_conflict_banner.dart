import 'package:flutter/material.dart';

import '../app/radio_connection.dart';
import '../mesh/channel_conflicts.dart';
import 'common.dart';

/// Shown above a radio's channels when some slots no longer hold what the
/// app last saw there. Opens a sheet to choose a version per slot.
class ChannelConflictBanner extends StatelessWidget {
  const ChannelConflictBanner({
    super.key,
    required this.connection,
    required this.onChanged,
  });

  final RadioConnection connection;

  /// Called after a slot was written, so the list can reload.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final count = connection.channelConflicts.length;
        if (count == 0) return const SizedBox.shrink();
        final l = context.l10n;
        final scheme = Theme.of(context).colorScheme;
        return Card(
          key: const Key('channel-conflicts'),
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          color: scheme.errorContainer,
          child: ListTile(
            leading: Icon(Icons.sync_problem, color: scheme.onErrorContainer),
            title: Text(
              l.channelConflictBanner(count),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            trailing: TextButton(
              onPressed: () => _open(context),
              child: Text(l.channelConflictReview),
            ),
            onTap: () => _open(context),
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConflictSheet(connection: connection),
    );
    onChanged();
  }
}

class _ConflictSheet extends StatelessWidget {
  const _ConflictSheet({required this.connection});

  final RadioConnection connection;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final conflicts = connection.channelConflicts;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  l.channelConflictTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(l.channelConflictHint),
                const SizedBox(height: 12),
                if (conflicts.isEmpty) Text(l.channelConflictDone),
                for (final c in conflicts)
                  _ConflictCard(connection: connection, conflict: c),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConflictCard extends StatefulWidget {
  const _ConflictCard({required this.connection, required this.conflict});

  final RadioConnection connection;
  final ChannelConflict conflict;

  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await action();
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.settingsSaveFailed(RadioConnection.describeError(e))),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(BuildContext context, SlotCopy? slot) {
    final l = context.l10n;
    if (slot == null) return l.channelConflictEmpty;
    return '${slot.name.isEmpty ? '—' : slot.name} · '
        '${l.channelConflictKey(slot.fingerprint)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.conflict;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.channelConflictSlot(c.index),
              style: theme.textTheme.titleMedium,
            ),
            Text(
              [
                if (c.nameDiffers) l.channelConflictNameDiffers,
                if (c.secretDiffers) l.channelConflictKeyDiffers,
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('${l.channelConflictOnRadio}: ${_describe(context, c.radio)}'),
            Text('${l.channelConflictInApp}: ${_describe(context, c.app)}'),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: Key('keep-radio-${c.index}'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.connection.keepRadioChannel(c.index),
                        ),
                  child: Text(l.channelConflictKeepRadio),
                ),
                FilledButton(
                  key: Key('use-app-${c.index}'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.connection.restoreAppChannel(c.index),
                        ),
                  child: Text(l.channelConflictUseApp),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
