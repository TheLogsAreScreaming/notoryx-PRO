import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app/radio_connection.dart';
import '../app/team_pack.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'restore_sheet.dart' show pickTextFile;
import 'verify_screen.dart' show openScanner;

/// Longest code that scans reliably on a phone screen.
const maxQrChars = 1200;

/// Shares this radio's setup with a team, or applies someone else's.
class TeamPackScreen extends StatefulWidget {
  const TeamPackScreen({
    super.key,
    required this.connection,
    required this.store,
    this.scan,
    this.pick,
  });

  final RadioConnection connection;
  final MeshStore store;

  /// Replaceable in tests.
  final Future<String?> Function(BuildContext context)? scan;
  final Future<String?> Function()? pick;

  @override
  State<TeamPackScreen> createState() => _TeamPackScreenState();
}

class _TeamPackScreenState extends State<TeamPackScreen> {
  final _name = TextEditingController();
  bool _channels = true;
  bool _radio = true;
  bool _places = true;
  TeamPack? _built;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _say(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _build() async {
    final l = context.l10n;
    try {
      final pack = await buildTeamPack(
        widget.connection,
        widget.store,
        name: _name.text.trim(),
        includeChannels: _channels,
        includeRadio: _radio,
        includePlaces: _places,
      );
      if (mounted) setState(() => _built = pack);
    } on Object catch (e) {
      if (mounted) _say(l.settingsSaveFailed(RadioConnection.describeError(e)));
    }
  }

  Future<void> _shareFile(TeamPack pack) async {
    final temp = await getTemporaryDirectory();
    final file = File('${temp.path}/notoryx-pro-team.json');
    await file.writeAsString(pack.toFile(), flush: true);
    if (!mounted) return;
    final box = context.findRenderObject();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: box is RenderBox && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      ),
    );
  }

  Future<void> _open(Future<String?> Function() get) async {
    final l = context.l10n;
    try {
      final text = await get();
      if (text == null || !mounted) return;
      final pack = TeamPack.parse(text);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _ImportSheet(
          pack: pack,
          connection: widget.connection,
          store: widget.store,
        ),
      );
    } on NotATeamPack catch (e) {
      if (mounted) _say(e.tooNew ? l.teamTooNew : l.teamNotPack);
    } on Object catch (e) {
      if (mounted) _say(l.exportFailed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final built = _built;
    final code = built?.toCode();
    return Scaffold(
      appBar: AppBar(title: Text(l.teamTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.teamApplyHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(l.teamScan),
            onTap: () => _open(() => (widget.scan ?? openScanner)(context)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l.teamOpenFile),
            onTap: () =>
                _open(widget.pick ?? () => pickTextFile(const ['json'])),
          ),
          const Divider(),
          Text(
            l.teamShareHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextField(
            key: const Key('team-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l.teamName),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.teamChannels),
            value: _channels,
            onChanged: (v) => setState(() => _channels = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.teamRadio),
            value: _radio,
            onChanged: (v) => setState(() => _radio = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.teamPlaces),
            value: _places,
            onChanged: (v) => setState(() => _places = v),
          ),
          Text(l.teamSecretWarning),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('team-build'),
            onPressed: _build,
            child: Text(l.teamBuild),
          ),
          if (built != null && code != null) ...[
            const SizedBox(height: 12),
            if (code.length <= maxQrChars)
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: code,
                    size: 280,
                    semanticsLabel: l.teamTitle,
                  ),
                ),
              )
            else
              Text(l.teamTooBigForCode),
            TextButton.icon(
              icon: const Icon(Icons.ios_share),
              label: Text(l.teamShareFile),
              onPressed: () => _shareFile(built),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({
    required this.pack,
    required this.connection,
    required this.store,
  });

  final TeamPack pack;
  final RadioConnection connection;
  final MeshStore store;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  late final bool _same = widget.pack.protocol == widget.connection.protocol;
  late bool _channels = _same && widget.pack.channels.isNotEmpty;

  /// Off until asked for: changing these can cut the radio off its mesh.
  bool _radio = false;
  late bool _places = widget.pack.places.isNotEmpty;
  bool _busy = false;

  String _radioText(BuildContext context) {
    final r = widget.pack.radio!;
    return r.entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }

  Future<void> _apply() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (_radio) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.teamRadioConfirmTitle),
          content: Text(l.teamRadioConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.radiosCancel),
            ),
            FilledButton(
              key: const Key('team-radio-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.teamApply),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final r = await applyTeamPack(
        widget.connection,
        widget.store,
        widget.pack,
        channels: _channels,
        radio: _radio,
        places: _places,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.teamApplied(r.channels, r.channelsFull, r.places)),
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.settingsSaveFailed(RadioConnection.describeError(e))),
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = widget.pack;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.name.isEmpty ? l.teamTitle : p.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Row(children: [ProtocolBadge(p.protocol)]),
            if (!_same) Text(l.teamOtherMesh),
            if (_same && p.channels.isNotEmpty)
              SwitchListTile(
                key: const Key('team-apply-channels'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.teamChannels),
                subtitle: Text(p.channels.map((c) => c.name).join(', ')),
                value: _channels,
                onChanged: (v) => setState(() => _channels = v),
              ),
            if (_same && p.radio != null)
              SwitchListTile(
                key: const Key('team-apply-radio'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.teamRadio),
                subtitle: Text(_radioText(context)),
                value: _radio,
                onChanged: (v) => setState(() => _radio = v),
              ),
            if (p.places.isNotEmpty)
              SwitchListTile(
                key: const Key('team-apply-places'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.teamPlaces),
                subtitle: Text(l.teamPlacesCount(p.places.length)),
                value: _places,
                onChanged: (v) => setState(() => _places = v),
              ),
            FilledButton(
              key: const Key('team-apply'),
              onPressed: _busy || !(_channels || _radio || _places)
                  ? null
                  : _apply,
              child: Text(l.teamApply),
            ),
          ],
        ),
      ),
    );
  }
}
