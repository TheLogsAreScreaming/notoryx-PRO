import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/heard_cleanup.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

void main() {
  final mc = RadioId.meshcore('aa' * 32);
  final mt = RadioId.meshtastic(0xa1b2c3d4);
  final appStart = DateTime.utc(2026, 11, 7, 12);
  final badClock = DateTime.utc(2024, 5, 15);
  final real = DateTime.utc(2026, 11, 19, 9);

  late MeshStore store;
  setUp(() async {
    store = MeshStore.memory();
    await store.addMessage(
      Message(
        conversation: ChannelConversation(mc, 0),
        text: 'first',
        outgoing: false,
        sentAt: appStart,
        receivedAt: appStart,
        delivery: const Received(),
        senderName: 'Ann',
      ),
    );
  });
  tearDown(() => store.close());

  Node node(RadioId radio, NodeKey key, DateTime? heard) =>
      Node(key: key, radioId: radio, name: key.short, lastHeard: heard);

  Future<DateTime?> heard(RadioId radio, NodeKey key) async =>
      (await store.node(radio, key))?.lastHeard?.toUtc();

  test('MeshCore times from before the app first ran become unknown', () async {
    final old = NodeKey.meshcore('11' * 32);
    final fresh = NodeKey.meshcore('22' * 32);
    final unknown = NodeKey.meshcore('33' * 32);
    final mtOld = NodeKey.meshtastic(0x44);
    await store.upsertNodes([
      node(mc, old, badClock),
      node(mc, fresh, real),
      node(mc, unknown, null),
      node(mt, mtOld, badClock),
    ]);

    expect(await store.clearPreAppMeshCoreHeard(), 1);
    expect(await heard(mc, old), isNull);
    expect(await heard(mc, fresh), real);
    expect(await heard(mc, unknown), isNull);
    expect(
      await heard(mt, mtOld),
      badClock,
      reason: 'Meshtastic times are left alone',
    );
  });

  test(
    'a time just before the first message is kept (a day of slack)',
    () async {
      final edge = NodeKey.meshcore('55' * 32);
      await store.upsertNode(
        node(mc, edge, appStart.subtract(const Duration(hours: 20))),
      );
      expect(await store.clearPreAppMeshCoreHeard(), 0);
      expect(await heard(mc, edge), isNotNull);
    },
  );

  test('nothing changes before any message is saved', () async {
    final empty = MeshStore.memory();
    addTearDown(empty.close);
    final old = NodeKey.meshcore('66' * 32);
    await empty.upsertNode(node(mc, old, badClock));
    expect(await empty.clearPreAppMeshCoreHeard(), 0);
    expect((await empty.node(mc, old))?.lastHeard?.toUtc(), badClock);
  });

  test('the cleanup runs once per install', () async {
    final old = NodeKey.meshcore('77' * 32);
    await store.upsertNode(node(mc, old, badClock));
    expect(await HeardCleanup.runOnce(store), 1);

    // A wrong time saved later (say, restored from an old export) is left
    // to the normal rules; the one-off cleanup doesn't run again.
    await store.upsertNode(node(mc, old, badClock));
    expect(await HeardCleanup.runOnce(store), 0);
    expect(await heard(mc, old), badClock);
  });
}
