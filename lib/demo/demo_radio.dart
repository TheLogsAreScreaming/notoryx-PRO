import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../app/radio_target.dart';
import '../mesh/mesh.dart';
import '../meshcore/bytes.dart';
import '../meshcore/codes.dart';
import '../radio/connection_log.dart';
import '../radio/radio_link.dart';

/// Address the demo radio is "connected" at. Never contacted.
const demoHost = 'demo.notoryx';

/// The target that opens the demo radio.
const demoTarget = TcpTarget(host: demoHost, protocol: RadioProtocol.meshcore);

/// Hands out the demo radio instead of a real link. Nothing here can reach
/// Bluetooth, USB or the network.
class DemoLinks extends LinkFactory {
  DemoLinks({this.chatter = const Duration(seconds: 25), this.random});

  final Duration chatter;
  final Random? random;

  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) =>
      DemoMeshCoreLink(chatter: chatter, random: random);
}

class _Peer {
  const _Peer(this.seed, this.name, this.lat, this.lon, {this.type = 1});
  final int seed;
  final String name;
  final double lat;
  final double lon;

  /// 1 chat, 2 repeater, 3 room server.
  final int type;

  Uint8List get key =>
      Uint8List.fromList(List.generate(32, (i) => (seed * 7 + i * 13) & 0xff));
}

const _peers = [
  _Peer(1, 'Ridge Relay', 45.3735, -121.6959, type: 2),
  _Peer(2, 'Camp North', 45.3311, -121.7113),
  _Peer(3, 'Trailhead', 45.3012, -121.7550),
  _Peer(4, 'Fire Lookout', 45.4401, -121.6505, type: 2),
  _Peer(5, 'Valley Room', 45.2804, -121.6100, type: 3),
];

const _chatter = [
  'Ann: trail is clear to the second bridge',
  'Bo: water at the hut is running',
  'Cy: heading down before dark',
  'Ann: wind picking up on the ridge',
  'Dee: anyone near the lookout?',
];

const _replies = [
  'Copy that',
  'Got it, thanks',
  'On my way',
  'Signal is good here',
];

/// A pretend MeshCore companion radio that lives in the app.
///
/// It answers the app's commands the way a v1.18 companion does: its own
/// identity, five nearby nodes with positions, two channels, delivery
/// confirmations, replies to direct messages and some channel chatter.
/// Nothing is transmitted.
class DemoMeshCoreLink extends BaseRadioLink {
  DemoMeshCoreLink({this.chatter = const Duration(seconds: 25), Random? random})
    : _random = random ?? Random();

  /// How often someone on the public channel says something.
  final Duration chatter;
  final Random _random;
  final List<Uint8List> _queue = [];
  final List<Timer> _timers = [];
  int _ack = 0x10000;
  int _chatIndex = 0;

  @override
  RadioProtocol get protocol => RadioProtocol.meshcore;

  @override
  LinkKind get kind => LinkKind.tcp;

  @override
  String get label => 'Demo radio';

  @override
  bool get deliversFrames => true;

  @override
  Future<void> open() async {
    setState(LinkState.connected);
    _timers.add(Timer.periodic(chatter, (_) => _say()));
  }

  @override
  Future<void> close() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    setState(LinkState.disconnected);
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void _later(Duration d, void Function() run) {
    _timers.add(
      Timer(d, () {
        if (state == LinkState.connected) run();
      }),
    );
  }

  void _queueMessage(Uint8List frame) {
    _queue.add(frame);
    deliver(Uint8List.fromList([Push.messagesWaiting]));
  }

  void _say() {
    _queueMessage(_channelMessage(0, _chatter[_chatIndex++ % _chatter.length]));
  }

  @override
  Future<void> send(Uint8List data) async {
    requireConnected();
    final replies = _answer(data);
    scheduleMicrotask(() => replies.forEach(deliver));
  }

