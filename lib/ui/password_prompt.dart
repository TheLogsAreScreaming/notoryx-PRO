import 'package:flutter/material.dart';

import 'common.dart';

/// Asks for a backup password; with [confirm], asks twice and requires at
/// least 8 characters. Null if cancelled.
Future<String?> askPassword(
  BuildContext context, {
  required String title,
  String? help,
  bool confirm = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordDialog(title: title, help: help, confirm: confirm),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.confirm,
    this.help,
  });

  final String title;
  final String? help;
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  String? get _error {
    final l = context.l10n;
    if (!widget.confirm) return null;
    if (_a.text.length < 8) return l.passwordTooShort;
    if (_a.text != _b.text) return l.passwordMismatch;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final error = _error;
    final ok = _a.text.isNotEmpty && error == null;
    void changed(String _) => setState(() {});
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.help case final h?) Text(h),
            TextField(
              key: const Key('password-1'),
              controller: _a,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: changed,
              decoration: InputDecoration(labelText: l.passwordLabel),
            ),
            if (widget.confirm)
              TextField(
                key: const Key('password-2'),
                controller: _b,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: changed,
                decoration: InputDecoration(
                  labelText: l.passwordRepeat,
                  errorText: _a.text.isEmpty ? null : error,
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
          key: const Key('password-ok'),
          onPressed: ok ? () => Navigator.pop(context, _a.text) : null,
          child: Text(l.passwordOk),
        ),
      ],
    );
  }
}
