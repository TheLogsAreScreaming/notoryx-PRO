import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_lock.dart';
import '../store/database_vault.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'encryption_tile.dart';

/// Covers the app while locked.
///
/// Only the screen is covered. Radios, a running distress beacon, scheduled
/// messages and notifications all carry on underneath.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.store,
    required this.auth,
    required this.child,
    this.startLocked = false,
    this.now,
  });

  final MeshStore store;
  final DeviceAuth auth;
  final Widget child;
  final bool startLocked;
  final DateTime Function()? now;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late bool _locked = widget.startLocked;
  LockSettings _settings = const LockSettings();
  bool _asking = false;
  DateTime? _left;
  StreamSubscription<String?>? _prefs;
  late final AppLifecycleListener _lifecycle;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _prefs = widget.store
        .watchPreference(LockSettings.prefName)
        .listen((v) => _settings = LockSettings.decode(v));
    _lifecycle = AppLifecycleListener(onHide: _hidden, onShow: _shown);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_prefs?.cancel());
    super.dispose();
  }

  void _hidden() {
    // The system's own prompt hides the app too; that isn't leaving.
    if (!_asking) _left ??= _now;
  }

  void _shown() {
    final left = _left;
    _left = null;
    if (!_settings.on || _locked || left == null) return;
    if (_now.difference(left).inSeconds >= _settings.graceSeconds) {
      setState(() => _locked = true);
      unawaited(_ask());
    }
  }

  Future<void> _ask() async {
    if (_asking || !mounted) return;
    _asking = true;
    final reason = context.l10n.lockReason;
    final result = await widget.auth.unlock(reason);
    _asking = false;
    if (!mounted) return;
    // With no screen lock left on the phone, staying locked would shut the
    // person out for good.
    if (result != UnlockResult.failed) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Stack(
      children: [
        ExcludeSemantics(excluding: _locked, child: widget.child),
        if (_locked)
          Positioned.fill(
            child: Material(
              key: const Key('lock-cover'),
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(l.lockLocked, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('lock-unlock'),
                        onPressed: _ask,
                        child: Text(l.lockUnlock),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Turns the lock on or off, after checking it's really the owner.
class LockSettingsScreen extends StatelessWidget {
  const LockSettingsScreen({
    super.key,
    required this.store,
    required this.auth,
    this.vault,
  });

  final MeshStore store;
  final DeviceAuth auth;
  final DatabaseVault? vault;

  Future<void> _toggle(BuildContext context, LockSettings s, bool on) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (!await auth.available()) {
      messenger.showSnackBar(SnackBar(content: Text(l.lockUnavailable)));
      return;
    }
    if (await auth.unlock(l.lockReason) != UnlockResult.unlocked) return;
    await LockSettings(on: on, graceSeconds: s.graceSeconds).save(store);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.lockTitle)),
      body: StreamBuilder<String?>(
        stream: store.watchPreference(LockSettings.prefName),
        builder: (context, snap) {
          final s = LockSettings.decode(snap.data);
          return ListView(
            children: [
              SwitchListTile(
                key: const Key('lock-on'),
                title: Text(l.lockOn),
                subtitle: Text(l.lockHelp),
                value: s.on,
                onChanged: (v) => _toggle(context, s, v),
              ),
              if (s.on)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final (secs, label) in [
                        (0, l.lockAtOnce),
                        (60, l.lockAfter1),
                        (300, l.lockAfter5),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: s.graceSeconds == secs,
                          onSelected: (_) => LockSettings(
                            on: true,
                            graceSeconds: secs,
                          ).save(store),
                        ),
                    ],
                  ),
                ),
              if (vault case final v?) ...[
                const Divider(),
                EncryptionTile(vault: v),
              ],
            ],
          );
        },
      ),
    );
  }
}
