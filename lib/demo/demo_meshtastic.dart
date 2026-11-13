import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../meshtastic/meshtastic.dart';
import '../radio/radio_link.dart';

class _Node {
  const _Node(this.num, this.name, this.short, this.lat, this.lon);
  final int num;
  final String name;
  final String short;
  final double lat;
  final double lon;
}

const _me = _Node(0xd3a10001, 'Demo Base', 'DB', 45.3402, -121.7051);
const _nodes = [
  _Node(0xd3a10002, 'Summit Hut', 'SH', 45.3740, -121.6950),
  _Node(0xd3a10003, 'Lake Camp', 'LC', 45.3160, -121.7380),
  _Node(0xd3a10004, 'Ranger Truck', 'RT', 45.2950, -121.6800),
  _Node(0xd3a10005, 'Ridge Repeater', 'RR', 45.4100, -121.6620),
];

const _chatter = [
  'Summit Hut: weather turning, heading in',
  'Lake Camp: fish are biting',
  'Ranger Truck: road closed past mile 12',
  'Summit Hut: anyone copy?',
];

const _replies = ['Copy', 'Roger that', 'See you at camp', 'Loud and clear'];

/// A pretend Meshtastic node that lives in the app, answering the config
/// download, acknowledging messages and replying, like the MeshCore demo.
/// Nothing is transmitted. Settings and admin requests get no answer.
class DemoMeshtasticLink extends BaseRadioLink {
  DemoMeshtasticLink({
    this.chatter = const Duration(seconds: 30),
    Random? random,
  }) : _random = random ?? Random();

  final Duration chatter;
  final Random _random;
  final List<Timer> _timers = [];
  int _packetId = 0x5000;
  int _chatIndex = 0;

  @override
  RadioProtocol get protocol => RadioProtocol.meshtastic;

  @override
  LinkKind get kind => LinkKind.tcp;

  @override
  String get label => 'Demo radio';

  @override
  bool get deliversFrames => true;

  @override
  Future<void> open() async {
    setState(LinkState.connected);
    _timers.add(
      Timer.periodic(chatter, (_) {
        final text = _chatter[_chatIndex++ % _chatter.length];
        final from = _nodes[_chatIndex % _nodes.length];
        deliver(_text(from.num, broadcastNode, text.split(': ').last));
      }),
    );
  }

