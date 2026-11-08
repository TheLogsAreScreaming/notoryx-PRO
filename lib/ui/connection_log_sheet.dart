import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/radio.dart';
import 'common.dart';

/// What the app tried while connecting, to read or copy into a bug report.
/// The log holds no message contents.
Future<void> showConnectionLog(BuildContext context, ConnectionLog log) {
  final l = context.l10n;
  final entries = log.entries.reversed.toList();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.logTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(l.verifyCopy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: log.export()));
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
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(l.logEmpty))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(
                        entries[i].toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
