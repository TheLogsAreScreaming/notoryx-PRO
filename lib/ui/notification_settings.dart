import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/message_alerts.dart';
import 'common.dart';

/// Which messages notify, and the system permission.
class NotificationSettingsSheet extends StatelessWidget {
  const NotificationSettingsSheet({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final store = app.store;
    Widget toggle(String pref, String title) => StreamBuilder<String?>(
      stream: store.watchPreference(pref),
      builder: (context, snap) => SwitchListTile(
        key: Key(pref),
        title: Text(title),
        value: snap.data != 'off',
        onChanged: (v) => store.setPreference(pref, v ? 'on' : 'off'),
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l.notifyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            toggle(AlertPrefs.direct, l.notifyDirect),
            toggle(AlertPrefs.channels, l.notifyChannels),
            toggle(AlertPrefs.background, l.notifyBackground),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.notifyHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (app.alerts case final alerts?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(l.notifyAllow),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await alerts.notifier.requestPermission();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(ok ? l.notifyAllowed : l.notifyDenied),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
