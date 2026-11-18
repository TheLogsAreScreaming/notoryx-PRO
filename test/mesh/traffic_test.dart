import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/hop_naming.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/raw_packet.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';

final t0 = DateTime.utc(2026, 11, 18, 12);
final mc = RadioId.meshcore('aa' * 32);
final mt = RadioId.meshtastic(0x0000aaaa);

Node mcNode(String keyStart, String name, {GeoPoint? at}) => Node(
  key: NodeKey.meshcore(keyStart.padRight(64, '0')),
  radioId: mc,
  name: name,
  kind: NodeKind.relay,
  position: at,
);

Node mtNode(int num, String name, {GeoPoint? at}) =>
    Node(key: NodeKey.meshtastic(num), radioId: mt, name: name, position: at);

/// A raw MeshCore packet: header (route + payload type), path, payload.
Uint8List rawPacket({
  required int payloadType,
  int route = 1, // flood
  List<int> path = const [],
  int hashSize = 1,
  List<int> body = const [],
}) => Uint8List.fromList([
  (payloadType << 2) | route,
  ((hashSize - 1) << 6) | (path.length ~/ hashSize),
  ...path,
  ...body,
]);

/// An advert body: key, timestamp, signature, then app data with a
/// location and a name.
List<int> advertBody(String keyHex, {double? lat, double? lon, String? name}) {
  final key = [
    for (var i = 0; i < 64; i += 2)
      int.parse(keyHex.substring(i, i + 2), radix: 16),
  ];
  var flags = 0x02; // repeater
  final data = <int>[];
  if (lat != null && lon != null) {
    flags |= 0x10;
    final d = ByteData(8)
      ..setInt32(0, (lat * 1e6).round(), Endian.little)
      ..setInt32(4, (lon * 1e6).round(), Endian.little);
    data.addAll(d.buffer.asUint8List());
  }
  if (name != null) {
    flags |= 0x80;
    data.addAll(name.codeUnits);
  }
  return [...key, ...List.filled(4, 0), ...List.filled(64, 0), flags, ...data];
}

