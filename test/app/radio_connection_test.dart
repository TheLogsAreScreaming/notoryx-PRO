import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

/// Hands out pre-made scripted links.
class FakeLinks extends LinkFactory {
  FakeLinks(this.links);
  final Map<RadioProtocol, RadioLink> links;

  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) =>
      links[target.protocol]!;
}

/// A v1.18 companion with one contact, two channels and one queued message.
Responder companion() {
  final inbox = [RadioFrames.channelMessageV3(text: 'Ann: hello trail')];
  return (cmd) => switch (cmd.first) {
    Cmd.appStart => [RadioFrames.selfInfo()],
    Cmd.deviceQuery => [RadioFrames.deviceInfo()],
    Cmd.setDeviceTime => [RadioFrames.ok()],
    Cmd.getContacts => [
      RadioFrames.contactsStart(1),
      RadioFrames.contact(seed: 0x40, name: 'Alpha'),
      RadioFrames.endOfContacts(5),
    ],
    Cmd.getChannel => [
      if (cmd[1] == 0)
        Uint8List.fromList([
          18,
          0,
          ...'Public'.codeUnits,
          ...List.filled(26, 0),
          ...fromHex(meshCorePublicKeyHex),
        ])
      else if (cmd[1] == 1)
        Uint8List.fromList([18, 1, ...List.filled(48, 0)])
      else
        RadioFrames.err(2),
    ],
    Cmd.syncNextMessage => [
      inbox.isEmpty ? RadioFrames.noMore() : inbox.removeAt(0),
    ],
    Cmd.sendText => [RadioFrames.sent(ack: 0x55)],
    Cmd.sendChannelText => [RadioFrames.ok()],
    _ => [RadioFrames.err(1)],
  };
}

Future<void> waitFor(bool Function() done) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsedMilliseconds > 3000) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MeshStore store;
  setUp(() => store = MeshStore.memory());
  tearDown(() => store.close());

  test('MeshCore: connect, sync, receive, send and confirm', () async {
    final link = ScriptedMeshCoreLink(responder: companion());
    final app = AppController(
      store: store,
      links: FakeLinks({RadioProtocol.meshcore: link}),
    );
    final c = await app.connect(
      const BleTarget(
        deviceId: 'x',
        name: 'MeshCore-Ridge',
        protocol: RadioProtocol.meshcore,
      ),
    );
    expect(c.status.phase, SupervisorPhase.connected);
    final radio = c.radio!;
    expect(radio.name, 'Ridge Base');
    expect((await store.radios()).single.id, radio.id);
    expect((await store.nodes(radio.id)).single.name, 'Alpha');
    expect((await store.channels(radio.id)).map((ch) => ch.name), ['Public']);

    final channel = ChannelConversation(radio.id, 0);
    var thread = await store.messages(channel);
    for (var i = 0; i < 50 && thread.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      thread = await store.messages(channel);
    }
    expect(thread.single.message.text, 'hello trail');
    expect(thread.single.message.senderName, 'Ann');

    final alpha = NodeKey.meshcore(toHex(RadioFrames.key(0x40)));
    final dm = DirectConversation(radio.id, alpha);
    final id = await c.sendText(dm, 'on my way');
    var sent = (await store.messages(dm)).single;
    expect(sent.id, id);
    expect(sent.message.delivery, isA<Sent>());
    expect(sent.message.nativeId, 0x55);
    expect(link.commands.last.first, Cmd.sendText);

    link.push(RadioFrames.sendConfirmed(0x55));
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sent = (await store.messages(dm)).single;
      if (sent.message.delivery is Delivered) break;
    }
    expect(sent.message.delivery, isA<Delivered>());

    await c.sendText(channel, 'all good');
    final last = (await store.messages(channel)).last.message;
    expect(last.outgoing, isTrue);
    expect(last.delivery, isA<Sent>());

    await app.shutdown();
  });

  test('Meshtastic: connect, sync, receive, send and deliver', () async {
    final link = ScriptedMeshtasticLink();
    link.onPacket = (p) => [
      NodeFrames.routing(from: p.to, to: link.myNode, requestId: p.id),
    ];
    final app = AppController(
      store: store,
      links: FakeLinks({RadioProtocol.meshtastic: link}),
    );
    final c = await app.connect(
      const TcpTarget(host: 'node.local', protocol: RadioProtocol.meshtastic),
    );
    final radio = c.radio!;
    expect(radio.name, 'Base Camp');
    final nodes = await store.nodes(radio.id);
    expect(nodes.map((n) => n.name), [
      'Ridge Relay',
    ], reason: 'own node left out');
    expect(nodes.single.path.hops, 2);
    expect((await store.channels(radio.id)).map((ch) => ch.name), [
      'Primary',
      'Trail',
    ]);

    link.push(NodeFrames.text(from: 0x0badcafe, to: link.myNode, text: 'psst'));
    final dm = DirectConversation(radio.id, NodeKey.meshtastic(0x0badcafe));
    var thread = <StoredMessage>[];
    for (var i = 0; i < 50 && thread.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      thread = await store.messages(dm);
    }
    expect(thread.single.message.text, 'psst');
    expect(thread.single.message.path.rssi, -97);

    await c.sendText(dm, 'got it');
    StoredMessage mine = (await store.messages(dm)).last;
    for (var i = 0; i < 80; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      mine = (await store.messages(dm)).last;
      if (mine.message.delivery is Delivered) break;
    }
    expect(mine.message.outgoing, isTrue);
    expect(mine.message.delivery, isA<Delivered>());
    expect(link.sent.last.packet!.to, 0x0badcafe);

    await app.shutdown();
  });

  test('old firmware stops the connection with a reason', () async {
    final link = ScriptedMeshtasticLink(firmware: '2.3.0.abc');
    final app = AppController(
      store: store,
      links: FakeLinks({RadioProtocol.meshtastic: link}),
    );
    final c = await app.connect(
      const TcpTarget(host: 'old', protocol: RadioProtocol.meshtastic),
    );
    expect(c.status.phase, SupervisorPhase.failed);
    expect(c.status.lastError, isA<UnsupportedMeshtasticFirmware>());
    expect(c.radio, isNull);
    await app.shutdown();
  });

  test('sending while not connected fails clearly', () async {
    final link = ScriptedMeshtasticLink();
    final app = AppController(
      store: store,
      links: FakeLinks({RadioProtocol.meshtastic: link}),
    );
    final c = await app.connect(
      const TcpTarget(host: 'n', protocol: RadioProtocol.meshtastic),
    );
    final other = ChannelConversation(RadioId.meshtastic(1), 0);
    expect(() => c.sendText(other, 'x'), throwsStateError);
    await app.disconnect(app.connections.single);
    expect(app.connections, isEmpty);
    expect(link.state, LinkState.disconnected);
    await app.shutdown();
  });
}
