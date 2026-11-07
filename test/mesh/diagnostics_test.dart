import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/meshcore/raw_packet.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

final t0 = DateTime.utc(2026, 11, 7, 12);
final mc = RadioId.meshcore('aa' * 32);
final mt = RadioId.meshtastic(1);

Message failed(Conversation c, String reason) => Message(
  conversation: c,
  text: 'hi',
  outgoing: true,
  sentAt: t0,
  receivedAt: t0,
  delivery: Failed(reason),
);

void main() {
  group('MeshCore stats and trace frames', () {
    test('radio stats keep a negative noise floor', () {
      final w = ByteWriter()
        ..u8(24)
        ..u8(1)
        ..bytes([0x8a, 0xff]) // -118 little-endian
        ..u8((-96) & 0xff)
        ..u8(26)
        ..u32(120)
        ..u32(3600);
      final f = decodeFrame(w.toBytes()) as RadioStatsFrame;
      expect(f.noiseFloor, -118);
      expect(f.lastRssi, -96);
      expect(f.lastSnr, 6.5);
      expect(f.txAirSeconds, 120);
      expect(f.rxAirSeconds, 3600);
    });

    test('packet and core stats', () {
      final p = ByteWriter()
        ..u8(24)
        ..u8(2);
      for (var i = 1; i <= 7; i++) {
        p.u32(i);
      }
      final ps = decodeFrame(p.toBytes()) as PacketStatsFrame;
      expect(ps.receiveErrors, 7);
      final c =
          decodeFrame(
                (ByteWriter()
                      ..u8(24)
                      ..u8(0)
                      ..bytes([0x10, 0x0e])
                      ..u32(86400)
                      ..bytes([0, 0])
                      ..u8(2))
                    .toBytes(),
              )
              as CoreStatsFrame;
      expect(c.batteryMv, 3600);
      expect(c.queueLength, 2);
    });

    test('trace command and its answer', () {
      expect(
        toHex(MeshCoreCommands.sendTracePath(tag: 1, path: [0xa1, 0xb2, 0xa1])),
        '24'
        '01000000'
        '00000000'
        '00'
        'a1b2a1',
      );
      expect(
        () => MeshCoreCommands.sendTracePath(
          tag: 1,
          path: [1, 2, 3],
          hashSize: 2,
        ),
        throwsArgumentError,
      );
      final push = ByteWriter()
        ..u8(0x89)
        ..u8(0)
        ..u8(3)
        ..u8(0)
        ..u32(77)
        ..u32(0)
        ..bytes([0xa1, 0xb2, 0xa1])
        ..bytes([20, (-12) & 0xff, 8])
        ..u8(4);
      final f = decodeFrame(push.toBytes()) as TraceDataPush;
      expect(f.tag, 77);
      expect(f.hopSnrs, [5.0, -3.0, 2.0]);
      expect(f.finalSnr, 1.0);
      expect(f.isPush, isTrue);
    });

    test('raw packets: route, payload, path and transport codes', () {
      // flood advert, 2 hops of 1-byte hashes
      final advert = MeshCorePacketInfo.parse(
        Uint8List.fromList([0x11, 0x02, 0xa1, 0xb2, 1, 2, 3, 4, 5]),
      )!;
      expect(advert.route, MeshCoreRoute.flood);
      expect(advert.payload, MeshCorePayload.advert);
      expect(advert.hops, 2);
      expect(advert.pathText, 'a1 b2');
      expect(advert.payloadLength, 5);
      expect(advert.isFlood, isTrue);

      // transport-direct text with 2-byte hashes after 4 transport bytes
      final dm = MeshCorePacketInfo.parse(
        Uint8List.fromList([0x0b, 9, 9, 9, 9, 0x41, 0xab, 0xcd, 7, 7]),
      )!;
      expect(dm.route, MeshCoreRoute.transportDirect);
      expect(dm.payload, MeshCorePayload.text);
      expect(dm.hashSize, 2);
      expect(dm.pathText, 'abcd');
      expect(dm.isFlood, isFalse);

      expect(MeshCorePacketInfo.parse(Uint8List.fromList([0x11])), isNull);
      expect(
        MeshCorePacketInfo.parse(Uint8List.fromList([0x11, 0x05, 1])),
        isNull,
      );
      expect(
        MeshCorePacketInfo.parse(Uint8List.fromList([0x11, 0xc1, 1])),
        isNull,
      );
    });
  });

  group('Meshtastic telemetry and traceroute', () {
    int bits(double v) => (ByteData(
      4,
    )..setFloat32(0, v, Endian.little)).getUint32(0, Endian.little);

    test('local stats inside telemetry', () {
      final local =
          (ProtoWriter()
                ..fixed32(2, bits(23.5))
                ..fixed32(3, bits(1.25))
                ..uint(5, 900)
                ..uint(15, -112))
              .toBytes();
      final t = Telemetry.decode((ProtoWriter()..bytes(6, local)).toBytes());
      expect(t.local!.channelUtilization, 23.5);
      expect(t.local!.airUtilTx, 1.25);
      expect(t.local!.packetsRx, 900);
      expect(t.local!.noiseFloor, -112);
    });

    test('route discovery with packed fields and unknown SNR', () {
      final route = ByteData(8)
        ..setUint32(0, 0x11, Endian.little)
        ..setUint32(4, 0x22, Endian.little);
      final snrs = <int>[24, -8, -128];
      final w = ProtoWriter()
        ..bytes(1, route.buffer.asUint8List())
        ..bytes(2, [
          for (final s in snrs)
            ...((ProtoWriter()..uint(1, s, always: true)).toBytes().sublist(1)),
        ]);
      final r = RouteDiscovery.decode(w.toBytes());
      expect(r.route, [0x11, 0x22]);
      expect(r.snrTowards, [6.0, -2.0, null]);
      expect(r.routeBack, isEmpty);
    });
  });

  group('packet log and samples', () {
    PacketLogEntry e(String k) =>
        PacketLogEntry(time: t0, protocol: RadioProtocol.meshcore, kind: k);

    test('keeps the newest, pauses and counts what it missed', () {
      final log = PacketLog(capacity: 2);
      log
        ..add(e('a'))
        ..add(e('b'))
        ..add(e('c'));
      expect(log.entries.map((x) => x.kind), ['b', 'c']);
      log.paused = true;
      log.add(e('d'));
      expect(log.entries.map((x) => x.kind), ['b', 'c']);
      expect(log.missedWhilePaused, 1);
      log.clear();
      expect(log.entries, isEmpty);
      expect(log.missedWhilePaused, 0);
    });

    test('samples keep the newest readings', () {
      final s = RadioSamples(capacity: 2);
      for (var i = 0; i < 3; i++) {
        s.add(RadioSample(time: t0, noiseFloor: -110 - i));
      }
      expect(s.samples.map((x) => x.noiseFloor), [-111, -112]);
      expect(s.latest!.noiseFloor, -112);
    });
  });

  group('delivery hints', () {
    final peerKey = NodeKey.meshcore('ab' * 32);
    final dm = DirectConversation(mc, peerKey);

    test('MeshCore: old, unrouted, needs contact', () {
      final n = Node(
        key: peerKey,
        radioId: mc,
        name: 'Sam',
        lastHeard: t0.subtract(const Duration(days: 3)),
        path: const PathFacts(route: RouteKind.flood),
      );
      expect(
        diagnoseDelivery(
          failed(dm, 'No acknowledgement after 5 tries'),
          n,
          now: t0,
        ),
        [
          DeliveryHint.notHeardRecently,
          DeliveryHint.noRoute,
          DeliveryHint.needsYourContact,
        ],
      );
    });

    test('long weak route', () {
      final n = Node(
        key: peerKey,
        radioId: mc,
        name: 'Sam',
        lastHeard: t0,
        path: const PathFacts(hops: 5, snr: -9, route: RouteKind.direct),
      );
      final hints = diagnoseDelivery(failed(dm, 'x'), n, now: t0);
      expect(
        hints,
        containsAll([DeliveryHint.longRoute, DeliveryHint.weakSignal]),
      );
      expect(hints, isNot(contains(DeliveryHint.noRoute)));
    });

    test('Meshtastic unknown key and busy radio', () {
      final key = NodeKey.meshtastic(9);
      final n = Node(key: key, radioId: mt, name: 'R', lastHeard: t0);
      final c = DirectConversation(mt, key);
      expect(
        diagnoseDelivery(failed(c, "The node's key is unknown"), n, now: t0),
        [DeliveryHint.unknownKey],
      );
      expect(
        diagnoseDelivery(
          failed(c, 'Radio duty-cycle limit reached'),
          n,
          now: t0,
        ),
        [DeliveryHint.radioBusy],
      );
    });

    test('nothing to say for delivered or received messages', () {
      final ok = failed(dm, 'x').withDelivery(const Delivered());
      expect(diagnoseDelivery(ok, null), isEmpty);
    });
  });

  test('line of sight over 10 km at 915 MHz', () {
    const a = GeoPoint(45.0, -122.0);
    // About 10 km due north.
    const b = GeoPoint(45.0899322, -122.0);
    final los = LineOfSight.between(a, b, 915);
    expect(los.distanceKm, closeTo(10, 0.01));
    expect(los.fresnelM, closeTo(28.6, 0.1));
    expect(los.earthBulgeM, closeTo(1.47, 0.01));
    expect(los.clearanceM, closeTo(1.47 + 0.6 * 28.6, 0.1));
  });
}
