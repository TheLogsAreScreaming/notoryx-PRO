import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/ignored_nodes.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

void main() {
  final a = NodeKey.meshtastic(0x0a);
  final b = NodeKey.meshtastic(0x0b);
  final c = NodeKey.meshcore('ab' * 32);

  test('decode ignores junk', () {
    expect(IgnoredNodes.decode(null), isEmpty);
    expect(IgnoredNodes.decode('nope'), isEmpty);
    expect(IgnoredNodes.decode('{"x":1}'), isEmpty);
    expect(IgnoredNodes.decode('["a", 3, "b"]'), {'a', 'b'});
  });

  test('ignoring is kept on the phone for both meshes', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    final seen = <Set<String>>[];
    final sub = IgnoredNodes.watch(store).listen(seen.add);
    addTearDown(sub.cancel);

    await IgnoredNodes.set(store, a, ignored: true);
    await IgnoredNodes.set(store, c, ignored: true);
    var now = await IgnoredNodes.read(store);
    expect(IgnoredNodes.has(now, a), isTrue);
    expect(IgnoredNodes.has(now, c), isTrue);
    expect(IgnoredNodes.has(now, b), isFalse);

    await IgnoredNodes.set(store, a, ignored: false);
    now = await IgnoredNodes.read(store);
    expect(now, {c.toString()});
    await pumpEventQueue();
    expect(seen.last, {c.toString()});
  });

  test('a radio flag adds the node unless you stopped ignoring it', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    await IgnoredNodes.set(store, a, ignored: true);
    await IgnoredNodes.set(store, a, ignored: false);
    expect(await IgnoredNodes.readCleared(store), {a.toString()});

    await IgnoredNodes.addAll(store, [a, b]);
    expect(await IgnoredNodes.read(store), {b.toString()});

    // Once the radio's flag is cleared, it may flag the node again.
    await IgnoredNodes.forgetCleared(store, a);
    await IgnoredNodes.addAll(store, [a]);
    expect(await IgnoredNodes.read(store), {a.toString(), b.toString()});

    // Ignoring again forgets the un-ignore.
    await IgnoredNodes.set(store, b, ignored: false);
    await IgnoredNodes.set(store, b, ignored: true);
    expect(await IgnoredNodes.readCleared(store), isEmpty);
  });

  group('radio admin', () {
    String hex(List<int> x) =>
        x.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ');

    test('set_ignored_node (47) and remove_ignored_node (48)', () {
      expect(
        hex(AdminMessages.setIgnoredNode(0x0a, [9], ignored: true)),
        'f8 02 0a aa 06 01 09',
      );
      expect(
        hex(AdminMessages.setIgnoredNode(0x0a, [9], ignored: false)),
        '80 03 0a aa 06 01 09',
      );
    });

    test('only firmware from 2.5.13 keeps the flag', () {
      expect(MeshtasticFirmware.supportsIgnoredNodes('2.5.12.abc'), isFalse);
      expect(MeshtasticFirmware.supportsIgnoredNodes('2.5.13.abc'), isTrue);
      expect(MeshtasticFirmware.supportsIgnoredNodes('2.7.0'), isTrue);
      expect(MeshtasticFirmware.supportsIgnoredNodes(''), isFalse);
    });
  });
}
