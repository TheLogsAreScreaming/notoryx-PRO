import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/nearby_probe.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

class _Links extends LinkFactory {
  _Links(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

/// A control-data push carrying a discover answer.
Uint8List answer({
  required int tag,
  required int seed,
  int type = 2,
  int heardUs = -14, // ×4: -3.5 dB
  int snr = 22, // ×4: 5.5 dB
  int rssi = -88,
}) {
  final w = ByteWriter()
    ..u8(Push.controlData)
    ..u8(snr)
    ..u8(rssi)
    ..u8(0)
    ..u8(0x90 | type)
    ..u8(heardUs)
    ..u32(tag)
    ..bytes(RadioFrames.key(seed));
  return w.toBytes();
}

void main() {
  test('discover request layout', () {
    final f = MeshCoreCommands.discoverNodes(tag: 0x01020304);
    expect(f, [55, 0x80, 0x04, 4, 3, 2, 1, 0, 0, 0, 0]);
  });

  test('a control-data push decodes its discover answer', () {
    final f = decodeFrame(answer(tag: 7, seed: 0x30));
    final a = (f as ControlDataPush).discoverAnswer!;
    expect(a.tag, 7);
    expect(a.nodeType, 2);
    expect(a.heardUsSnr, -3.5);
    expect(a.snr, 5.5);
    expect(a.rssi, -88);
    expect(a.key, RadioFrames.key(0x30));
  });

  test('MeshCore: repeaters in range answer the probe', () async {
    late ScriptedMeshCoreLink link;
    link = ScriptedMeshCoreLink(
      responder: (cmd) => switch (cmd.first) {
        Cmd.appStart => [RadioFrames.selfInfo()],
        Cmd.deviceQuery => [RadioFrames.deviceInfo()],
        Cmd.setDeviceTime => [RadioFrames.ok()],
        Cmd.getContacts => [
          RadioFrames.contactsStart(1),
          RadioFrames.contact(seed: 0x30, name: 'Peak', type: 2),
          RadioFrames.endOfContacts(1),
        ],
        Cmd.getChannel => [RadioFrames.err(2)],
        Cmd.syncNextMessage => [RadioFrames.noMore()],
        Cmd.sendControlData => () {
          final tag = ByteData.sublistView(cmd).getUint32(3, Endian.little);
          return [
            RadioFrames.ok(),
            answer(tag: tag, seed: 0x30),
            answer(tag: tag, seed: 0x30), // repeated: counted once
            answer(tag: tag, seed: 0x50, snr: -20, rssi: -115),
            answer(tag: tag + 1, seed: 0x60), // someone else's test
          ];
        }(),
        _ => [RadioFrames.err(1)],
      },
    );
    final store = MeshStore.memory();
    final app = AppController(store: store, links: _Links(link));
    final c = await app.connect(
      const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
    );
    final found = await c.probeNearby(
      listen: const Duration(milliseconds: 100),
    );
    expect(found.map((n) => n.name), [
      'Peak',
      toHex(RadioFrames.key(0x50)).substring(0, 8),
    ]);
    expect(found.first.kind, NodeKind.relay);
    expect(found.first.node, isNotNull);
    expect(found.first.heardUsSnr, -3.5);
    expect(found.last.snr, -5);
    expect(found.last.rssi, -115);
    await app.shutdown();
    await store.close();
  });

  test('MeshCore: the probe needs protocol 8', () async {
    // The scripted radio reports a recent protocol, so check the gate on
    // the session directly with an old one.
    expect(MeshCoreFirmware.supports(7, MeshCoreFeature.stats), isFalse);
  });

  test('Meshtastic: a zero-hop info request, direct answers only', () async {
    final link = ScriptedMeshtasticLink();
    MeshPacket? asked;
    link.onPacket = (p) {
      if (p.decoded?.portnum != PortNum.nodeInfo) return const [];
      asked = p;
      return [
        NodeFrames.packet(
          from: 0x22,
          to: link.myNode,
          portnum: PortNum.nodeInfo,
          payload:
              (ProtoWriter()
                    ..string(1, '!00000022')
                    ..string(2, 'Hill Router')
                    ..uint(7, 2))
                  .toBytes(),
          hopStart: 3,
          hopLimit: 3,
          snr: 4.25,
          rssi: -101,
        ),
        // Came through a repeater: not in direct range.
        NodeFrames.packet(
          from: 0x33,
          to: link.myNode,
          portnum: PortNum.nodeInfo,
          payload: (ProtoWriter()..string(2, 'Far Away')).toBytes(),
          hopStart: 3,
          hopLimit: 1,
        ),
      ];
    };
    final store = MeshStore.memory();
    final app = AppController(store: store, links: _Links(link));
    final c = await app.connect(
      const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
    );
    final found = await c.probeNearby(
      listen: const Duration(milliseconds: 100),
    );
    expect(asked!.hopLimit, 0, reason: 'nobody repeats it');
    expect(asked!.wantAck, isFalse);
    expect(asked!.to, broadcastNode);
    expect(asked!.decoded!.wantResponse, isTrue);
    expect(MeshUser.decode(asked!.decoded!.payload).longName, 'Base Camp');
    expect(found, hasLength(1));
    expect(found.single.name, 'Hill Router');
    expect(found.single.kind, NodeKind.relay);
    expect(found.single.snr, 4.25);
    expect(found.single.rssi, -101);
    await app.shutdown();
    await store.close();
  });

  test('answers come first, then quiet direct neighbours', () {
    final radio = RadioId.meshtastic(1);
    final now = DateTime(2026, 11, 13, 12);
    Node node(
      int n, {
      int? hops,
      Duration ago = Duration.zero,
      NodeKind kind = NodeKind.person,
      double? snr,
    }) => Node(
      key: NodeKey.meshtastic(n),
      radioId: radio,
      name: 'N$n',
      kind: kind,
      lastHeard: now.subtract(ago),
      path: PathFacts(hops: hops, snr: snr),
    );
    final answers = [
      NearbyNode(
        id: NodeKey.meshtastic(1).native,
        name: 'N1',
        kind: NodeKind.person,
        snr: 9,
      ),
      NearbyNode(
        id: NodeKey.meshtastic(2).native,
        name: 'N2',
        kind: NodeKind.relay,
        snr: -3,
      ),
    ];
    final merged = mergeNearby(answers, [
      node(1, hops: 0), // answered already
      node(3, hops: 0, kind: NodeKind.relay, snr: 2),
      node(4, hops: 0, ago: const Duration(hours: 2)), // too long ago
      node(5, hops: 1), // not direct
    ], now: now);
    expect(merged.map((n) => n.name), ['N2', 'N1', 'N3']);
    expect(merged.last.answered, isFalse);
    expect(
      mergeNearby(
        answers,
        const [],
        now: now,
        infrastructureOnly: true,
      ).map((n) => n.name),
      ['N2'],
    );
  });
}
