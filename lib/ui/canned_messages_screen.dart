import 'package:flutter/material.dart';

import '../app/canned_messages.dart';
import '../store/mesh_store.dart';
import 'common.dart';

/// Edit the list of quick message snippets.
class CannedMessagesScreen extends StatelessWidget {
  const CannedMessagesScreen({super.key, required this.store});

  final MeshStore store;

  Future<void> _save(CannedMessages m) =>
      store.setPreference(CannedMessages.prefName, m.encode());

  Future<void> _add(BuildContext context, CannedMessages current) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _CannedMessageDialog(),
    );
    if (text != null && text.trim().isNotEmpty) {
      await _save(current.add(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.cannedTitle)),
      body: StreamBuilder<String?>(
        stream: store.watchPreference(CannedMessages.prefName),
        builder: (context, snap) {
          final canned = CannedMessages.decode(snap.data);
          return ListView(
            children: [
              if (canned.messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.cannedEmpty,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final m in canned.messages)
                ListTile(
                  title: Text(m.text),
                  trailing: IconButton(
                    tooltip: l.cannedDelete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save(canned.remove(m.id)),
                  ),
                ),
              ListTile(
                key: const Key('canned-add'),
                leading: const Icon(Icons.add),
                title: Text(l.cannedAdd),
                onTap: () => _add(context, canned),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CannedMessageDialog extends StatefulWidget {
  const _CannedMessageDialog();

  @override
  State<_CannedMessageDialog> createState() => _CannedMessageDialogState();
}

class _CannedMessageDialogState extends State<_CannedMessageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.cannedAdd),
      content: TextField(
        key: const Key('canned-text'),
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(hintText: l.cannedHint),
        textInputAction: TextInputAction.done,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(context, text);
          },
          child: Text(l.cannedSave),
        ),
      ],
    );
  }
}

/// A bottom sheet showing quick message snippets; tapping one inserts the text.
Future<String?> showCannedMessagesSheet(
  BuildContext context, {
  required MeshStore store,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (context) => _CannedMessagesSheet(store: store),
);

class _CannedMessagesSheet extends StatelessWidget {
  const _CannedMessagesSheet({required this.store});

  final MeshStore store;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return StreamBuilder<String?>(
      stream: store.watchPreference(CannedMessages.prefName),
      builder: (context, snap) {
        final canned = CannedMessages.decode(snap.data);
        if (canned.messages.isEmpty) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.cannedEmpty),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CannedMessagesScreen(store: store),
                        ),
                      );
                    },
                    child: Text(l.cannedAdd),
                  ),
                ],
              ),
            ),
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l.cannedTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in canned.messages)
                      ListTile(
                        title: Text(m.text),
                        onTap: () => Navigator.pop(context, m.text),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
