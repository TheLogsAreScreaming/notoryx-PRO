import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/channel_bridge.dart';
import '../mesh/model.dart';
import '../radio/radio_link.dart';
import 'common.dart';

/// Lists bridges between the two meshes and turns them on and off.
class BridgeScreen extends StatefulWidget {
  const BridgeScreen({super.key, required this.app});

  final AppController app;

  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen> {
  late final Future<void> _loaded = widget.app.bridge.load();

  ChannelBridge get _bridge => widget.app.bridge;

  String _status(BuildContext context, BridgeLink link) {
    final l = context.l10n;
    if (!link.enabled) return l.bridgeOff;
    final s = _bridge.statsFor(link);
    final why = switch (s.lastHold) {
      null => null,
      BridgeHold.tooOld => l.bridgeHoldTooOld,
      BridgeHold.repeated => l.bridgeHoldRepeated,
      BridgeHold.tooFast => l.bridgeHoldTooFast,
      BridgeHold.offline => l.bridgeHoldOffline,
    };
    return [l.bridgeStatus(s.forwarded, s.held), ?why].join('\n');
  }

  Future<void> _toggle(BridgeLink link, bool on) async {
    if (on && !await _confirm(link)) return;
    await _bridge.setEnabled(link, on);
  }

  Future<bool> _confirm(BridgeLink link) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.bridgeConfirmTitle),
        content: Text(
          link.isDirect
              ? l.bridgeConfirmDirect(link.aLabel, link.bLabel)
              : l.bridgeConfirmChannels(link.aLabel, link.bLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.bridgeTurnOn),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.bridgeTitle)),
      floatingActionButton: FloatingActionButton(
        tooltip: l.bridgeAdd,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _BridgeForm(app: widget.app)),
        ),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) => ListenableBuilder(
          listenable: _bridge,
          builder: (context, _) => ListView(
            children: [
              ListTile(subtitle: Text(l.bridgeHelp)),
              if (_bridge.links.isEmpty) EmptyState(l.bridgeEmpty),
              for (final link in _bridge.links)
                ListTile(
                  leading: Icon(
                    link.isDirect ? Icons.person_outline : Icons.forum_outlined,
                  ),
                  title: Text('${link.aLabel} ↔ ${link.bLabel}'),
                  subtitle: Text(_status(context, link)),
                  isThreeLine: link.enabled,
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Switch(
                        value: link.enabled,
                        onChanged: (on) => _toggle(link, on),
                      ),
                      IconButton(
                        tooltip: l.deleteAction,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _bridge.remove(link),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _Choice = ({Conversation conversation, String label});

class _BridgeForm extends StatefulWidget {
  const _BridgeForm({required this.app});

  final AppController app;

  @override
  State<_BridgeForm> createState() => _BridgeFormState();
}

class _BridgeFormState extends State<_BridgeForm> {
  late final Future<List<_Choice>> _channels = _loadChannels();
  late final Future<List<_Choice>> _people = _loadPeople();
  bool _direct = false;
  Conversation? _meshCore;
  Conversation? _meshtastic;

  Future<List<_Choice>> _loadChannels() async {
    final store = widget.app.store;
    final primary = context.l10n.channelsPrimary;
    return [
      for (final r in await store.radios())
        for (final c in await store.channels(r.id))
          (
            conversation: ChannelConversation(r.id, c.index),
            label: c.name.isEmpty ? primary : c.name,
          ),
    ];
  }

  Future<List<_Choice>> _loadPeople() async {
    final store = widget.app.store;
    final out = <_Choice>[
      for (final r in await store.radios())
        for (final n in await store.nodes(r.id))
          if (n.canMessage && n.key != r.self)
            (
              conversation: DirectConversation(r.id, n.key),
              label: n.displayName,
            ),
    ];
    return out..sort((a, b) => a.label.compareTo(b.label));
  }

  Future<void> _save(List<_Choice> choices) async {
    final l = context.l10n;
    final a = _meshCore;
    final b = _meshtastic;
    if (a == null || b == null) return;
    String label(Conversation c) =>
        choices.firstWhere((x) => x.conversation == c).label;
    final added = await widget.app.bridge.add(
      BridgeLink(a: a, b: b, aLabel: label(a), bLabel: label(b)),
    );
    if (!mounted) return;
    if (added) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.bridgeExists)));
    }
  }

  Widget _picker(
    String label,
    RadioProtocol protocol,
    List<_Choice> choices,
    Conversation? value,
    ValueChanged<Conversation?> onChanged,
  ) {
    return DropdownButtonFormField<Conversation>(
      key: ValueKey('bridge-${protocol.name}-$_direct'),
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      initialValue: value,
      items: [
        for (final c in choices)
          if (c.conversation.radioId.protocol == protocol)
            DropdownMenuItem(
              value: c.conversation,
              child: Text(c.label, overflow: TextOverflow.ellipsis),
            ),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.bridgeAdd)),
      body: FutureBuilder<List<_Choice>>(
        future: _direct ? _people : _channels,
        builder: (context, snap) {
          final choices = snap.data;
          if (choices == null) {
            return const Center(child: CircularProgressIndicator());
          }
          bool has(RadioProtocol p) =>
              choices.any((c) => c.conversation.radioId.protocol == p);
          final ready =
              has(RadioProtocol.meshcore) && has(RadioProtocol.meshtastic);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l.bridgeChannels)),
                  ButtonSegment(value: true, label: Text(l.bridgeDirect)),
                ],
                selected: {_direct},
                onSelectionChanged: (s) => setState(() {
                  _direct = s.single;
                  _meshCore = null;
                  _meshtastic = null;
                }),
              ),
              const SizedBox(height: 16),
              if (!ready)
                Text(l.bridgeNeedBoth)
              else ...[
                _picker(
                  l.bridgeMeshCore,
                  RadioProtocol.meshcore,
                  choices,
                  _meshCore,
                  (c) => setState(() => _meshCore = c),
                ),
                const SizedBox(height: 16),
                _picker(
                  l.bridgeMeshtastic,
                  RadioProtocol.meshtastic,
                  choices,
                  _meshtastic,
                  (c) => setState(() => _meshtastic = c),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _meshCore == null || _meshtastic == null
                      ? null
                      : () => _save(choices),
                  child: Text(l.bridgeSave),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
