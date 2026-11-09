import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';

/// Where the database key is kept.
abstract interface class KeyVault {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> delete();
}

/// [KeyVault] in the phone's Keystore or Keychain.
class SecureKeyVault implements KeyVault {
  static const _storage = FlutterSecureStorage();
  static const _name = 'database-key';

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String key) => _storage.write(key: _name, value: key);

  @override
  Future<void> delete() => _storage.delete(key: _name);
}

/// The database is encrypted but its key is gone (for example the phone's
/// keystore was reset). Nothing can read it, and nothing has been changed.
class DatabaseKeyMissing implements Exception {
  const DatabaseKeyMissing();
}

/// Encrypts the message database when asked, and finds its key on launch.
///
/// Conversion happens at startup, while nothing has the database open: a
/// copy is encrypted, reopened with the key and compared table by table,
/// and only then replaces the original. On any failure the original stays
/// exactly as it was.
class DatabaseVault {
  DatabaseVault(this.file, this.keys);

  final File file;
  final KeyVault keys;

  File get _request => File('${file.path}.encrypt-requested');
  File get _failed => File('${file.path}.encrypt-failed');
  File get _temp => File('${file.path}.encrypting');

  /// Whether the file on disk is encrypted. A plain SQLite file always
  /// starts with this header.
  static bool isEncrypted(File f) {
    if (!f.existsSync() || f.lengthSync() < 16) return false;
    final r = f.openSync();
    try {
      return utf8.decode(r.readSync(16), allowMalformed: true) !=
          'SQLite format 3\u0000';
    } finally {
      r.closeSync();
    }
  }

  /// Whether the saved messages are encrypted now.
  bool get encrypted => isEncrypted(file);

  /// Whether encryption will happen on the next launch.
  bool get requested => _request.existsSync();

  /// Why the last attempt failed, if it did.
  String? get lastFailure =>
      _failed.existsSync() ? _failed.readAsStringSync() : null;

  /// Asks for encryption on the next launch, after checking this device
  /// can really keep a key. False if it can't.
  Future<bool> request() async {
    try {
      const probe = 'notoryx-probe';
      await keys.write(probe);
      final back = await keys.read();
      await keys.delete();
      if (back != probe) return false;
    } on Object {
      return false;
    }
    if (_failed.existsSync()) _failed.deleteSync();
    await _request.writeAsString('1', flush: true);
    return true;
  }

  /// Run before opening the database. Returns its key, or null if it is
  /// plain. Throws [DatabaseKeyMissing] if it can't be opened.
  Future<String?> prepare() async {
    if (_temp.existsSync()) _temp.deleteSync();
    if (encrypted) {
      if (_request.existsSync()) _request.deleteSync();
      final key = await keys.read();
      if (key == null) throw const DatabaseKeyMissing();
      return key;
    }
    if (!_request.existsSync() || !file.existsSync()) return null;
    return _convert();
  }

  Future<String?> _convert() async {
    final r = Random.secure();
    final key = [
      for (var i = 0; i < 32; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final (source, temp) = (file.path, _temp.path);
    try {
      await keys.write(key);
      if (await keys.read() != key) throw StateError('Key was not saved');
      await Isolate.run(() => encryptCopy(source, temp, key));
      await _temp.rename(file.path);
      await _request.delete();
      return key;
    } on Object catch (e) {
      if (_temp.existsSync()) _temp.deleteSync();
      try {
        await keys.delete();
      } on Object {
        // The plain file doesn't need it either way.
      }
      await _request.delete();
      await _failed.writeAsString('$e', flush: true);
      return null;
    }
  }

  /// Moves an unreadable database aside so the app can start empty. The
  /// old file is kept, not deleted.
  Future<void> setAside() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await file.rename('${file.path}.unreadable-$stamp');
    await keys.delete();
  }
}

/// Encrypts a copy of the database at [source] into [target] and proves
/// the copy reads back the same. Throws if anything differs; [source] is
/// only ever checkpointed.
void encryptCopy(String source, String target, String key) {
  final plain = sqlite3.open(source);
  final Map<String, int> before;
  try {
    plain.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    before = _counts(plain);
  } finally {
    plain.close();
  }
  File(source).copySync(target);

  final copy = sqlite3.open(target);
  try {
    copy.execute("PRAGMA rekey = '$key'");
  } finally {
    copy.close();
  }
  if (!DatabaseVault.isEncrypted(File(target))) {
    throw StateError('The copy was not encrypted');
  }

  final check = sqlite3.open(target);
  try {
    check.execute("PRAGMA key = '$key'");
    final ok = check.select('PRAGMA integrity_check').first.values.first;
    if (ok != 'ok') throw StateError('Integrity check failed: $ok');
    final after = _counts(check);
    for (final MapEntry(key: table, value: n) in before.entries) {
      if (after[table] != n) {
        throw StateError('$table has ${after[table]} rows, expected $n');
      }
    }
  } finally {
    check.close();
  }
}

Map<String, int> _counts(Database db) => {
  for (final t in db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  ))
    t['name'] as String:
        db.select('SELECT COUNT(*) AS n FROM "${t['name']}"').first['n'] as int,
};
