import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_lock.dart';
import '../store/database_vault.dart';
import 'common.dart';
import 'list_insets.dart';

/// One page that says what can leave this phone, and whether it's on.
///
/// Read-only: each row names where to change it. Everything is worked out
/// from the app's own state, so the page can't drift from what the app
/// actually does.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.app, this.vault});

  final AppController app;

  /// Null where saved messages can't be encrypted (tests, some desktops).
  final DatabaseVault? vault;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.privacyTitle)),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          app.coverage,
          app.feeds,
          app.bridge,
          app.sentinel,
          app.automations,
        ]),
        builder: (context, _) => StreamBuilder<String?>(
          stream: app.store.watchPreference(LockSettings.prefName),
          builder: (context, lockSnap) {
            final lockOn = LockSettings.decode(lockSnap.data).on;
            final feeds = app.feeds.feeds.length;
            final bridges = app.bridge.links.length;
            final encrypted = vault?.encrypted;
            return ListView(
              padding: withBottomInset(context, EdgeInsets.zero),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(l.privacyIntro),
                ),
                _Header(l.privacyLeavesHeader),
                _Row(
                  key: const Key('privacy-coverage'),
                  icon: Icons.hexagon_outlined,
                  title: l.privacyCoverage,
                  on: app.coverage.sharing,
                  detail: app.coverage.sharing
                      ? l.privacyCoverageOn
                      : l.privacyCoverageOff,
                ),
                _Row(
                  key: const Key('privacy-feeds'),
                  icon: Icons.rss_feed,
                  title: l.privacyFeeds,
                  on: feeds > 0,
                  state: feeds > 0 ? '$feeds' : null,
                  detail: l.privacyFeedsDetail,
                ),
                _Row(
                  key: const Key('privacy-bridge'),
                  icon: Icons.compare_arrows,
                  title: l.privacyBridge,
                  on: bridges > 0,
                  state: bridges > 0 ? '$bridges' : null,
                  detail: l.privacyBridgeDetail,
                ),
                _Row(
                  key: const Key('privacy-moderation'),
                  icon: Icons.shield_outlined,
                  title: l.privacyModeration,
                  on: app.sentinel.enabled,
                  detail: l.privacyModerationDetail,
                ),
                _Row(
                  key: const Key('privacy-webhooks'),
                  icon: Icons.webhook,
                  title: l.privacyWebhooks,
                  on: app.automations.settings.webhooks,
                  detail: l.privacyWebhooksDetail,
                ),
                _Row(
                  key: const Key('privacy-tiles'),
                  icon: Icons.map_outlined,
                  title: l.privacyTiles,
                  state: l.privacyAlways,
                  detail: l.privacyTilesDetail,
                ),
                _Header(l.privacyPhoneHeader),
                _Row(
                  key: const Key('privacy-encryption'),
                  icon: Icons.lock_outline,
                  title: l.encryptTitle,
                  on: encrypted ?? false,
                  state: encrypted == null ? l.privacyNotHere : null,
                  detail: l.privacyEncryptionDetail,
                ),
                _Row(
                  key: const Key('privacy-lock'),
                  icon: Icons.fingerprint,
                  title: l.lockTitle,
                  on: lockOn,
                  detail: l.privacyLockDetail,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.privacyFooter,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

/// A feature, whether it's on (said in words, not only by colour), and what
/// it means for your data.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.on = false,
    this.state,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool on;

  /// Replaces "On" / "Off" when set.
  final String? state;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = Theme.of(context).colorScheme;
    final label = state ?? (on ? l.privacyOn : l.privacyOff);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      isThreeLine: true,
      trailing: Text(
        label,
        style: TextStyle(
          color: on ? s.primary : s.onSurfaceVariant,
          fontWeight: on ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
