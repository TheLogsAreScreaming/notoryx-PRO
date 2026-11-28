import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/radio_connection.dart';
import 'common.dart';

final _forgeUrl = Uri.parse('https://meshmayhem.org/forge/');

/// Tells the user what firmware their radio runs and how to update it.
void showFirmwareUpdateSheet(BuildContext context, MeshCoreConnection c) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => FirmwareUpdateSheet(connection: c),
  );
}

class FirmwareUpdateSheet extends StatelessWidget {
  const FirmwareUpdateSheet({super.key, required this.connection});

  final MeshCoreConnection connection;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final radio = connection.radio;
    final version = radio?.firmware.isNotEmpty == true ? radio!.firmware : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.fwUpdateTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_outlined),
              title: Text(
                l.fwUpdateCurrentVersion(version ?? l.fwUpdateNoVersion),
              ),
            ),
            const Divider(height: 24),
            Text(l.fwUpdateHint),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(l.fwUpdateOpenForge),
              onPressed: () => launchUrl(_forgeUrl),
            ),
          ],
        ),
      ),
    );
  }
}
