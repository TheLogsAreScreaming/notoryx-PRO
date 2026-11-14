import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../meshcore/meshcore.dart';
import 'common.dart';

/// The 64-byte key in [text]: 128 hex digits, ignoring spaces, line
/// breaks and a leading 0x. Null when it isn't one.
Uint8List? parseIdentityKey(String text) {
  var hex = text.replaceAll(RegExp(r'\s'), '').toLowerCase();
  if (hex.startsWith('0x')) hex = hex.substring(2);
  if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(hex)) return null;
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// Back up a MeshCore radio's identity key, or give it one from a backup.
class IdentityKeyScreen extends StatefulWidget {
  const IdentityKeyScreen({
    super.key,
    required this.export,
    required this.import,
  });

  final Future<Uint8List> Function() export;
  final Future<void> Function(List<int> key) import;

  @override
  State<IdentityKeyScreen> createState() => _IdentityKeyScreenState();
}

class _IdentityKeyScreenState extends State<IdentityKeyScreen> {
  final _paste = TextEditingController();
  String? _hex;
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _why(Object e) {
    final l = context.l10n;
    return switch (e) {
      MeshCoreFeatureOff() => l.identityKeyOff,
      MeshCoreTimeout() => l.identityKeyNoAnswer,
      MeshCoreException() => l.identityKeyRefused,
      _ => l.identityKeyFailed,
    };
  }

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(MaterialLocalizations.of(dialog).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(yes),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _show() async {
    final l = context.l10n;
    if (!await _confirm(
      l.identityKeyShowTitle,
      l.identityKeyShowBody,
      l.identityKeyShowYes,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final key = await widget.export();
      if (mounted) {
        setState(
          () => _hex = [
            for (final b in key) b.toRadixString(16).padLeft(2, '0'),
          ].join(),
        );
      }
    } on Object catch (e) {
      if (mounted) _say(_why(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final key = parseIdentityKey(_paste.text);
    if (key == null) return;
    final l = context.l10n;
    if (!await _confirm(
      l.identityKeyReplaceTitle,
      l.identityKeyReplaceBody,
      l.identityKeyReplace,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.import(key);
      if (!mounted) return;
      _paste.clear();
      setState(() => _hex = null);
      _say(l.identityKeyReplaced);
    } on Object catch (e) {
      if (mounted) _say(_why(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = _paste.text.trim();
    final valid = parseIdentityKey(text) != null;
    final hex = _hex;
    final heading = Theme.of(context).textTheme.titleMedium;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Scaffold(
      appBar: AppBar(title: Text(l.identityKeyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.identityKeyIntro),
          const SizedBox(height: 24),
          Text(l.identityKeyBackUp, style: heading),
          const SizedBox(height: 8),
          if (hex == null)
            FilledButton.icon(
              key: const ValueKey('key-show'),
              icon: const Icon(Icons.key),
              label: Text(l.identityKeyShow),
              onPressed: _busy ? null : _show,
            )
          else ...[
            SelectableText(hex, key: const ValueKey('key-hex'), style: mono),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(l.identityKeyCopy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: hex));
                if (mounted) _say(l.identityKeyCopied);
              },
            ),
          ],
          const SizedBox(height: 24),
          Text(l.identityKeyRestore, style: heading),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('key-paste'),
            controller: _paste,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            style: mono,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l.identityKeyPasteHint,
              errorText: text.isEmpty || valid ? null : l.identityKeyFormat,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('key-replace'),
            icon: const Icon(Icons.restore),
            label: Text(l.identityKeyReplace),
            onPressed: valid && !_busy ? _restore : null,
          ),
          const SizedBox(height: 24),
          Text(
            l.identityKeyNeverShare,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}
