import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/message_export.dart';
import '../mesh/model.dart';
import '../store/mesh_store.dart';
import 'common.dart';

enum _Format { csv, json }

/// Asks for a format, then shares messages as a file: those in [only], or
/// every message when it is null.
Future<void> showExportSheet(
  BuildContext context, {
  required MeshStore store,
  Conversation? only,
}) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final origin = _originOf(context);
  final format = await showModalBottomSheet<_Format>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l.exportTitle), subtitle: Text(l.exportHelp)),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(l.exportCsv),
              onTap: () => Navigator.pop(context, _Format.csv),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: Text(l.exportJson),
              onTap: () => Navigator.pop(context, _Format.json),
            ),
          ],
        ),
      ),
    ),
  );
  if (format == null) return;
  try {
    final messages = await store.allMessages(only: only);
    if (messages.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.exportNothing)));
      return;
    }
    final titles = <String, String>{};
    for (final s in messages) {
      final c = s.message.conversation;
      titles[c.key] ??= await store.conversationTitle(c);
    }
    final now = DateTime.now();
    final file = await _write(
      format == _Format.csv
          ? messagesToCsv(messages, titles)
          : messagesToJson(messages, titles, exportedAt: now),
      format,
      now,
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.exportFailed('$e'))));
  }
}

/// Writes to a folder of its own, cleared each time. The file can't be
/// removed right after sharing: the receiving app may still be reading it.
Future<File> _write(String content, _Format format, DateTime now) async {
  final temp = await getTemporaryDirectory();
  final dir = Directory('${temp.path}/exports');
  if (dir.existsSync()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final stamp = now.toIso8601String().substring(0, 10);
  final file = File('${dir.path}/notoryx-pro-messages-$stamp.${format.name}');
  return file.writeAsString(content, flush: true);
}

/// Where the share popup points on iPad and Mac.
Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
}
