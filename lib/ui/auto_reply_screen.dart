import 'package:flutter/material.dart';

import '../app/auto_responder.dart';
import '../store/mesh_store.dart';
import 'common.dart';

/// Turns auto-replies on and off and edits the rules.
class AutoReplyScreen extends StatelessWidget {
  const AutoReplyScreen({super.key, required this.store});

  final MeshStore store;

  Future<void> _save(AutoSettings s) =>
      store.setPreference(AutoResponder.prefName, s.encode());

  Future<void> _add(BuildContext context, AutoSettings s) async {
    final rule = await showDialog<AutoRule>(
      context: context,
      builder: (_) => const _RuleDialog(),
    );
    if (rule != null) {
      await _save(AutoSettings(on: s.on, rules: [...s.rules, rule]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.autoTitle)),
      body: StreamBuilder<String?>(
        stream: store.watchPreference(AutoResponder.prefName),
        builder: (context, snap) {
          final s = AutoSettings.decode(snap.data);
          return ListView(
            children: [
              SwitchListTile(
                key: const Key('auto-on'),
                title: Text(l.autoOn),
                subtitle: Text(l.autoHelp),
                value: s.on,
                onChanged: (v) => _save(AutoSettings(on: v, rules: s.rules)),
              ),
              const Divider(),
              if (s.rules.isEmpty) ListTile(title: Text(l.autoEmpty)),
              for (final r in s.rules)
                ListTile(
                  title: Text(r.isAway ? l.autoAway : r.keyword),
                  subtitle: Text(
                    r.channels ? '${r.reply}\n${l.autoOnChannels}' : r.reply,
                  ),
                  trailing: IconButton(
                    tooltip: l.autoDelete(r.isAway ? l.autoAway : r.keyword),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save(
                      AutoSettings(
                        on: s.on,
                        rules: [
                          for (final x in s.rules)
                            if (x.id != r.id) x,
                        ],
                      ),
                    ),
                  ),
                ),
              ListTile(
                key: const Key('auto-add'),
                leading: const Icon(Icons.add),
                title: Text(l.autoAdd),
                onTap: () => _add(context, s),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _keyword = TextEditingController();
  final _reply = TextEditingController();
  bool _away = false;
  bool _channels = false;

  @override
  void dispose() {
    _keyword.dispose();
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ok =
        _reply.text.trim().isNotEmpty &&
        (_away || _keyword.text.trim().isNotEmpty);
    return AlertDialog(
      title: Text(l.autoAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('auto-away'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.autoAway),
              subtitle: Text(l.autoAwayHelp),
              value: _away,
              onChanged: (v) => setState(() => _away = v),
            ),
            if (!_away) ...[
              TextField(
                key: const Key('auto-keyword'),
                controller: _keyword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.autoKeyword),
              ),
              SwitchListTile(
                key: const Key('auto-channels'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.autoOnChannels),
                subtitle: Text(l.autoChannelsHelp),
                value: _channels,
                onChanged: (v) => setState(() => _channels = v),
              ),
            ],
            TextField(
              key: const Key('auto-reply'),
              controller: _reply,
              onChanged: (_) => setState(() {}),
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l.autoReply,
                helperText: l.autoReplyHelp(
                  '{hops}',
                  '{name}',
                  '{snr}',
                  '{time}',
                ),
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(
          key: const Key('auto-save'),
          onPressed: !ok
              ? null
              : () => Navigator.pop(
                  context,
                  AutoRule(
                    id: DateTime.now().microsecondsSinceEpoch,
                    keyword: _away ? AutoRule.away : _keyword.text.trim(),
                    reply: _reply.text.trim(),
                    channels: !_away && _channels,
                  ),
                ),
          child: Text(l.channelsAdd),
        ),
      ],
    );
  }
}
