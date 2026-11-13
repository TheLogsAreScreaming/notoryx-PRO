import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

Future<void> waitFor(bool Function() done) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsedMilliseconds > 3000) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Responder companion() =>
    (cmd) => switch (cmd.first) {
      Cmd.appStart => [RadioFrames.selfInfo()],
      Cmd.deviceQuery => [RadioFrames.deviceInfo()],
      Cmd.setDeviceTime => [RadioFrames.ok()],
      Cmd.getContacts => [
        RadioFrames.contactsStart(2),
        RadioFrames.contact(seed: 0xa1, name: 'Peak', type: 2, pathLength: 0),
        RadioFrames.contact(seed: 0xee, name: 'Sam', pathLength: 0x02),
        RadioFrames.endOfContacts(5),
      ],
      Cmd.getChannel => [RadioFrames.err(2)],
      Cmd.syncNextMessage => [RadioFrames.noMore()],
      Cmd.getStats => [
        (ByteWriter()
              ..u8(24)
              ..u8(1)
              ..bytes([0x8a, 0xff])
              ..u8((-90) & 0xff)
              ..u8(20)
              ..u32(5)
              ..u32(50))
            .toBytes(),
      ],
      Cmd.sendTracePath => [
        RadioFrames.sent(ack: 1, timeoutMs: 10),
        _traceBack(cmd),
      ],
      _ => [RadioFrames.err(1)],
    };

/// Echoes the trace's tag and path with made-up SNRs.
Uint8List _traceBack(Uint8List cmd) {
  final tag = ByteData.sublistView(cmd, 1, 5).getUint32(0, Endian.little);
  final path = cmd.sublist(10);
  return (ByteWriter()
        ..u8(0x89)
        ..u8(0)
        ..u8(path.length)
        ..u8(0)
        ..u32(tag)
        ..u32(0)
        ..bytes(path)
        ..bytes([for (var i = 0; i < path.length; i++) (12 - 8 * i) & 0xff])
        ..u8(6))
      .toBytes();
}

void main() {
  late MeshStore store;
  setUp(() => store = MeshStore.memory());
  tearDown(() => store.close());

  test('MeshCore: packet log, radio stats and a trace', () async {
    final link = ScriptedMeshCoreLink(responder: companion());
    final app = AppController(store: store, links: FakeLinks(link));
    final c =
        await app.connect(
              const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
            )
            as MeshCoreConnection;
    expect(c.frequencyMHz, closeTo(910.525, 1e-9));

    link.push(
      Uint8List.fromList([0x88, 24, (-101) & 0xff, 0x11, 0x01, 0xa1, 9, 9, 9]),
    );
    await waitFor(() => c.packetLog.entries.isNotEmpty);
    final e = c.packetLog.entries.single;
    expect(e.kind, 'Advert');
    expect(
      e.path,
      const PathFacts(hops: 1, snr: 6, rssi: -101, route: RouteKind.flood),
    );
    expect(e.detail, 'a1');

    final s = (await c.sampleRadio())!;
    expect(s.noiseFloor, -118);
    expect(c.samples.latest!.lastRssi, -90);

    final sam = (await store.nodes(
      c.radio!.id,
    )).firstWhere((n) => n.name == 'Sam');
    // Sam's route is aa bb (from the contact frame); make the first hop Peak.
    final routed = sam.copyWith(route: [0xa1, 0xb2]);
    expect(c.canTrace(routed), isTrue);
    expect(MeshCoreConnection.tracePath(routed), [0xa1, 0xb2, 0xa1]);
    final r = await c.trace(routed);
    expect(r.towards.map((h) => h.label), ['Peak', 'b2']);
    expect(r.towards.map((h) => h.snr), [3.0, 1.0]);
    expect(r.back.map((h) => h.label), ['Peak', 'Ridge Base']);
    expect(r.weakest!.snr, -1.0);
    expect(r.roundTrip, isNotNull, reason: 'the card shows the timing');
    await c.traceAndSave(routed);
    final saved = await store.traces(routed.radioId, routed.key);
    expect(saved.single.targetName, 'Sam');
    expect(saved.single.result.towards.map((h) => h.label), ['Peak', 'b2']);
    await app.shutdown();
  });

  test('Meshtastic: packet log, local stats and traceroute', () async {
    final link = ScriptedMeshtasticLink();
    link.onPacket = (p) {
      if (p.decoded?.portnum != PortNum.traceroute) return const [];
      final route = ByteData(4)..setUint32(0, 0x0badcafe, Endian.little);
      final payload =
          (ProtoWriter()
                ..bytes(1, route.buffer.asUint8List())
                ..bytes(2, [24, 0x10]))
              .toBytes();
      return [
        NodeFrames.packet(
          from: p.to,
          to: link.myNode,
          portnum: PortNum.traceroute,
          payload: payload,
          requestId: p.id,
        ),
      ];
    };
    final app = AppController(store: store, links: FakeLinks(link));
    final c = await app.connect(
      const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
    );

    link.push(NodeFrames.text(from: 0x22, to: broadcastNode, text: 'yo'));
    await waitFor(() => c.packetLog.entries.any((x) => x.from == '!00000022'));
    final e = c.packetLog.entries.lastWhere((x) => x.from == '!00000022');
    expect(e.kind, 'Text message');
    expect(e.from, '!00000022');
    expect(e.path.hops, 2);

    int bits(double v) => (ByteData(
      4,
    )..setFloat32(0, v, Endian.little)).getUint32(0, Endian.little);
    final local = (ProtoWriter()..fixed32(2, bits(12.5))).toBytes();
    link.push(
      NodeFrames.packet(
        from: link.myNode,
        to: broadcastNode,
        portnum: PortNum.telemetry,
        payload: (ProtoWriter()..bytes(6, local)).toBytes(),
      ),
    );
    await waitFor(() => c.samples.latest != null);
    expect(c.samples.latest!.channelUtilization, 12.5);
    expect(
      c.packetLog.entries.where((x) => x.from == meshtasticNodeId(link.myNode)),
      isEmpty,
      reason: 'own packets are not logged',
    );

    final target = Node(
      key: NodeKey.meshtastic(0x33),
      radioId: c.radio!.id,
      name: 'Far',
    );
    final r = await c.trace(target);
    expect(r.towards.map((h) => h.label), ['Ridge Relay', '!00000033']);
    expect(r.towards.map((h) => h.snr), [6.0, 4.0]);
    expect(r.back, isEmpty);
    expect(r.roundTrip, isNotNull);
    await app.shutdown();
  });

  test('describeError covers trace timeouts', () {
    expect(
      RadioConnection.describeError(const MeshCoreTimeout(Cmd.sendTracePath)),
      'The radio did not answer',
    );
  });
}
