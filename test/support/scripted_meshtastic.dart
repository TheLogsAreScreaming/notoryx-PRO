import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

/// Builds `FromRadio` protobufs the way a node's firmware does.
abstract final class NodeFrames {
  static Uint8List _from(int field, List<int> inner, {int id = 0}) =>
      (ProtoWriter()
            ..uint(1, id)
            ..bytes(field, inner, always: true))
          .toBytes();

  static Uint8List myInfo(int num) => _from(
    3,
    (ProtoWriter()
          ..uint(1, num)
          ..uint(15, 2))
        .toBytes(),
  );

  static Uint8List metadata(String version) => _from(
    13,
    (ProtoWriter()
          ..string(1, version)
          ..boolean(5, true)
          ..uint(9, 43)
          ..boolean(11, true))
        .toBytes(),
  );

  static Uint8List user(String id, String longName, String shortName) =>
      (ProtoWriter()
            ..string(1, id)
            ..string(2, longName)
            ..string(3, shortName)
            ..uint(5, 43))
          .toBytes();

  static Uint8List position(double lat, double lon) =>
      (ProtoWriter()
            ..fixed32(1, (lat * 1e7).round())
            ..fixed32(2, (lon * 1e7).round())
            ..uint(3, 1250))
          .toBytes();

  static Uint8List nodeInfo(
    int num,
    String longName, {
    int? hops,
    bool withPosition = false,
  }) {
    final w = ProtoWriter()
      ..uint(1, num)
      ..bytes(2, user(nodeIdOf(num), longName, longName.substring(0, 2)));
    if (withPosition) w.bytes(3, position(45.5, -122.6));
    w
      ..fixed32(4, _floatBits(6.25))
      ..fixed32(5, 1762500000);
    if (hops != null) w.uint(9, hops, always: true);
    return _from(4, w.toBytes());
  }

  static Uint8List channel(int index, String name, {int role = 1}) {
    final settings =
        (ProtoWriter()
              ..bytes(2, [1])
              ..string(3, name))
            .toBytes();
    return _from(
      10,
      (ProtoWriter()
            ..uint(1, index)
            ..bytes(2, settings)
            ..uint(3, role))
          .toBytes(),
    );
  }

  static Uint8List config(int section) =>
      _from(5, (ProtoWriter()..bytes(section, [8, 1], always: true)).toBytes());

  static Uint8List complete(int nonce) =>
      (ProtoWriter()..uint(7, nonce, always: true)).toBytes();

  static Uint8List queueStatus(int packetId, {int result = 0}) => _from(
    11,
    (ProtoWriter()
          ..uint(1, result)
          ..uint(2, 15)
          ..uint(3, 16)
          ..uint(4, packetId))
        .toBytes(),
  );

  static Uint8List packet({
    required int from,
    required int to,
    required int portnum,
    required List<int> payload,
    int id = 0x1234,
    int channel = 0,
    int requestId = 0,
    double snr = 7.5,
    int rssi = -97,
    int hopStart = 3,
    int hopLimit = 1,
    bool viaMqtt = false,
  }) {
    final data =
        (ProtoWriter()
              ..uint(1, portnum)
              ..bytes(2, payload)
              ..fixed32(6, requestId))
            .toBytes();
    final p = ProtoWriter()
      ..fixed32(1, from)
      ..fixed32(2, to)
      ..uint(3, channel)
      ..bytes(4, data)
      ..fixed32(6, id)
      ..fixed32(7, 1762500300)
      ..fixed32(8, _floatBits(snr))
      ..uint(9, hopLimit)
      ..uint(12, rssi)
      ..boolean(14, viaMqtt)
      ..uint(15, hopStart);
    return _from(2, p.toBytes());
  }

  static Uint8List text({
    required int from,
    required int to,
    required String text,
    int channel = 0,
  }) => packet(
    from: from,
    to: to,
    channel: channel,
    portnum: PortNum.textMessage,
    payload: utf8.encode(text),
  );

  static Uint8List routing({
    required int from,
    required int to,
    required int requestId,
    int error = 0,
  }) => packet(
    from: from,
    to: to,
    portnum: PortNum.routing,
    requestId: requestId,
    payload: (ProtoWriter()..uint(3, error)).toBytes(),
  );

  static int _floatBits(double v) => (ByteData(
    4,
  )..setFloat32(0, v, Endian.little)).getUint32(0, Endian.little);
}

