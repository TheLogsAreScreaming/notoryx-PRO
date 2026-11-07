import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/radio/radio_link.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final t0 = DateTime.utc(2026, 11, 7, 12);
final mc = RadioId.meshcore('aa' * 32);
final mt = RadioId.meshtastic(0xa1b2c3d4);

Message received(
  Conversation c,
  String text, {
  NodeKey? from,
  String? senderName,
  int? nativeId,
  DateTime? at,
  PathFacts path = PathFacts.none,
}) => Message(
  conversation: c,
  text: text,
  outgoing: false,
  sentAt: at ?? t0,
  receivedAt: at ?? t0,
  delivery: const Received(),
  from: from,
  senderName: senderName,
  nativeId: nativeId,
  path: path,
);

Message outgoing(Conversation c, String text, {int? nativeId}) => Message(
  conversation: c,
  text: text,
  outgoing: true,
  sentAt: t0,
  receivedAt: t0,
  delivery: const Pending(),
  nativeId: nativeId,
);

void main() {
  late MeshStore store;

  setUp(() => store = MeshStore.memory());
  tearDown(() => store.close());

  test('keys parse back from their text form', () {
    final dm = DirectConversation(mt, NodeKey.meshtastic(7));
    expect(Conversation.tryParse(dm.key), dm);
    final ch = ChannelConversation(mc, 3);
    expect(Conversation.tryParse(ch.key), ch);
    expect(Conversation.tryParse('junk'), isNull);
    expect(NodeKey.tryParse('meshtastic:!00000007'), NodeKey.meshtastic(7));
    expect(NodeKey.tryParse('meshcore:'), isNull);
  });

  test('radios round-trip, most recently connected first', () async {
    await store.upsertRadio(
      Radio(
        id: mc,
        name: 'Ridge Base',
        self: NodeKey.meshcore('aa' * 32),
        firmware: 'v1.18.0',
        maxChannels: 40,
        position: const GeoPoint(45.1, -122.6),
      ),
      connectedAt: t0,
    );
    await store.upsertRadio(
      Radio(id: mt, name: 'Base Camp', self: NodeKey.meshtastic(0xa1b2c3d4)),
      connectedAt: t0.add(const Duration(hours: 1)),
    );
    final radios = await store.radios();
    expect(radios.map((r) => r.name), ['Base Camp', 'Ridge Base']);
    expect(radios.last.protocol, RadioProtocol.meshcore);
    expect(radios.last.maxChannels, 40);
    expect(radios.last.position!.latitude, 45.1);
  });

  test('nodes keep path facts and stay separate per radio', () async {
    final peak = Node(
      key: NodeKey.meshcore('ab' * 32),
      radioId: mc,
      name: 'Peak',
      kind: NodeKind.relay,
      lastHeard: t0,
      position: const GeoPoint(46, -121, altitude: 2100),
      path: const PathFacts(hops: 2, snr: 5.5, route: RouteKind.direct),
      isFavorite: true,
    );
    final relay = Node(
      key: NodeKey.meshtastic(0x0badcafe),
      radioId: mt,
      name: 'Ridge Relay',
      shortName: 'RR',
      path: const PathFacts(hops: 1, snr: -3, rssi: -110, viaMqtt: true),
      batteryPercent: 76,
    );
    await store.upsertNodes([peak, relay]);
    final mcNodes = await store.nodes(mc);
    expect(mcNodes.single.name, 'Peak');
    expect(mcNodes.single.path, peak.path);
    expect(mcNodes.single.position, peak.position);
    expect(mcNodes.single.isFavorite, isTrue);
    final mtNode = (await store.nodes(mt)).single;
    expect(mtNode.path, relay.path);
    expect(mtNode.batteryPercent, 76);

    await store.upsertNode(peak.copyWith(name: 'Peak 2'));
    expect((await store.node(mc, peak.key))!.name, 'Peak 2');
    await store.removeNode(mc, peak.key);
    expect(await store.nodes(mc), isEmpty);
  });

  test('MeshCore sender found by key prefix only when unique', () async {
    await store.upsertNodes([
      Node(
        key: NodeKey.meshcore('a1b2c3d4e5f6${'0' * 52}'),
        radioId: mc,
        name: 'A',
      ),
      Node(
        key: NodeKey.meshcore('a1b2c3ffffff${'0' * 52}'),
        radioId: mc,
        name: 'B',
      ),
    ]);
    expect(
      (await store.meshCoreNodeByPrefix(mc, 'A1B2C3D4E5F6'))!.native,
      startsWith('a1b2c3d4e5f6'),
    );
    expect(await store.meshCoreNodeByPrefix(mc, 'a1b2c3'), isNull);
    expect(await store.meshCoreNodeByPrefix(mt, 'a1b2c3d4e5f6'), isNull);
  });

  test('channels are replaced as a set, in slot order', () async {
    await store.replaceChannels(mc, [
      Channel(
        radioId: mc,
        index: 1,
        name: '#hiking',
        kind: ChannelKind.hashtag,
      ),
      Channel(radioId: mc, index: 0, name: 'Public', kind: ChannelKind.public),
    ]);
    expect((await store.channels(mc)).map((c) => c.name), [
      'Public',
      '#hiking',
    ]);
    await store.replaceChannels(mc, [
      Channel(radioId: mc, index: 0, name: 'Public', kind: ChannelKind.public),
    ]);
    expect(await store.channels(mc), hasLength(1));
  });

  test('messages keep path facts and come back oldest first', () async {
    final ch = ChannelConversation(mc, 0);
    await store.addMessage(
      received(
        ch,
        'one',
        senderName: 'Ann',
        path: const PathFacts(hops: 3, snr: 6.5, route: RouteKind.flood),
      ),
    );
    await store.addMessage(
      received(
        ch,
        'two',
        senderName: 'Bob',
        at: t0.add(const Duration(seconds: 5)),
      ),
    );
    final list = await store.messages(ch);
    expect(list.map((m) => m.message.text), ['one', 'two']);
    expect(
      list.first.message.path,
      const PathFacts(hops: 3, snr: 6.5, route: RouteKind.flood),
    );
    expect(list.first.message.senderName, 'Ann');
    expect(list.first.message.conversation, ch);
  });

  test('a repeated received message is stored once', () async {
    final dm = DirectConversation(mt, NodeKey.meshtastic(9));
    final m = received(dm, 'hi', from: NodeKey.meshtastic(9), nativeId: 77);
    expect(await store.addMessage(m), isNotNull);
    expect(await store.addMessage(m), isNull);
    final ch = ChannelConversation(mc, 0);
    final c = received(ch, 'same', senderName: 'Ann');
    expect(await store.addMessage(c), isNotNull);
    expect(await store.addMessage(c), isNull);
    expect(
      await store.addMessage(received(ch, 'same', senderName: 'Bob')),
      isNotNull,
    );
    expect(await store.addMessage(outgoing(ch, 'same')), isNotNull);
    expect(
      await store.addMessage(outgoing(ch, 'same')),
      isNotNull,
      reason: 'own messages are never deduped',
    );
  });

  test('delivery only moves forward', () async {
    final dm = DirectConversation(mc, NodeKey.meshcore('ab' * 32));
    final id = (await store.addMessage(outgoing(dm, 'hello')))!;
    await store.setNativeId(id, 0xdeadbeef);

    Future<DeliveryState> state() async =>
        (await store.messages(dm)).single.message.delivery;

    expect(
      await store.setDeliveryByNativeId(
        mc,
        0xdeadbeef,
        const Sent(flood: true),
      ),
      isTrue,
    );
    expect((await state() as Sent).flood, isTrue);
    expect(await store.setDelivery(id, const Pending()), isFalse);
    expect(
      await store.setDelivery(
        id,
        const Delivered(roundTrip: Duration(milliseconds: 1450)),
      ),
      isTrue,
    );
    expect(
      (await state() as Delivered).roundTrip,
      const Duration(milliseconds: 1450),
    );
    expect(await store.setDelivery(id, const Failed('late timeout')), isFalse);
    expect(await state(), isA<Delivered>());
    expect(
      await store.setDeliveryByNativeId(mt, 0xdeadbeef, const Relayed()),
      isFalse,
    );
  });

  test('a failed message can be retried', () async {
    final ch = ChannelConversation(mt, 0);
    final id = (await store.addMessage(outgoing(ch, 'x')))!;
    await store.setDelivery(id, const Failed('No route to the node'));
    var m = (await store.messages(ch)).single.message;
    expect((m.delivery as Failed).reason, 'No route to the node');
    expect(await store.setDelivery(id, const Relayed()), isFalse);
    expect(await store.setDelivery(id, const Pending()), isTrue);
    m = (await store.messages(ch)).single.message;
    expect(m.delivery, isA<Pending>());
  });

  test('inbox lists the newest message per conversation', () async {
    final a = ChannelConversation(mc, 0);
    final b = DirectConversation(mt, NodeKey.meshtastic(5));
    await store.addMessage(received(a, 'a1', senderName: 'x'));
    await store.addMessage(
      received(b, 'b1', from: NodeKey.meshtastic(5), nativeId: 1),
    );
    await store.addMessage(received(a, 'a2', senderName: 'y'));
    final inbox = await store.conversations();
    expect(inbox.map((s) => s.last.message.text), ['a2', 'b1']);
    expect(inbox.first.conversation, a);
  });

  test('watchers see new messages', () async {
    final ch = ChannelConversation(mc, 0);
    final seen = <int>[];
    final sub = store.watchMessages(ch).listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.addMessage(received(ch, 'new', senderName: 'z'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