  List<Uint8List> _answer(Uint8List cmd) {
    switch (cmd.first) {
      case Cmd.appStart:
        return [_selfInfo()];
      case Cmd.deviceQuery:
        return [_deviceInfo()];
      case Cmd.setDeviceTime || Cmd.sendSelfAdvert || Cmd.resetPath:
        return [_ok()];
      case Cmd.getDeviceTime:
        return [
          (ByteWriter()
                ..u8(Resp.currentTime)
                ..u32(_now))
              .toBytes(),
        ];
      case Cmd.getContacts:
        return [
          (ByteWriter()
                ..u8(Resp.contactsStart)
                ..u32(_peers.length))
              .toBytes(),
          for (final p in _peers) _contact(p),
          (ByteWriter()
                ..u8(Resp.endOfContacts)
                ..u32(_now))
              .toBytes(),
        ];
      case Cmd.getChannel:
        return [_channel(cmd[1])];
      case Cmd.syncNextMessage:
        return [
          if (_queue.isNotEmpty)
            _queue.removeAt(0)
          else
            Uint8List.fromList([Resp.noMoreMessages]),
        ];
      case Cmd.getBattAndStorage:
        return [
          (ByteWriter()
                ..u8(Resp.battAndStorage)
                ..u8(3900 & 0xff)
                ..u8(3900 >> 8))
              .toBytes(),
        ];
      case Cmd.sendText:
        return _direct(cmd);
      case Cmd.sendChannelText:
        final channel = cmd[2];
        _later(Duration(seconds: 3 + _random.nextInt(4)), () {
          _queueMessage(
            _channelMessage(
              channel,
              'Bo: ${_replies[_random.nextInt(_replies.length)]}',
            ),
          );
        });
        return [_ok()];
      default:
        // Settings and admin aren't part of the demo.
        return [
          Uint8List.fromList([Resp.err, 1]),
        ];
    }
  }

  List<Uint8List> _direct(Uint8List cmd) {
    final prefix = cmd.sublist(7, 13);
    final ack = _ack++;
    _later(const Duration(milliseconds: 1500), () {
      deliver(
        (ByteWriter()
              ..u8(Push.sendConfirmed)
              ..u32(ack)
              ..u32(1400))
            .toBytes(),
      );
    });
    _later(Duration(seconds: 4 + _random.nextInt(4)), () {
      final w = ByteWriter()
        ..u8(Resp.contactMsgV3)
        ..u8((6 * 4) & 0xff)
        ..u8(0)
        ..u8(0)
        ..bytes(prefix)
        ..u8(1)
        ..u8(0)
        ..u32(_now)
        ..bytes(utf8.encode(_replies[_random.nextInt(_replies.length)]));
      _queueMessage(w.toBytes());
    });
    return [
      (ByteWriter()
            ..u8(Resp.sent)
            ..u8(0)
            ..u32(ack)
            ..u32(9000))
          .toBytes(),
    ];
  }

  static Uint8List _ok() => Uint8List.fromList([Resp.ok]);

  static Uint8List _selfInfo() =>
      (ByteWriter()
            ..u8(Resp.selfInfo)
            ..u8(1)
            ..u8(22)
            ..u8(30)
            ..bytes(List.generate(32, (i) => (0x51 + i * 3) & 0xff))
            ..i32(45330000)
            ..i32(-121720000)
            ..u8(0)
            ..u8(1)
            ..u8(0x15)
            ..u8(0)
            ..u32(910525)
            ..u32(62500)
            ..u8(7)
            ..u8(5)
            ..bytes(utf8.encode('Demo Radio')))
          .toBytes();

  static Uint8List _deviceInfo() =>
      (ByteWriter()
            ..u8(Resp.deviceInfo)
            ..u8(14)
            ..u8(175)
            ..u8(8)
            ..u32(0)
            ..fixedString('01 Nov 2026', 12)
            ..fixedString('Demo radio', 40)
            ..fixedString('v1.18.0', 20)
            ..u8(0)
            ..u8(1))
          .toBytes();

  static Uint8List _contact(_Peer p) {
    final path = Uint8List(64);
    return (ByteWriter()
          ..u8(Resp.contact)
          ..bytes(p.key)
          ..u8(p.type)
          ..u8(0)
          ..u8(p.type == 1 ? 1 : 0)
          ..bytes(path)
          ..fixedString(p.name, 32)
          ..u32(_now - 600)
          ..i32((p.lat * 1e6).round())
          ..i32((p.lon * 1e6).round())
          ..u32(_now - 600))
        .toBytes();
  }

  static Uint8List _channel(int index) {
    final (name, secret) = switch (index) {
      0 => ('Public', bytesOfHex(meshCorePublicKeyHex)),
      1 => ('#trail', ChannelInvite.hashtag('trail').secret),
      _ => ('', Uint8List(16)),
    };
    if (index >= 8) return Uint8List.fromList([Resp.err, 2]);
    return (ByteWriter()
          ..u8(Resp.channelInfo)
          ..u8(index)
          ..fixedString(name, 32)
          ..bytes(secret))
        .toBytes();
  }

  static Uint8List _channelMessage(int channel, String text) =>
      (ByteWriter()
            ..u8(Resp.channelMsgV3)
            ..u8((7 * 4) & 0xff)
            ..u8(0)
            ..u8(0)
            ..u8(channel)
            ..u8(1)
            ..u8(0)
            ..u32(_now)
            ..bytes(utf8.encode(text)))
          .toBytes();
}