/// Decodes a `ToRadio` written by the app.
class SentToRadio {
  SentToRadio(Uint8List data) {
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          packet = MeshPacket.decode(f.asBytes);
        case 3:
          wantConfig = f.asInt;
        case 4:
          disconnect = f.asBool;
        case 7:
          heartbeat = true;
      }
    }
  }

  MeshPacket? packet;
  int? wantConfig;
  bool disconnect = false;
  bool heartbeat = false;
}

/// A fake Meshtastic node on a [RadioLink].
class ScriptedMeshtasticLink extends BaseRadioLink {
  ScriptedMeshtasticLink({
    this.framed = true,
    this.myNode = 0xa1b2c3d4,
    this.firmware = '2.8.2.d5f1619',
    this.sendMetadata = true,
  });

  final bool framed;
  final int myNode;
  String firmware;
  bool sendMetadata;

  /// `ToRadio` messages the app wrote, decoded.
  final List<SentToRadio> sent = [];

  /// Raw writes, for checking wrapping.
  final List<Uint8List> raw = [];

  /// Extra replies to each text packet.
  List<Uint8List> Function(MeshPacket p)? onPacket;

  @override
  RadioProtocol get protocol => RadioProtocol.meshtastic;

  @override
  LinkKind get kind => framed ? LinkKind.bluetooth : LinkKind.usb;

  @override
  String get label => 'node';

  @override
  bool get deliversFrames => framed;

  @override
  Future<void> open() async => setState(LinkState.connected);

  @override
  Future<void> close() async => setState(LinkState.disconnected);

  @override
  Future<void> send(Uint8List data) async {
    requireConnected();
    raw.add(data);
    if (!framed && data.every((b) => b == 0xc3)) return; // wake bytes
    final proto = framed ? data : _unwrap(data);
    final msg = SentToRadio(proto);
    sent.add(msg);
    final replies = <Uint8List>[];
    if (msg.wantConfig != null) {
      replies
        ..add(NodeFrames.myInfo(myNode))
        ..add(NodeFrames.text(from: 0x11, to: broadcastNode, text: 'early'))
        ..addAll([if (sendMetadata) NodeFrames.metadata(firmware)])
        ..add(NodeFrames.nodeInfo(myNode, 'Base Camp'))
        ..add(NodeFrames.nodeInfo(0x0badcafe, 'Ridge Relay', hops: 2))
        ..add(NodeFrames.channel(1, 'Trail', role: 2))
        ..add(NodeFrames.channel(0, ''))
        ..add(NodeFrames.config(1))
        ..add(NodeFrames.config(6))
        ..add(NodeFrames.complete(msg.wantConfig!));
    }
    if (msg.packet != null) {
      replies.add(NodeFrames.queueStatus(msg.packet!.id));
      replies.addAll(onPacket?.call(msg.packet!) ?? const []);
    }
    scheduleMicrotask(() => replies.forEach(push));
  }

  /// A frame from the node to the app.
  void push(Uint8List fromRadio) {
    if (framed) {
      deliver(fromRadio);
      return;
    }
    final wrapped = Uint8List.fromList([
      ...'DEBUG | ok\r\n'.codeUnits,
      ...wrapMeshtasticFrame(fromRadio),
    ]);
    final mid = wrapped.length ~/ 2;
    deliver(Uint8List.sublistView(wrapped, 0, mid));
    deliver(Uint8List.sublistView(wrapped, mid));
  }

  static Uint8List _unwrap(Uint8List data) {
    final length = (data[2] << 8) | data[3];
    if (data[0] != 0x94 || data[1] != 0xc3 || length != data.length - 4) {
      throw StateError('bad wrapping');
    }
    return Uint8List.sublistView(data, 4);
  }
}

/// A node's settings and admin handling, for a [ScriptedMeshtasticLink]'s
/// `onPacket`: answers get requests with a passkey and records changes.
class FakeAdminNode {
  FakeAdminNode(this.num, {this.answers = true});

  final int num;

  /// Whether it answers at all (a remote node without our admin key won't).
  bool answers;
  final passkey = Uint8List.fromList([9, 9, 9, 9]);

