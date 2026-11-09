import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../radio/radio_link.dart';
import 'common.dart';
import 'team_pack_screen.dart';
import 'verify_screen.dart' show openScanner;

/// A radio's channels: share, leave, create and join.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.connection, this.scan});

  final RadioConnection connection;

  /// Opens a scanner and returns what it read; replaceable in tests.
  final Future<String?> Function(BuildContext context)? scan;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  late Future<List<ChannelSlot>> _slots = widget.connection.channelSlots();

  RadioConnection get c => widget.connection;
  bool get _meshCore => c.protocol == RadioProtocol.meshcore;

  /// Longest channel name each mesh accepts, in bytes.
  int get _maxName => _meshCore ? 31 : 11;

  void _reload() {
    final next = widget.connection.channelSlots();
    setState(() {
      _slots = next;
    });
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _join(ChannelInvite invite) async {
    final l = context.l10n;
    if (invite.protocol != c.protocol) {
      _say(l.channelsWrongMesh);
      return;
    }
    try {
      await c.addChannel(invite);
      if (mounted) _say(l.channelsJoined(invite.name));
    } on ChannelsFull {
      if (mounted) _say(l.channelsFull);
    } on Object catch (e) {
      if (mounted) _say(l.settingsSaveFailed(RadioConnection.describeError(e)));
    }
    if (mounted) _reload();
  }

  Future<String?> _askName(String title, {String prefix = ''}) {
    final l = context.l10n;
    return showTextPrompt(
      context,
      title: title,
      confirm: l.channelsAdd,
      initial: prefix,
      label: l.channelsName,
      fieldKey: const Key('channel-name'),
      validate: (t) => t.isEmpty || t == '#' || utf8.encode(t).length > _maxName
          ? l.channelsNameInvalid(_maxName)
          : null,
    );
  }

  Future<void> _newPrivate() async {
    final name = await _askName(context.l10n.channelsNewPrivate);
    if (name == null) return;
    await _join(ChannelInvite.private(c.protocol, name));
  }

  Future<void> _hashtag() async {
    final name = await _askName(context.l10n.channelsHashtag, prefix: '#');
    if (name == null) return;
    await _join(ChannelInvite.hashtag(name));
  }

  Future<void> _fromText(String? text) async {
    if (text == null || !mounted) return;
    final invites = ChannelInvite.parse(text);
    if (invites.isEmpty) {
      _say(context.l10n.channelsNotALink);
      return;
    }
    for (final i in invites) {
      await _join(i);
    }
  }

  Future<void> _paste() async {
    final l = context.l10n;
    final text = await showTextPrompt(
      context,
      title: l.channelsPaste,
      confirm: l.channelsAdd,
      hint: l.channelsPasteHint,
      fieldKey: const Key('channel-link'),
    );
    await _fromText(text);
  }

  Future<void> _leave(ChannelSlot s) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.channelsLeaveConfirm(s.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.channelsLeave),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.removeChannel(s.index);
    } on Object catch (e) {
      if (mounted) _say(l.settingsSaveFailed(RadioConnection.describeError(e)));
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.channelsTitle(c.radio?.name ?? '')),
        actions: [
          IconButton(
            tooltip: l.teamTitle,
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TeamPackScreen(connection: c, store: c.store),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<ChannelSlot>>(
        future: _slots,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              l.channelsLoadFailed(RadioConnection.describeError(snap.error!)),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final s in snap.data!)
                ListTile(
                  leading: Icon(
                    s.isPrimary
                        ? Icons.public
                        : s.invite.isHashtag
                        ? Icons.tag
                        : Icons.lock_outline,
                  ),
                  title: Text(
                    s.name.isEmpty && s.isPrimary ? l.channelsPrimary : s.name,
                  ),
                  subtitle: Text(_kind(context, s)),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: l.channelsShare,
                        icon: const Icon(Icons.qr_code),
                        onPressed: () => showChannelCode(context, s.invite),
                      ),
                      if (!s.isPrimary)
                        IconButton(
                          tooltip: l.channelsLeave,
                          icon: const Icon(Icons.logout),
                          onPressed: () => _leave(s),
                        ),
                    ],
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l.channelsNewPrivate),
                onTap: _newPrivate,
              ),
              if (_meshCore)
                ListTile(
                  leading: const Icon(Icons.tag),
                  title: Text(l.channelsHashtag),
                  subtitle: Text(l.channelsHashtagHelp),
                  onTap: _hashtag,
                ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: Text(l.channelsScan),
                onTap: () async =>
                    _fromText(await (widget.scan ?? openScanner)(context)),
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: Text(l.channelsPaste),
                onTap: _paste,
              ),
            ],
          );
        },
      ),
    );
  }

  String _kind(BuildContext context, ChannelSlot s) {
    final l = context.l10n;
    final secret = hexOf(s.invite.secret);
    if (_meshCore) {
      if (secret == meshCorePublicKeyHex) return l.channelsKindPublic;
      if (s.invite.isHashtag) return l.channelsKindHashtag;
      return l.channelsKindPrivate;
    }
    return s.invite.secret.length <= 1
        ? l.channelsKindPublic
        : l.channelsKindPrivate;
  }
}

/// Shows a channel's QR code and link.
Future<void> showChannelCode(BuildContext context, ChannelInvite invite) {
  final l = context.l10n;
  final link = invite.toLink();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.channelsShareTitle(invite.name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: link,
                size: 240,
                semanticsLabel: l.channelsShareTitle(invite.name),
              ),
            ),
            const SizedBox(height: 8),
            Text(l.channelsShareHelp, textAlign: TextAlign.center),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(l.verifyCopy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.verifyCopied)));
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
