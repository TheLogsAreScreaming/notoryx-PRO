import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_controller.dart';
import '../app/support_report.dart';
import 'common.dart';

/// Builds the support report for [app], with every radio and node name the
/// app knows removed.
Future<String> buildSupportReport(
  AppController app, {
  required String appVersion,
  required String locale,
  String? system,
}) async {
  final private = <String>{};
  final radios = <RadioSummary>[];
  for (final c in app.connections) {
    final r = c.radio;
    private
      ..add(c.target.label)
      ..add(c.target.address);
    if (r != null) {
      private
        ..add(r.name)
        ..add(r.id.toString())
        ..add(r.self.toString());
      for (final n in await app.store.nodes(r.id)) {
        private
          ..add(n.name)
          ..add(n.key.toString());
      }
    }
    radios.add(
      RadioSummary(
        protocol: c.target.protocol.label,
        transport: c.target.kind.label,
        status: c.status.phase.name,
        firmware: r?.firmware ?? '',
        model: r?.model ?? '',
      ),
    );
  }
  return supportReport(
    appVersion: appVersion,
    system:
        system ??
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    locale: locale,
    radios: radios,
    log: app.log.entries,
    private: private,
  );
}

/// Shows the report so the person can read every line before sharing it.
Future<void> showSupportReport(
  BuildContext context,
  AppController app,
  String appVersion,
) async {
  final l = context.l10n;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final report = await buildSupportReport(
    app,
    appVersion: appVersion,
    locale: locale,
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.supportTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.supportHelp),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                key: const Key('support-text'),
                child: SelectableText(
                  report,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.supportClose),
        ),
        TextButton(
          key: const Key('support-copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(l.supportCopied)));
            }
          },
          child: Text(l.supportCopy),
        ),
        FilledButton(
          key: const Key('support-share'),
          onPressed: () => _share(context, report),
          child: Text(l.supportShare),
        ),
      ],
    ),
  );
}

Future<void> _share(BuildContext context, String report) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final dir = Directory('${(await getTemporaryDirectory()).path}/support');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 19);
  final file = File(
    '${dir.path}/notoryx-pro-support-${stamp.replaceAll(':', '')}.txt',
  )..writeAsStringSync(report);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
  );
}