  @override
  Future<void> close() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    setState(LinkState.disconnected);
  }

  void _later(Duration d, void Function() run) {
    _timers.add(
      Timer(d, () {
        if (state == LinkState.connected) run();
      }),
    );
  }

  @override
  Future<void> send(Uint8List data) async {
    requireConnected();
    int? wantConfig;
    MeshPacket? packet;
    for (final f in readFields(data)) {
      if (f.number == 1) packet = MeshPacket.decode(f.asBytes);
      if (f.number == 3) wantConfig = f.asInt;
    }
    final replies = <Uint8List>[
      if (wantConfig != null) ..._config(wantConfig),
      if (packet != null) ..._answer(packet),
    ];
    scheduleMicrotask(() => replies.forEach(deliver));
  }

  List<Uint8List> _answer(MeshPacket p) {
    final out = [_queueStatus(p.id)];
    final data = p.decoded;
    if (data == null || data.portnum != PortNum.textMessage) return out;
    final direct = p.to != broadcastNode;
    if (direct && p.wantAck) {
      _later(const Duration(milliseconds: 1500), () {
        deliver(_routingAck(p.to, p.id));
      });
    }
    final replier = direct
        ? _nodes.where((n) => n.num == p.to).firstOrNull ?? _nodes.first
        : _nodes[_random.nextInt(_nodes.length)];
    _later(Duration(seconds: 3 + _random.nextInt(4)), () {
      deliver(
        _text(
          replier.num,
          direct ? _me.num : broadcastNode,
          _replies[_random.nextInt(_replies.length)],
          channel: direct ? 0 : p.channel,
        ),
      );
    });
    return out;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static Uint8List _from(int field, List<int> inner) =>
      (ProtoWriter()
            ..uint(1, 0)
            ..bytes(field, inner, always: true))
          .toBytes();

  static int _float(double v) => (ByteData(
    4,
  )..setFloat32(0, v, Endian.little)).getUint32(0, Endian.little);

  static List<int> _user(_Node n) =>
      (ProtoWriter()
            ..string(1, nodeIdOf(n.num))
            ..string(2, n.name)
            ..string(3, n.short)
            ..uint(5, 43))
          .toBytes();

  static List<int> _position(_Node n) =>
      (ProtoWriter()
            ..fixed32(1, (n.lat * 1e7).round())
            ..fixed32(2, (n.lon * 1e7).round())
            ..uint(3, 1200))
          .toBytes();

  static Uint8List _nodeInfo(_Node n, {int? hops}) {
    final w = ProtoWriter()
      ..uint(1, n.num)
      ..bytes(2, _user(n))
      ..bytes(3, _position(n))
      ..fixed32(4, _float(5.5))
      ..fixed32(5, _now() - 300);
    if (hops != null) w.uint(9, hops, always: true);
    return _from(4, w.toBytes());
  }

  static Uint8List _channel(int index, String name, List<int> psk, int role) =>
      _from(
        10,
        (ProtoWriter()
              ..uint(1, index)
              ..bytes(
                2,
                (ProtoWriter()
                      ..bytes(2, psk)
                      ..string(3, name))
                    .toBytes(),
              )
              ..uint(3, role))
            .toBytes(),
      );

  static List<Uint8List> _config(int nonce) => [
    _from(3, (ProtoWriter()..uint(1, _me.num)).toBytes()),
    _from(
      13,
      (ProtoWriter()
            ..string(1, '2.8.2.demo')
            ..boolean(5, true)
            ..uint(9, 43)
            ..boolean(11, true))
          .toBytes(),
    ),
    _nodeInfo(_me),
    for (final (i, n) in _nodes.indexed) _nodeInfo(n, hops: i % 3),
    _channel(0, '', [1], 1),
    _channel(1, 'Trail', List.generate(32, (i) => (i * 37 + 11) & 0xff), 2),
    _from(
      5,
      (ProtoWriter()
            ..bytes(1, (ProtoWriter()..uint(1, 0)).toBytes(), always: true))
          .toBytes(),
    ),
    _from(
      5,
      (ProtoWriter()..bytes(
            SectionKind.lora.field,
            (ProtoWriter()
                  ..boolean(LoraField.usePreset, true)
                  ..uint(LoraField.region, 1)
                  ..uint(LoraField.hopLimit, 3)
                  ..boolean(LoraField.txEnabled, true))
                .toBytes(),
            always: true,
          ))
          .toBytes(),
    ),
    (ProtoWriter()..uint(7, nonce, always: true)).toBytes(),
  ];

  static Uint8List _queueStatus(int id) => _from(
    11,
    (ProtoWriter()
          ..uint(1, 0)
          ..uint(2, 15)
          ..uint(3, 16)
          ..uint(4, id))
        .toBytes(),
  );

  Uint8List _packet(
    int from,
    int to,
    int portnum,
    List<int> payload, {
    int channel = 0,
    int requestId = 0,
  }) {
    final data =
        (ProtoWriter()
              ..uint(1, portnum)
              ..bytes(2, payload)
              ..fixed32(6, requestId))
            .toBytes();
    return _from(
      2,
      (ProtoWriter()
            ..fixed32(1, from)
            ..fixed32(2, to)
            ..uint(3, channel)
            ..bytes(4, data)
            ..fixed32(6, _packetId++)
            ..fixed32(7, _now())
            ..fixed32(8, _float(6.75))
            ..uint(9, 2)
            ..uint(12, -92)
            ..uint(15, 3))
          .toBytes(),
    );
  }

  Uint8List _text(int from, int to, String text, {int channel = 0}) => _packet(
    from,
    to,
    PortNum.textMessage,
    utf8.encode(text),
    channel: channel,
  );

  Uint8List _routingAck(int from, int requestId) => _packet(
    from,
    _me.num,
    PortNum.routing,
    (ProtoWriter()..uint(3, 0)).toBytes(),
    requestId: requestId,
  );
}