void main() {
  group('packet colours', () {
    test('MeshCore payloads map onto the six kinds', () {
      expect(trafficKindOfMeshCore(MeshCorePayload.advert), TrafficKind.advert);
      expect(trafficKindOfMeshCore(MeshCorePayload.text), TrafficKind.direct);
      expect(
        trafficKindOfMeshCore(MeshCorePayload.request),
        TrafficKind.direct,
      );
      expect(
        trafficKindOfMeshCore(MeshCorePayload.groupText),
        TrafficKind.channel,
      );
      expect(trafficKindOfMeshCore(MeshCorePayload.ack), TrafficKind.ack);
      expect(trafficKindOfMeshCore(MeshCorePayload.trace), TrafficKind.trace);
      expect(trafficKindOfMeshCore(MeshCorePayload.path), TrafficKind.path);
      expect(
        trafficKindOfMeshCore(MeshCorePayload.multipart),
        TrafficKind.path,
      );
    });

    test('Meshtastic ports map onto the six kinds', () {
      TrafficKind k(int? port, {bool broadcast = true}) =>
          trafficKindOfMeshtastic(port, broadcast: broadcast);
      expect(k(PortNum.position), TrafficKind.advert);
      expect(k(PortNum.nodeInfo), TrafficKind.advert);
      expect(k(PortNum.textMessage), TrafficKind.channel);
      expect(k(PortNum.textMessage, broadcast: false), TrafficKind.direct);
      expect(k(PortNum.routing), TrafficKind.ack);
      expect(k(PortNum.traceroute), TrafficKind.trace);
      expect(k(PortNum.telemetry), TrafficKind.path);
      expect(k(null), TrafficKind.path);
    });
  });

  group('MeshCore raw packets', () {
    test('a flooded direct message lists its repeaters and sender hash', () {
      final info = MeshCorePacketInfo.parse(
        rawPacket(
          payloadType: 2,
          path: [0xa1, 0xb2, 0xc3],
          body: [0x11, 0xee, 0, 0, 9, 9],
        ),
      )!;
      final p = heardMeshCore(info, radioId: mc, time: t0, snr: 7.5, rssi: -90);
      expect(p.kind, TrafficKind.direct);
      expect(p.label, 'Direct message');
      expect(p.origin, const HopId('ee', HopMatch.prefix));
      expect(p.hops.map((h) => h.id), ['a1', 'b2', 'c3']);
      expect(p.hopCount, 3);
      expect(p.flood, isTrue);
      expect(p.snr, 7.5);
      expect(p.rssi, -90);
    });

    test('two-byte path hashes stay whole', () {
      final info = MeshCorePacketInfo.parse(
        rawPacket(payloadType: 5, path: [0x9f, 0x67, 0x04, 0x53], hashSize: 2),
      )!;
      final p = heardMeshCore(info, radioId: mc, time: t0);
      expect(p.hops.map((h) => h.id), ['9f67', '0453']);
      expect(p.origin, isNull); // channel messages hide the sender
    });

    test('a direct-routed packet has passed nothing we can see', () {
      final info = MeshCorePacketInfo.parse(
        rawPacket(payloadType: 2, route: 2, path: [0xa1], body: [1, 2]),
      )!;
      final p = heardMeshCore(info, radioId: mc, time: t0);
      expect(p.hops, isEmpty);
      expect(p.flood, isFalse);
      expect(p.hopCount, isNull);
    });

    test('an advert gives its key, name and location', () {
      final key = 'c0ffee'.padRight(64, '1');
      final info = MeshCorePacketInfo.parse(
        rawPacket(
          payloadType: 4,
          path: [0xa1],
          body: advertBody(key, lat: 38.9, lon: -77.03, name: 'Hilltop'),
        ),
      )!;
      final p = heardMeshCore(info, radioId: mc, time: t0);
      expect(p.kind, TrafficKind.advert);
      expect(p.origin, HopId(key, HopMatch.key));
      expect(p.originName, 'Hilltop');
      expect(p.originAt!.latitude, closeTo(38.9, 1e-6));
      expect(p.originAt!.longitude, closeTo(-77.03, 1e-6));
    });

    test('a trace takes its hops from the payload', () {
      final info = MeshCorePacketInfo.parse(
        rawPacket(
          payloadType: 9,
          path: [20, 12], // two SNR bytes: two hops done
          body: [1, 2, 3, 4, 5, 6, 7, 8, 0, 0xa1, 0xb2, 0xc3],
        ),
      )!;
      final p = heardMeshCore(info, radioId: mc, time: t0);
      expect(p.kind, TrafficKind.trace);
      expect(p.hops.map((h) => h.id), ['a1', 'b2']);
    });
  });

  group('route building', () {
    const here = GeoPoint(39.0, -77.0);
    final peak = mcNode('a1', 'Peak', at: const GeoPoint(39.2, -77.2));
    final dark = mcNode('b2', 'Dark Hill');
    final ridge = mcNode('c3', 'Ridge', at: const GeoPoint(39.1, -77.1));
    final sender = mcNode('ee', 'Sam', at: const GeoPoint(39.3, -77.3));

    HeardPacket packet({
      HopId? origin,
      List<String> hops = const [],
      TrafficKind kind = TrafficKind.direct,
    }) => HeardPacket(
      time: t0,
      radioId: mc,
      kind: kind,
      label: 'Direct message',
      origin: origin,
      hops: [for (final h in hops) HopId(h, HopMatch.prefix)],
      hopCount: hops.length,
    );

    test('path hashes become stops in order, ending at us', () {
      final r = buildTrafficRoute(
        packet(origin: const HopId('ee', HopMatch.prefix), hops: ['a1', 'c3']),
        [peak, ridge, sender, dark],
        selfLabel: 'You',
        selfAt: here,
      );
      expect(r.stops.map((s) => s.label), ['Sam', 'Peak', 'Ridge', 'You']);
      expect(r.stops.map((s) => s.role), [
        StopRole.origin,
        StopRole.hop,
        StopRole.hop,
        StopRole.self,
      ]);
      expect(r.text, 'Sam → Peak → Ridge → You');
      expect(r.drawable, isTrue);
      expect(r.heardFrom!.label, 'Ridge');
    });

    test('hops with no position stay in the route but off the map', () {
      final r = buildTrafficRoute(
        packet(
          origin: const HopId('ee', HopMatch.prefix),
          hops: ['a1', 'b2', 'c3'],
        ),
        [peak, ridge, sender, dark],
        selfLabel: 'You',
        selfAt: here,
      );
      expect(r.stops.map((s) => s.label), [
        'Sam',
        'Peak',
        'Dark Hill',
        'Ridge',
        'You',
      ]);
      expect(r.onMap.map((s) => s.label), ['Sam', 'Peak', 'Ridge', 'You']);
      expect(r.offMap.map((s) => s.label), ['Dark Hill']);
    });

    test('unknown hashes show as short IDs and are skipped on the map', () {
      final r = buildTrafficRoute(
        packet(hops: ['a1', '7f']),
        [peak],
        selfLabel: 'You',
        selfAt: here,
      );
      expect(r.stops.map((s) => s.label), ['Peak', '7F', 'You']);
      expect(r.offMap.map((s) => s.label), ['7F']);
      expect(r.onMap.length, 2);
    });

    test('only nodes the same radio knows are matched', () {
      final elsewhere = Node(
        key: NodeKey.meshcore('a1'.padRight(64, '9')),
        radioId: RadioId.meshcore('bb' * 32),
        name: 'Other radio',
        position: const GeoPoint(1, 1),
      );
      final r = buildTrafficRoute(packet(hops: ['a1']), [
        elsewhere,
      ], selfLabel: 'You');
      expect(r.stops.first.label, 'A1');
      expect(r.drawable, isFalse);
    });

    test('an ambiguous hash picks the repeater nearest the last stop', () {
      final far = mcNode('a1ff', 'Far Peak', at: const GeoPoint(45, -100));
      final r = buildTrafficRoute(
        packet(origin: const HopId('ee', HopMatch.prefix), hops: ['a1']),
        [peak, far, sender],
        selfLabel: 'You',
        selfAt: here,
        naming: HopNaming(),
        now: t0,
      );
      expect(r.stops[1].label, 'Peak');
    });

    test('without naming an ambiguous hash stays unnamed', () {
      final twin = mcNode('a1ff', 'Twin', at: const GeoPoint(39.2, -77.2));
      final r = buildTrafficRoute(packet(hops: ['a1']), [
        peak,
        twin,
      ], selfLabel: 'You');
      expect(r.stops.first.label, 'A1');
    });

    test("an advert's own location places an unknown sender", () {
      final p = HeardPacket(
        time: t0,
        radioId: mc,
        kind: TrafficKind.advert,
        label: 'Advert',
        origin: HopId('dd' * 32, HopMatch.key),
        originName: 'New Node',
        originAt: const GeoPoint(39.4, -77.4),
      );
      final r = buildTrafficRoute(p, const [], selfLabel: 'You', selfAt: here);
      expect(r.text, 'New Node → You');
      expect(r.drawable, isTrue);
      expect(r.offMap, isEmpty);
    });

    test('our radio without a position leaves nothing to draw', () {
      final r = buildTrafficRoute(packet(hops: ['a1']), [
        peak,
      ], selfLabel: 'You');
      expect(r.drawable, isFalse);
      expect(r.offMap, isEmpty, reason: 'our own radio is not listed');
    });
  });

  group('Meshtastic packets', () {
    final origin = mtNode(0x11223344, 'Ranger', at: const GeoPoint(45, -121));
    final relay = mtNode(
      0x0badca5e,
      'Ridge Relay',
      at: const GeoPoint(45.1, -121),
    );
    final middle = mtNode(0x55667788, 'Mid', at: const GeoPoint(45.2, -121));

    test('the relay byte names the last hop', () {
      final p = heardMeshtastic(
        const MeshPacket(
          from: 0x11223344,
          to: broadcastNode,
          id: 1,
          hopStart: 3,
          hopLimit: 1,
          relayNode: 0x5e,
          rxSnr: 6.25,
          rxRssi: -101,
        ),
        radioId: mt,
        time: t0,
        label: 'Text',
      );
      expect(p.kind, TrafficKind.path); // not decoded
      expect(p.hopCount, 2);
      expect(p.hops, const [HopId('5e', HopMatch.lastByte)]);
      final r = buildTrafficRoute(
        p,
        [origin, relay, middle],
        selfLabel: 'You',
        selfAt: const GeoPoint(45.3, -121),
      );
      expect(r.text, 'Ranger → Ridge Relay → You');
      expect(r.heardFrom!.label, 'Ridge Relay');
    });

    test('a packet heard straight from its sender has no hops', () {
      final p = heardMeshtastic(
        MeshPacket(
          from: 0x11223344,
          to: 0x0000aaaa,
          id: 2,
          hopStart: 3,
          hopLimit: 3,
          relayNode: 0x44,
          decoded: DataPayload(
            portnum: PortNum.textMessage,
            payload: Uint8List(0),
          ),
        ),
        radioId: mt,
        time: t0,
        label: 'Text',
      );
      expect(p.kind, TrafficKind.direct);
      expect(p.hops, isEmpty);
      expect(p.hopCount, 0);
    });

    test('a traceroute draws its full route', () {
      final w = ProtoWriter()
        ..fixed32(1, 0x55667788, always: true)
        ..fixed32(1, 0x0badca5e, always: true);
      final p = heardMeshtastic(
        MeshPacket(
          from: 0x11223344,
          to: broadcastNode,
          id: 3,
          decoded: DataPayload(
            portnum: PortNum.traceroute,
            payload: w.toBytes(),
          ),
        ),
        radioId: mt,
        time: t0,
        label: 'Traceroute',
      );
      expect(p.kind, TrafficKind.trace);
      final r = buildTrafficRoute(
        p,
        [origin, relay, middle],
        selfLabel: 'You',
        selfAt: const GeoPoint(45.3, -121),
      );
      expect(r.text, 'Ranger → Mid → Ridge Relay → You');
      expect(r.onMap.length, 4);
    });
  });

  group('traffic log', () {
    HeardPacket p(int i) => HeardPacket(
      time: t0.add(Duration(seconds: i)),
      radioId: mc,
      kind: TrafficKind.advert,
      label: '$i',
    );

    test('keeps the newest and reports what is new since a count', () {
      final log = TrafficLog(capacity: 3);
      var heard = 0;
      log.addListener(() => heard++);
      for (var i = 0; i < 5; i++) {
        log.add(p(i));
      }
      expect(heard, 5);
      expect(log.count, 5);
      expect(log.recent.map((e) => e.label), ['2', '3', '4']);
      expect(log.since(3).map((e) => e.label), ['3', '4']);
      expect(log.since(0).length, 3);
      expect(log.since(5), isEmpty);
    });
  });
}
