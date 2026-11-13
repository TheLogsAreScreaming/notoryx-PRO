import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/export_crypto.dart';
import '../app/message_import.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'password_prompt.dart';

/// Larger files are refused rather than risk running out of memory.
const maxRestoreBytes = 64 * 1024 * 1024;

/// A file that's over [maxRestoreBytes].
class RestoreFileTooBig implements Exception {
  const RestoreFileTooBig();
}

/// Asks for a file with one of [extensions] and returns its text, or null
/// if cancelled.
Future<String?> pickTextFile(List<String> extensions) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  final path = picked.firstOrNull?.path;
  if (path == null) return null;
  final file = File(path);
  if (await file.length() > maxRestoreBytes) throw const RestoreFileTooBig();
  return file.readAsString();
}

/// Asks for a JSON export and returns its text, or null if cancelled.
Future<String?> pickExportFile() => pickTextFile(const ['json']);

/// Top-level on purpose: a closure inside [restoreFromExport] would drag
/// its screen objects along, and those can't cross to another isolate.
Future<ParsedExport> _parseInBackground(String text) =>
    Isolate.run(() => parseExport(text));

/// Decrypts off the UI thread, for the same reason as parsing.
Future<String> _openInBackground(String text, String password) =>
    Isolate.run(() => decryptExport(text, password));

/// Reads an export, confirms, and adds its messages to this device.
Future<void> restoreFromExport(
  BuildContext context, {
  required MeshStore store,
  Future<String?> Function() pick = pickExportFile,
}) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));
  try {
    var text = await pick();
    if (text == null) return;
    if (isEncryptedExport(text)) {
      if (!context.mounted) return;
      final password = await askPassword(
        context,
        title: l.restorePasswordTitle,
      );
      if (password == null) return;
      text = await _openInBackground(text, password);
    }
    final parsed = await _parseInBackground(text);
    if (!context.mounted) return;
    if (parsed.messages.isEmpty) {
      say(l.restoreNothing);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.restoreTitle),
        content: Text(l.restoreConfirm(parsed.messages.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.restoreAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final added = await store.restoreMessages(parsed.messages);
    say(
      l.restoreDone(added, parsed.messages.length - added, parsed.unreadable),
    );
  } on RestoreRefused catch (e) {
    say(switch (e.problem) {
      RestoreProblem.notAnExport => l.restoreNotExport,
      RestoreProblem.tooNew => l.restoreTooNew,
    });
  } on WrongPassword {
    say(l.restoreWrongPassword);
  } on RestoreFileTooBig {
    say(l.restoreTooBig);
  } on Object catch (e) {
    say(l.restoreFailed('$e'));
  }
}
