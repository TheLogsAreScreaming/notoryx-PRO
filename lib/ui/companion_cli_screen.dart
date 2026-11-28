import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/radio_connection.dart';
import '../meshcore/firmware.dart';
import 'common.dart';

/// Commands that change the radio's identity or wipe its state.
/// Any command whose first token matches one of these gets a
/// confirmation dialog before it runs.
const _destructiveCommands = {'rekey', 'factory-reset', 'factory_reset'};

bool _isDestructive(String command) {
  final first = command.trim().split(RegExp(r'\s+')).first.toLowerCase();
  return _destructiveCommands.contains(first);
}

/// In-app terminal for the firmware v1.18+ Companion CLI.
///
/// Only shown when the connected radio reports protocol 14 or later
/// ([MeshCoreFeature.companionCli]).
class CompanionCliScreen extends StatefulWidget {
  const CompanionCliScreen({super.key, required this.connection});

  final MeshCoreConnection connection;

  @override
  State<CompanionCliScreen> createState() => _CompanionCliScreenState();
}

class _CompanionCliScreenState extends State<CompanionCliScreen> {
  final _lines = <_CliLine>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _busy) return;

    if (_isDestructive(cmd)) {
      final l = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.cliDestructiveTitle),
          content: Text(l.cliDestructiveBody(cmd)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.radiosCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.cliRunAnyway),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    _input.clear();
    setState(() {
      _lines.add(_CliLine.input(cmd));
      _busy = true;
    });
    _scrollToEnd();

    try {
      final reply = await widget.connection.runCli(cmd);
      if (!mounted) return;
      setState(() => _lines.add(_CliLine.output(reply)));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _lines.add(_CliLine.error(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    _scrollToEnd();
    _inputFocus.requestFocus();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  });

  void _copyAll() {
    final text = _lines.map((l) => l.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.cliCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(
        title: Text(l.cliTitle),
        actions: [
          if (_lines.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: l.cliCopyAll,
              onPressed: _copyAll,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text(
                      l.cliHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final line = _lines[i];
                      final color = switch (line.kind) {
                        _LineKind.input => cs.primary,
                        _LineKind.output => cs.onSurface,
                        _LineKind.error => cs.error,
                      };
                      final prefix = switch (line.kind) {
                        _LineKind.input => '> ',
                        _LineKind.output => '',
                        _LineKind.error => '! ',
                      };
                      return SelectableText(
                        '$prefix${line.text}',
                        style: mono?.copyWith(color: color),
                      );
                    },
                  ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              8 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    autofocus: true,
                    enabled: !_busy,
                    style: mono,
                    decoration: InputDecoration(
                      hintText: l.cliInputHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _run(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _run,
                  child: Text(l.cliRun),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _LineKind { input, output, error }

class _CliLine {
  const _CliLine._({required this.kind, required this.text});

  factory _CliLine.input(String text) =>
      _CliLine._(kind: _LineKind.input, text: text);

  factory _CliLine.output(String text) =>
      _CliLine._(kind: _LineKind.output, text: text);

  factory _CliLine.error(String text) =>
      _CliLine._(kind: _LineKind.error, text: text);

  final _LineKind kind;
  final String text;
}
