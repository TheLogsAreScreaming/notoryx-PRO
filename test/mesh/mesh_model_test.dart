import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

final now = DateTime.utc(2026, 11, 7, 12);

void main() {
  group('ids', () {
    test('radio and node keys are protocol-scoped and stable', () {
      final a = RadioId.meshtastic(0xa1b2c3d4);
      expect(a.toString(), 'meshtastic:!a1b2c3d4');
      expect(RadioId.tryParse(a.toString()), a);
      expect(RadioId.tryParse('nope'), isNull);
      expect(RadioId.tryParse('lora:x'), isNull);

      final mc = NodeKey.meshcore('ABCDEF0123');
      final mt = NodeKey.meshtastic(0xabcdef01);
      expect(mc.native, 'abcdef0123');
      expect(mc.short, 'abcdef01');
      expect(mt.native, '!abcdef01');
      expect(mt.meshtasticNum, 0xabcdef01);
      expect(mc == NodeKey.meshcore('abcdef0123'), isTrue);
      expect(
        NodeKey.meshcore('a1b2c3d4') == NodeKey.meshtastic(0xa1b2c3d4),
        isFalse,
        reason: 'same digits on different meshes are different nodes',
      );
    });

    test('conversation keys separate radios', () {
      final mc = RadioId.meshcore('aa');
      final mt = RadioId.meshtastic(1);
      expect(ChannelConversation(mc, 0), ChannelConversation(mc, 0));
      expect(ChannelConversation(mc, 0) == ChannelConversation(mt, 0), isFalse);
      expect(
        DirectConversation(mt, NodeKey.meshtastic(2)).key,
        'meshtastic:!00000001/dm/meshtastic:!00000002',
      );
    });
  });

  group('MeshCore mapping', () {
    final radioId = RadioId.meshcore('10' * 32);
    final m = MeshCoreMapper(radioId, clock: () => now);

    test('radio from the handshake', () {
      final h = MeshCoreHandshake(
        self: decodeFrame(RadioFrames.selfInfo()) as SelfInfoFrame,
        device: decodeFrame(RadioFrames.deviceInfo()) as DeviceInfoFrame,
        clockSet: true,
      );
      final r = MeshCoreMapper.radio(h);
      expect(r.protocol, RadioProtocol.meshcore);
      expect(r.name, 'Ridge Base');
      expect(r.firmware, 'v1.18.0');
      expect(r.model, 'Heltec V3');
      expect(r.maxChannels, 40);
      expect(r.position!.latitude, closeTo(45.123456, 1e-9));
      expect(r.self.native, toHex(RadioFrames.key(0x10)));
    });

    test('contacts become nodes with kind, path and favourite', () {
      final repeater =
          decodeFrame(RadioFrames.contact(name: 'Peak', type: 2))
              as ContactFrame;
      final n = m.node(repeater);
      expect(n.kind, NodeKind.relay);
      expect(n.displayName, 'Peak');
      expect(n.isFavorite, isTrue);
      expect(n.path.hops, 2);
      expect(n.path.route, RouteKind.direct);
      expect(n.position!.longitude, closeTo(-121, 1e-9));
      expect(n.radioId, radioId);

      final flood = m.node(
        decodeFrame(RadioFrames.contact(pathLength: 0xff)) as ContactFrame,
      );
      expect(flood.path.route, RouteKind.flood);
      expect(flood.path.hops, isNull);
    });

    test('channel kinds: public key, hashtag, private, empty slot', () {
      ChannelInfoFrame info(int i, String name, String keyHex) =>
          ChannelInfoFrame(index: i, name: name, secret: fromHex(keyHex));
      expect(
        m.channel(info(0, 'Public', meshCorePublicKeyHex))!.kind,
        ChannelKind.public,
      );
      expect(
        m.channel(info(1, '#hiking', '9cd8fcf22a47333b591d96a2b848b73f'))!.kind,
        ChannelKind.hashtag,
      );
      expect(
        m.channel(info(2, 'Crew', '0102030405060708090a0b0c0d0e0f10'))!.kind,
        ChannelKind.private,
      );
      expect(m.channel(info(3, '', '00' * 16)), isNull);
    });

    test('direct message resolves the sender from the key prefix', () {
      final frame =
          decodeFrame(RadioFrames.contactMessageV3(text: 'hey'))
              as ContactMessageFrame;
      final full = NodeKey.meshcore(toHex(RadioFrames.key(0x40)));
      final msg = m.received(
        frame,
        findContact: (prefix) =>
            toHex(prefix) == full.native.substring(0, 12) ? full : null,
      )!;
      expect(msg.conversation, DirectConversation(radioId, full));
      expect(msg.from, full);
      expect(msg.text, 'hey');
      expect(msg.delivery, isA<Received>());
      expect(msg.path.route, RouteKind.direct);
      expect(msg.path.snr, -2.0);
      expect(
        msg.sentAt,
        DateTime.fromMillisecondsSinceEpoch(1762500200000, isUtc: true),
      );
    });

    test('unknown sender keeps the 6-byte prefix', () {
      final frame =
          decodeFrame(RadioFrames.contactMessageV3()) as ContactMessageFrame;
      final msg = m.received(frame)!;
      expect(msg.from!.native, hasLength(12));
    });

    test('channel message keeps the sender name and flood hops', () {
      final msg = m.received(
        decodeFrame(RadioFrames.channelMessageV3(channel: 2, text: 'Ann: hi')),
      )!;
      expect(msg.conversation, ChannelConversation(radioId, 2));
      expect(msg.senderName, 'Ann');
      expect(msg.text, 'hi');
      expect(msg.from, isNull);
      expect(msg.path.route, RouteKind.flood);
      expect(msg.path.hops, 3);
      expect(m.received(decodeFrame(RadioFrames.ok())), isNull);
    });

    test('delivery from SENT and SEND_CONFIRMED', () {
      final s = MeshCoreMapper.sent(
        decodeFrame(RadioFrames.sent(flood: true)) as SentFrame,
      );
      expect((s as Sent).flood, isTrue);
      final d = MeshCoreMapper.confirmed(
        decodeFrame(RadioFrames.sendConfirmed(1)) as SendConfirmedPush,
      );
      expect((d as Delivered).roundTrip, const Duration(milliseconds: 1450));
    });
  });

  group('Meshtastic mapping', () {
    final radioId = RadioId.meshtastic(0xa1b2c3d4);
    final m = MeshtasticMapper(radioId, clock: () => now);

    MeshNodeInfo node(Uint8List frame) =>
        (FromRadio.decode(frame) as NodeInfoFromRadio).node;

    test('radio from the config download', () {
      final r = MeshtasticMapper.radio(
        MeshtasticConfig(
          myInfo: const MyNodeInfo(nodeNum: 0xa1b2c3d4, pioEnv: 'heltec-v3'),
          metadata: const DeviceMetadata(firmwareVersion: '2.8.2.d5f1619'),
          nodes: {
            0xa1b2c3d4: node(NodeFrames.nodeInfo(0xa1b2c3d4, 'Base Camp')),
          },
          channels: const [],
          configSections: 0,
          moduleSections: 0,
        ),
      );
      expect(r.id, radioId);
      expect(r.name, 'Base Camp');
      expect(r.firmware, '2.8.2.d5f1619');
      expect(r.model, 'heltec-v3');
      expect(r.maxChannels, 8);
    });

    test('node database entries keep hops, SNR and position', () {
      final n = m.node(
        node(
          NodeFrames.nodeInfo(
            0x0badcafe,
            'Ridge Relay',
            hops: 1,
            withPosition: true,
          ),
        ),
      );
      expect(n.key, NodeKey.meshtastic(0x0badcafe));
      expect(n.name, 'Ridge Relay');
      expect(n.shortName, 'Ri');
      expect(n.path.hops, 1);
      expect(n.path.snr, 6.25);
      expect(n.position!.altitude, 1250);
      expect(
        n.lastHeard,
        DateTime.fromMillisecondsSinceEpoch(1762500000000, isUtc: true),
      );
    });

    test('roles map to kinds', () {
      expect(MeshtasticMapper.kindForRole(0), NodeKind.person);
      expect(MeshtasticMapper.kindForRole(2), NodeKind.relay);
      expect(MeshtasticMapper.kindForRole(4), NodeKind.relay);
      expect(MeshtasticMapper.kindForRole(5), NodeKind.sensor);
      expect(MeshtasticMapper.kindForRole(99), NodeKind.unknown);
    });

    test('mesh news updates a node without losing what it knew', () {
      final known = m.node(
        node(NodeFrames.nodeInfo(0x22, 'Summit', withPosition: true)),
      );
      final updated = m.update(
        known,
        const NodeUpdate(num: 0x22, snr: -3.5, hops: 4, viaMqtt: true),
      );
      expect(updated.name, 'Summit');
      expect(updated.position, known.position);
      expect(updated.path.hops, 4);
      expect(updated.path.viaMqtt, isTrue);
      expect(updated.lastHeard, now);

      final fresh = m.update(
        null,
        const NodeUpdate(
          num: 0x33,
          user: MeshUser(longName: 'New', shortName: 'NW', role: 2),
        ),
      );
      expect(fresh.name, 'New');
      expect(fresh.kind, NodeKind.relay);
    });

    test(
      'channels: default key is public, own key private, disabled hidden',
      () {
        MeshChannel ch(
          int i,
          ChannelRole role,
          List<int>? psk, [
          String name = '',
        ]) => MeshChannel(
          index: i,
          role: role,
          name: name,
          psk: psk == null ? null : Uint8List.fromList(psk),
        );
        final primary = m.channel(ch(0, ChannelRole.primary, [1]))!;
        expect(primary.kind, ChannelKind.public);
        expect(primary.isPrimary, isTrue);
        expect(primary.name, 'Primary');
        final team = m.channel(
          ch(1, ChannelRole.secondary, List.filled(32, 7), 'Team'),
        )!;
        expect(team.kind, ChannelKind.private);
        expect(team.name, 'Team');
        expect(m.channel(ch(2, ChannelRole.disabled, null)), isNull);
      },
    );

    test('texts keep path facts and reply info', () {
      final p =
          (FromRadio.decode(
                    NodeFrames.text(
                      from: 0x0badcafe,
                      to: 0xa1b2c3d4,
                      text: 'psst',
                    ),
                  )
                  as PacketFromRadio)
              .packet;
      final msg = m.received(
        MeshtasticText(packet: p, text: 'psst', isDirect: true),
      );
      expect(
        msg.conversation,
        DirectConversation(radioId, NodeKey.meshtastic(0x0badcafe)),
      );
      expect(msg.path, const PathFacts(hops: 2, snr: 7.5, rssi: -97));
      expect(msg.nativeId, 0x1234);
      expect(msg.replyTo, isNull);
      expect(
        msg.sentAt,
        DateTime.fromMillisecondsSinceEpoch(1762500300000, isUtc: true),
      );
      expect(msg.protocol, RadioProtocol.meshtastic);

      final channelMsg = m.received(
        MeshtasticText(packet: p, text: 'x', isDirect: false),
      );
      expect(channelMsg.conversation, ChannelConversation(radioId, 0));
    });

    test('delivery updates map to delivery states', () {
      expect(
        MeshtasticMapper.delivery(
          const DeliveryUpdate(1, DeliveryStatus.queued),
        ),
        isA<Sent>(),
      );
      expect(
        MeshtasticMapper.delivery(
          const DeliveryUpdate(1, DeliveryStatus.relayed),
        ),
        isA<Relayed>(),
      );
      expect(
        MeshtasticMapper.delivery(
          const DeliveryUpdate(1, DeliveryStatus.delivered),
        ),
        isA<Delivered>(),
      );
      final f = MeshtasticMapper.delivery(
        const DeliveryUpdate(
          1,
          DeliveryStatus.failed,
          error: RoutingError.noRoute,
        ),
      );
      expect((f as Failed).reason, 'No route to the node');
    });
  });

  test('withDelivery changes only the delivery', () {
    final msg = Message(
      conversation: ChannelConversation(RadioId.meshcore('aa'), 0),
      text: 'hi',
      outgoing: true,
      sentAt: now,
      receivedAt: now,
      delivery: const Pending(),
      nativeId: 5,
    );
    final sent = msg.withDelivery(const Sent());
    expect(sent.delivery, isA<Sent>());
    expect(sent.text, 'hi');
    expect(sent.nativeId, 5);
  });
}
