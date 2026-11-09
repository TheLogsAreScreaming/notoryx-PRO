import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/database_vault.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:sqlite3/sqlite3.dart';

class MemoryVault implements KeyVault {
  String? key;
  bool loses = false;
  @override
  Future<String?> read() async => key;
  @override
  Future<void> write(String k) async => key = loses ? null : k;
  @override
  Future<void> delete() async => key = null;
}

final ch = ChannelConversation(RadioId.meshtastic(1), 0);

Message msg(String t, int n) => Message(
  conversation: ch,
  text: t,
  outgoing: true,
  sentAt: DateTime.utc(2026, 1, 1, 0, n),
  receivedAt: DateTime.utc(2026, 1, 1, 0, n),
  delivery: const Sent(),
);

void main() {
  late Directory dir;
  late File file;
  late MemoryVault keys;
  late DatabaseVault vault;

  Future<void> seed() async {
    final s = MeshStore.open(file);
    await s.addMessage(msg('water at the hut', 1));
    await s.addMessage(msg('second', 2));
    await s.close();
  }

  Future<List<String>> texts(String? key) async {
    final s = MeshStore.open(file, key: key);
    final m = await s.messages(ch);
    await s.close();
    return m.map((x) => x.message.text).toList();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vault');
    file = File('${dir.path}/db.sqlite');
    keys = MemoryVault();
    vault = DatabaseVault(file, keys);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing changes unless asked', () async {
    await seed();
    expect(await vault.prepare(), isNull);
    expect(vault.encrypted, isFalse);
    expect(await texts(null), ['water at the hut', 'second']);
  });

  test('converts, keeps every message, and hides the text', () async {
    await seed();
    expect(await vault.request(), isTrue);
    final key = await vault.prepare();
    expect(key, isNotNull);
    expect(vault.encrypted, isTrue);
    expect(vault.requested, isFalse);
    final raw = file.readAsBytesSync();
    expect(String.fromCharCodes(raw).contains('water at the hut'), isFalse);
    expect(await texts(key), ['water at the hut', 'second']);
    expect(await vault.prepare(), key, reason: 'next launch finds the key');
  });

  test('the wrong key cannot read it', () async {
    await seed();
    await vault.request();
    await vault.prepare();
    final db = sqlite3.open(file.path);
    addTearDown(db.close);
    db.execute("PRAGMA key = 'wrong'");
    expect(() => db.select('SELECT * FROM messages'), throwsA(anything));
  });

  test('new messages after converting stay readable', () async {
    await seed();
    await vault.request();
    final key = await vault.prepare();
    final s = MeshStore.open(file, key: key);
    await s.addMessage(msg('third', 3));
    await s.close();
    expect(await texts(key), hasLength(3));
  });

  test('a device that cannot keep a key is refused up front', () async {
    keys.loses = true;
    expect(await vault.request(), isFalse);
    expect(vault.requested, isFalse);
  });

  test('if the key can\'t be saved, the original is untouched', () async {
    await seed();
    await vault.request();
    final before = file.readAsBytesSync();
    keys.loses = true;
    expect(await vault.prepare(), isNull);
    expect(file.readAsBytesSync(), before);
    expect(vault.lastFailure, isNotNull);
    expect(vault.requested, isFalse);
    expect(await texts(null), hasLength(2));
  });

  test('a damaged database stops the conversion', () async {
    file.writeAsBytesSync(List.filled(4096, 7));
    // Not plain by header, so treat it as encrypted with no key: nothing
    // is rewritten or deleted.
    final before = file.readAsBytesSync();
    await expectLater(vault.prepare(), throwsA(isA<DatabaseKeyMissing>()));
    expect(file.readAsBytesSync(), before);
  });

  test('a missing key is reported, and setting aside keeps the file', () async {
    await seed();
    await vault.request();
    await vault.prepare();
    keys.key = null;
    await expectLater(vault.prepare(), throwsA(isA<DatabaseKeyMissing>()));
    expect(file.existsSync(), isTrue);
    await vault.setAside();
    expect(file.existsSync(), isFalse);
    expect(
      dir.listSync().where((f) => f.path.contains('unreadable')),
      hasLength(1),
    );
  });

  test('a leftover half-finished copy is cleared', () async {
    await seed();
    final temp = File('${file.path}.encrypting')..writeAsStringSync('junk');
    await vault.prepare();
    expect(temp.existsSync(), isFalse);
  });
}
