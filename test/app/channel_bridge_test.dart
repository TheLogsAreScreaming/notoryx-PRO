import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/channel_bridge.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

void main() {
  final mcId = RadioId.tryParse('meshcore:aa')!;
  final mtId = RadioId.tryParse('meshtastic:bb')!;
  final mc = ChannelConversation(mcId, 1);
  final mt = ChannelConversation(mtId, 2);
  final start = DateTime(2026, 11, 8, 12);

  late MeshStore store;
  late List<(Conversation, String)> sent;
  late DateTime now;
  late ChannelBridge bridge;
  late BridgeLink link;
  var connected = true;

  Future<void> hear(
    Conversation c,
    String text, {
    String? name = 'Ann',
    DateTime? at,
    bool reaction = false,
  }) async {
    await store.addMessage(
      Message(
        conversation: c,
        text: text,
        outgoing: false,
        sentAt: at ?? now,
        receivedAt: now,
        delivery: const Received(),
        senderName: name,
        isReaction: reaction,
      ),
    );
    await pumpEventQueue();
    await bridge.idle;
  }

  setUp(() async {
    store = MeshStore.memory();
    sent = [];
    now = start;
    connected = true;
    bridge = ChannelBridge(
      store,
      clock: () => now,
      send: (to, text) async {
        if (!connected) return false;
        sent.add((to, text));
        return true;
      },
    );
    link = BridgeLink(a: mc, b: mt, aLabel: 'Hike', bLabel: 'Trail');
    await bridge.load();
    await bridge.add(link);
  });

  tearDown(() async {
    await bridge.stop();
    await store.close();
  });

  test('nothing crosses until the link is turned on', () async {
    await hear(mc, 'hello');
    expect(sent, isEmpty);
  });

  test('copies both ways with a label', () async {
    await bridge.setEnabled(link, true);
    await hear(mc, 'hello');
    await hear(mt, 'back at you', name: 'Bob');
    expect(sent, [(mt, '[MC Ann] hello'), (mc, '[MT Bob] back at you')]);
    expect(bridge.statsFor(link).forwarded, 2);
  });

  test('other conversations and reactions stay put', () async {
    await bridge.setEnabled(link, true);
    await hear(ChannelConversation(mcId, 3), 'not linked');
    await hear(mc, '👍', reaction: true);
    expect(sent, isEmpty);
  });

  test('never forwards what a bridge already forwarded', () async {
    await bridge.setEnabled(link, true);
    await hear(mc, '[MT Bob] from another bridge');
    await hear(mt, 'Relay: [MC Ann] with a name in front');
    expect(sent, isEmpty);
    expect(ChannelBridge.isBridged('[note] ordinary'), isFalse);
  });

  test('limits each direction, then recovers', () async {
    await bridge.setEnabled(link, true);
    for (var i = 0; i < 7; i++) {
      await hear(mc, 'm$i');
    }
    expect(sent, hasLength(ChannelBridge.maxPerWindow));
    expect(bridge.statsFor(link).held, 2);
    expect(bridge.statsFor(link).lastHold, BridgeHold.tooFast);
    await hear(mt, 'other way still free');
    expect(sent, hasLength(ChannelBridge.maxPerWindow + 1));
    now = now.add(ChannelBridge.window);
    await hear(mc, 'later');
    expect(sent.last.$2, '[MC Ann] later');
  });

  test('drops a repeat and an old backlog', () async {
    await bridge.setEnabled(link, true);
    await hear(mc, 'same', at: now);
    await hear(mc, 'same', at: now.add(const Duration(seconds: 1)));
    expect(sent, hasLength(1));
    expect(bridge.statsFor(link).lastHold, BridgeHold.repeated);
    await hear(mc, 'stale', at: now.subtract(const Duration(hours: 1)));
    expect(sent, hasLength(1));
    expect(bridge.statsFor(link).lastHold, BridgeHold.tooOld);
  });

  test('counts a message the other radio could not take', () async {
    await bridge.setEnabled(link, true);
    connected = false;
    await hear(mc, 'nobody home');
    expect(bridge.statsFor(link).lastHold, BridgeHold.offline);
  });

  test('a direct message cannot be linked to a channel', () async {
    final dm = DirectConversation(mcId, NodeKey.meshcore('cc'));
    expect(BridgeLink.isAllowed(dm, mt), isFalse);
    expect(BridgeLink.isAllowed(mc, ChannelConversation(mcId, 2)), isFalse);
    expect(
      () => bridge.add(BridgeLink(a: dm, b: mt, aLabel: 'x', bLabel: 'y')),
      throwsArgumentError,
    );
  });

  test('links are saved, off stays off, and pairs are unique', () async {
    expect(await bridge.add(link), isFalse);
    await bridge.setEnabled(link, true);
    final again = ChannelBridge(store, send: (_, _) async => true);
    await again.load();
    expect(again.links.single.id, link.id);
    expect(again.links.single.enabled, isTrue);
    await again.stop();
  });

  group('compose', () {
    test('fits the limit without splitting a character', () {
      final t = ChannelBridge.compose(
        RadioProtocol.meshcore,
        'Ann',
        '🙂' * 100,
        40,
      );
      expect(utf8.encode(t).length, lessThanOrEqualTo(40));
      expect(t, startsWith('[MC Ann] 🙂'));
      expect(t, endsWith('…'));
    });

    test('a sender name cannot forge the label', () {
      expect(
        ChannelBridge.compose(RadioProtocol.meshtastic, 'a]\n[MC x', 'hi', 99),
        '[MT aMC x] hi',
      );
      expect(
        ChannelBridge.compose(RadioProtocol.meshtastic, '', 'hi', 99),
        '[MT ?] hi',
      );
    });
  });
}
