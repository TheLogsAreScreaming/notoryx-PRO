import 'package:flutter/material.dart';

import '../store/database_vault.dart';
import 'common.dart';

/// Shows whether saved messages are encrypted, and asks for it.
class EncryptionTile extends StatefulWidget {
  const EncryptionTile({super.key, required this.vault});

  final DatabaseVault vault;

  @override
  State<EncryptionTile> createState() => _EncryptionTileState();
}

class _EncryptionTileState extends State<EncryptionTile> {
  Future<void> _ask() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.encryptConfirmTitle),
        content: Text(l.encryptConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            key: const Key('encrypt-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.encryptAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await widget.vault.request();
    if (!done) {
      messenger.showSnackBar(SnackBar(content: Text(l.encryptUnavailable)));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = widget.vault;
    final failure = v.lastFailure;
    return ListTile(
      key: const Key('encrypt-tile'),
      leading: const Icon(Icons.enhanced_encryption_outlined),
      title: Text(l.encryptTitle),
      subtitle: Text(
        v.encrypted
            ? l.encryptOn
            : v.requested
            ? l.encryptPending
            : failure != null
            ? l.encryptFailed(failure)
            : l.encryptOff,
      ),
      onTap: v.encrypted || v.requested ? null : _ask,
    );
  }
}

/// Shown instead of the app when the database's key is gone.
class KeyMissingApp extends StatefulWidget {
  const KeyMissingApp({super.key, required this.vault});

  final DatabaseVault vault;

  @override
  State<KeyMissingApp> createState() => _KeyMissingAppState();
}

class _KeyMissingAppState extends State<KeyMissingApp> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: L10nDelegates.all,
    supportedLocales: L10nDelegates.locales,
    home: Builder(
      builder: (context) {
        final l = context.l10n;
        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.key_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _done ? l.keyMissingDone : l.keyMissingBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (!_done)
                    FilledButton(
                      key: const Key('key-missing-fresh'),
                      onPressed: () async {
                        await widget.vault.setAside();
                        if (mounted) setState(() => _done = true);
                      },
                      child: Text(l.keyMissingFresh),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