  /// Section bytes by kind.
  final sections = <SectionKind, Uint8List>{
    SectionKind.owner:
        (ProtoWriter()
              ..string(1, '!0badcafe')
              ..string(2, 'Ridge Relay')
              ..string(3, 'RR')
              ..uint(5, 43)
              ..bytes(8, List.filled(32, 7)))
            .toBytes(),
    SectionKind.device: (ProtoWriter()..uint(DeviceField.role, 0)).toBytes(),
    SectionKind.lora:
        (ProtoWriter()
              ..boolean(LoraField.usePreset, true)
              ..uint(LoraField.region, 1)
              ..uint(LoraField.hopLimit, 3)
              ..boolean(LoraField.txEnabled, true)
              ..fixed32(6, 0x3f800000) // frequency_offset 1.0
              ..string(200, 'future field'))
            .toBytes(),
    SectionKind.position:
        (ProtoWriter()
              ..uint(PositionField.broadcastSecs, 900)
              ..boolean(PositionField.smartBroadcast, true)
              ..uint(PositionField.gpsMode, 1))
            .toBytes(),
    SectionKind.telemetry:
        (ProtoWriter()..uint(TelemetryField.deviceInterval, 1800)).toBytes(),
  };

  /// Admin messages received: (field, body, passkey).
  final received = <(int, Uint8List, Uint8List)>[];

  /// Packets that carried them.
  final packets = <MeshPacket>[];

  List<Uint8List> call(MeshPacket p, {required int myNode}) {
    final data = p.decoded;
    if (data == null || data.portnum != PortNum.admin || p.to != num) {
      return const [];
    }
    packets.add(p);
    var field = 0;
    Object value = 0;
    var key = Uint8List(0);
    for (final f in readFields(data.payload)) {
      if (f.number == AdminField.sessionPasskey) {
        key = f.asBytes;
      } else {
        field = f.number;
        value = f.value;
      }
    }
    received.add((field, value is Uint8List ? value : Uint8List(0), key));
    if (!answers) return const [];
    Uint8List? answer;
    switch (field) {
      case AdminField.getOwnerRequest:
        answer =
            (ProtoWriter()..bytes(
                  AdminField.getOwnerResponse,
                  sections[SectionKind.owner]!,
                  always: true,
                ))
                .toBytes();
      case AdminField.getConfigRequest || AdminField.getModuleConfigRequest:
        final module = field == AdminField.getModuleConfigRequest;
        final kind = SectionKind.values.firstWhere(
          (k) =>
              k != SectionKind.owner &&
              k.module == module &&
              k.requestType == value,
        );
        final inner =
            (ProtoWriter()..bytes(
                  kind.field,
                  sections[kind] ?? Uint8List(0),
                  always: true,
                ))
                .toBytes();
        answer =
            (ProtoWriter()..bytes(
                  module
                      ? AdminField.getModuleConfigResponse
                      : AdminField.getConfigResponse,
                  inner,
                  always: true,
                ))
                .toBytes();
      case AdminField.getMetadataRequest:
        answer =
            (ProtoWriter()..bytes(
                  AdminField.getMetadataResponse,
                  (ProtoWriter()..string(1, '2.8.2')).toBytes(),
                  always: true,
                ))
                .toBytes();
      case AdminField.setFixedPosition:
        sections[SectionKind.position] =
            (ProtoWriter()..boolean(PositionField.fixedPosition, true))
                .toBytes();
      case AdminField.removeFixedPosition:
        sections[SectionKind.position] = Uint8List(0);
      case AdminField.setOwner:
        sections[SectionKind.owner] = value as Uint8List;
      case AdminField.setConfig || AdminField.setModuleConfig:
        final module = field == AdminField.setModuleConfig;
        final f = readFields(value as Uint8List).first;
        final kind = SectionKind.values.firstWhere(
          (k) =>
              k != SectionKind.owner &&
              k.module == module &&
              k.field == f.number,
        );
        sections[kind] = f.asBytes;
    }
    if (answer == null) return const [];
    final withKey =
        (ProtoWriter()
              ..field(readFields(answer).first)
              ..bytes(AdminField.sessionPasskey, passkey))
            .toBytes();
    return [
      NodeFrames.packet(
        from: num,
        to: myNode,
        portnum: PortNum.admin,
        payload: withKey,
        requestId: p.id,
      ),
    ];
  }

  /// The fields of the admin messages received, in order.
  List<int> get fields => [for (final r in received) r.$1];
}
