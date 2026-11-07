import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/connection_log.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

import '../support/scripted_meshtastic.dart';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('protobuf wire format', () {
    test('round-trips varints, negatives, fixed32, floats and strings', () {
      final w = ProtoWriter()
        ..uint(1, 300)
        ..uint(2, -97)
        ..fixed32(3, 0xdeadbeef)
        ..fixed32(
          4,
          (ByteData(
            4,
          )..setFloat32(0, 6.25, Endian.little)).getUint32(0, Endian.little),
        )
        ..string(5, 'héllo')
        ..boolean(6, false)
        ..uint(7, 0);
      final f = readFields(w.toBytes());
      expect(f.map((x) => x.number), [
        1,
        2,
        3,
        4,
        5,
      ], reason: 'defaults skipped');
      expect(f[0].asInt, 300);
      expect(f[1].asInt32, -97);
      expect(f[2].asInt, 0xdeadbeef);
      expect(f[3].asFloat, 6.25);
      expect(f[4].asString, 'héllo');
    });

    test('known encodings', () {
      expect((ProtoWriter()..uint(1, 150)).toBytes(), [0x08, 0x96, 0x01]);
      expect((ProtoWriter()..uint(1, 1)).toBytes(), [0x08, 0x01]);
      const zz = ProtoField(1, WireType.varint, 3);
      expect(zz.asSint32, -2);
      const neg = ProtoField(1, WireType.fixed32, 0xfffffffe);
      expect(neg.asSfixed32, -2);
    });

    test('rejects truncated data', () {
      expect(
        () => readFields(Uint8List.fromList([0x0a, 0x05, 1])),
        throwsA(isA<ProtobufException>()),
      );
      expect(
        () => readFields(Uint8List.fromList([0x08, 0x80])),
        throwsA(isA<ProtobufException>()),
      );
    });
  });

  group('serial/TCP framing', () {
    test('wraps with 0x94 0xC3 and a big-endian length', () {
      expect(wrapMeshtasticFrame(Uint8List.fromList([0x18, 0x01])), [
        0x94,
        0xc3,
        0,
        2,
        0x18,
        0x01,
      ]);
      expect(() => wrapMeshtasticFrame(Uint8List(513)), throwsArgumentError);
    });

    test('decoder splits frames from console text', () {
      final d = MeshtasticFrameDecoder();
      final frames = <Uint8List>[
        ...d.add('INFO | boot\r\n'.codeUnits),
        ...d.add([0x94]),
        ...d.add([0xc3, 0, 3, 1, 2]),
        ...d.add([3, ...'DEBUG | x\n'.codeUnits, 0x94, 0xc3, 0, 1, 9]),
      ];
      expect(frames, [
        [1, 2, 3],
        [9],
      ]);
      expect(d.consoleLines, ['INFO | boot', 'DEBUG | x']);
    });

    test('impossible lengths are skipped', () {
      final d = MeshtasticFrameDecoder();
      expect(d.add([0x94, 0xc3, 0xff, 0xff, 0x94, 0xc3, 0, 1, 7]), [
        [7],
      ]);
    });
  });

  group('messages', () {
    test('MeshPacket keeps path facts', () {
      final from = FromRadio.decode(
        NodeFrames.packet(
          from: 0x11,
          to: broadcastNode,
          portnum: PortNum.textMessage,
          payload: 'hi'.codeUnits,
          viaMqtt: true,
        ),
      );
      final p = (from as PacketFromRadio).packet;
      expect(p.from, 0x11);
      expect(p.isBroadcast, isTrue);
      expect(p.rxSnr, 7.5);
      expect(p.rxRssi, -97);
      expect(p.hopsTaken, 2);
      expect(p.viaMqtt, isTrue);
      expect(p.decoded!.portnum, PortNum.textMessage);
    });

    test('ToRadio packet leaves from and hop limit to the node', () {
      final bytes = ToRadio.packet(
        MeshPacket(
          from: 0,
          to: 0x0badcafe,
          id: 42,
          channel: 1,
          wantAck: true,
          decoded: DataPayload(
            portnum: PortNum.textMessage,
            payload: textPayload('yo'),
          ),
        ),
      );
      final sent = SentToRadio(bytes).packet!;
      expect(sent.to, 0x0badcafe);
      expect(sent.from, 0);
      expect(sent.hopLimit, 0);
      expect(sent.id, 42);
      expect(sent.channel, 1);
      expect(sent.wantAck, isTrue);
      expect(String.fromCharCodes(sent.decoded!.payload), 'yo');
    });

    test('node info, channel and metadata', () {
      final n =
          (FromRadio.decode(
                    NodeFrames.nodeInfo(
                      0x0badcafe,
                      'Ridge Relay',
                      hops: 0,
                      withPosition: true,
                    ),
                  )
                  as NodeInfoFromRadio)
              .node;
      expect(n.user!.longName, 'Ridge Relay');
      expect(n.user!.id, '!0badcafe');
      expect(n.hopsAway, 0, reason: 'zero is meaningful: a neighbour');
      expect(n.position!.latitude, closeTo(45.5, 1e-6));
      expect(n.position!.longitude, closeTo(-122.6, 1e-6));
      expect(n.snr, 6.25);

      final c =
          (FromRadio.decode(NodeFrames.channel(1, 'Trail', role: 2))
                  as ChannelFromRadio)
              .channel;
      expect(c.name, 'Trail');
      expect(c.role, ChannelRole.secondary);

      final m =
          (FromRadio.decode(NodeFrames.metadata('2.8.2.d5f1619'))
                  as MetadataFromRadio)
              .metadata;
      expect(m.firmwareVersion, '2.8.2.d5f1619');
      expect(m.hasPkc, isTrue);
    });

    test('text payload limit is 233 bytes', () {
      expect(textPayload('a' * 233).length, 233);
      expect(() => textPayload('a' * 234), throwsArgumentError);
      expect(() => textPayload(''), throwsArgumentError);
    });
  });

  group('firmware gate', () {
    test('versions compare numerically', () {
      expect(
        MeshtasticVersion.tryParse('2.4.9')! < MeshtasticFirmware.minimum,
        isTrue,
      );
      expect(MeshtasticFirmware.isSupported('2.10.0.abc'), isTrue);
      expect(MeshtasticFirmware.isSupported('2.5.0'), isTrue);
      expect(MeshtasticFirmware.isSupported('2.4.3.91d6612'), isFalse);
      expect(MeshtasticFirmware.isSupported(''), isFalse);
    });
  });

  for (final framed in [true, false]) {
    group(framed ? 'session over Bluetooth' : 'session over USB/TCP', () {
      late ScriptedMeshtasticLink link;
      late MeshtasticSession session;

      setUp(() async {
        link = ScriptedMeshtasticLink(framed: framed);
        await link.open();
        session = MeshtasticSession(link);
      });

      tearDown(() => session.dispose());

      test('handshake downloads the config', () async {
        final texts = <MeshtasticText>[];
        session.texts.listen(texts.add);
        final c = await session.handshake();
        expect(c.myInfo.nodeNum, 0xa1b2c3d4);
        expect(session.myNodeNum, 0xa1b2c3d4);
        expect(c.metadata!.firmwareVersion, startsWith('2.8.2'));
        expect(c.nodes.keys, containsAll([0xa1b2c3d4, 0x0badcafe]));
        expect(c.self!.user!.longName, 'Base Camp');
        expect(c.channels.map((ch) => ch.index), [0, 1]);
        expect(c.configSections, 2);
        expect(link.sent.first.wantConfig, isNotNull);
        await settle();
        expect(texts.single.text, 'early', reason: 'traffic during config');
        if (!framed) {
          expect(link.raw.first.every((b) => b == 0xc3), isTrue);
        }
      });

      test('direct message: queued, then delivered by the recipient', () async {
        await session.handshake();
        link.onPacket = (p) => [
          NodeFrames.routing(from: p.to, to: 0xa1b2c3d4, requestId: p.id),
        ];
        final updates = <DeliveryUpdate>[];
        session.deliveries.listen(updates.add);
        final id = await session.sendText('hello', to: 0x0badcafe);
        await settle();
        expect(updates.map((u) => u.status), [
          DeliveryStatus.queued,
          DeliveryStatus.delivered,
        ]);
        expect(updates.every((u) => u.packetId == id), isTrue);
        final sent = link.sent.last.packet!;
        expect(sent.to, 0x0badcafe);
        expect(sent.wantAck, isTrue);
      });
    });
  }

  group('session behaviour', () {
    late ScriptedMeshtasticLink link;
    late MeshtasticSession session;
    late ConnectionLog log;

    Future<void> start({
      String firmware = '2.8.2.d5f1619',
      bool meta = true,
    }) async {
      link = ScriptedMeshtasticLink(firmware: firmware, sendMetadata: meta);
      await link.open();
      log = ConnectionLog();
      session = MeshtasticSession(
        link,
        log: log,
        heartbeatInterval: const Duration(milliseconds: 20),
        configTimeout: const Duration(milliseconds: 300),
      );
    }

    tearDown(() => session.dispose());

    test('old firmware is refused before anything is sent', () async {
      await start(firmware: '2.3.15.deb7c27');
      await expectLater(
        session.handshake(),
        throwsA(
          isA<UnsupportedMeshtasticFirmware>().having(
            (e) => e.message,
            'message',
            contains('2.3.15'),
          ),
        ),
      );
      expect(link.sent.where((s) => s.packet != null), isEmpty);
      expect(log.export(), contains('not supported'));
    });

    test('missing metadata is treated as too old', () async {
      await start(meta: false);
      await expectLater(
        session.handshake(),
        throwsA(isA<UnsupportedMeshtasticFirmware>()),
      );
    });

    test('broadcast ack from our own node means relayed', () async {
      await start();
      await session.handshake();
      link.onPacket = (p) => [
        NodeFrames.routing(from: 0xa1b2c3d4, to: 0xa1b2c3d4, requestId: p.id),
      ];
      final updates = <DeliveryUpdate>[];
      session.deliveries.listen(updates.add);
      await session.sendText('hi all', channel: 1);
      await settle();
      expect(updates.last.status, DeliveryStatus.relayed);
    });

    test('routing errors become failures with a reason', () async {
      await start();
      await session.handshake();
      link.onPacket = (p) => [
        NodeFrames.routing(
          from: 0xa1b2c3d4,
          to: 0xa1b2c3d4,
          requestId: p.id,
          error: 5,
        ),
      ];
      final updates = <DeliveryUpdate>[];
      session.deliveries.listen(updates.add);
      await session.sendText('anyone?', to: 0x0badcafe);
      await settle();
      expect(updates.last.status, DeliveryStatus.failed);
      expect(updates.last.error, RoutingError.maxRetransmit);
      expect(updates.last.error!.message, contains('No acknowledgement'));
    });

    test('incoming texts carry path facts and direct flag', () async {
      await start();
      await session.handshake();
      final texts = <MeshtasticText>[];
      session.texts.listen(texts.add);
      link.push(
        NodeFrames.text(from: 0x0badcafe, to: 0xa1b2c3d4, text: 'psst'),
      );
      link.push(
        NodeFrames.text(from: 0xa1b2c3d4, to: broadcastNode, text: 'me'),
      );
      await settle();
      final t = texts.single;
      expect(t.text, 'psst');
      expect(t.isDirect, isTrue);
      expect(t.hops, 2);
      expect(t.rssi, -97);
    });

    test('node info and position packets become node updates', () async {
      await start();
      await session.handshake();
      final updates = <NodeUpdate>[];
      session.nodes.listen(updates.add);
      link.push(
        NodeFrames.packet(
          from: 0x22,
          to: broadcastNode,
          portnum: PortNum.nodeInfo,
          payload: NodeFrames.user('!00000022', 'Summit', 'SU'),
        ),
      );
      link.push(
        NodeFrames.packet(
          from: 0x22,
          to: broadcastNode,
          portnum: PortNum.position,
          payload: NodeFrames.position(46.1, -121.7),
        ),
      );
      await settle();
      expect(updates[0].user!.shortName, 'SU');
      expect(updates[1].position!.latitude, closeTo(46.1, 1e-6));
    });

    test('sends heartbeats after the handshake', () async {
      await start();
      await session.handshake();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(
        link.sent.where((s) => s.heartbeat).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('config download that never ends times out', () async {
      await start();
      final quiet = MeshtasticSession(
        _SilentLink(),
        configTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(quiet.handshake(), throwsA(isA<MeshtasticTimeout>()));
      await quiet.dispose();
    });

    test('bad frames are logged, not fatal', () async {
      await start();
      session.attach();
      link.push(Uint8List.fromList([0x0a, 0x09, 1]));
      await settle();
      expect(log.export(), contains('bad frame'));
    });
  });
}

class _SilentLink extends BaseRadioLink {
  _SilentLink() {
    setState(LinkState.connected);
  }

  @override
  RadioProtocol get protocol => RadioProtocol.meshtastic;
  @override
  LinkKind get kind => LinkKind.bluetooth;
  @override
  String get label => 'silent';
  @override
  bool get deliversFrames => true;
  @override
  Future<void> open() async {}
  @override
  Future<void> send(Uint8List data) async {}
  @override
  Future<void> close() async {}
}
