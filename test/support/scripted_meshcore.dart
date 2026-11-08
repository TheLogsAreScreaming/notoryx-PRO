import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/stream_framing.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

/// Replies a fake radio gives to one command frame.
typedef Responder = List<Uint8List> Function(Uint8List command);

/// A [RadioLink] that answers commands like a MeshCore companion would.
///
/// With [framed] true it behaves like Bluetooth (one frame per event);
/// otherwise like USB/TCP, wrapping replies in `>` + length.
class ScriptedMeshCoreLink extends BaseRadioLink {
  ScriptedMeshCoreLink({this.framed = true, Responder? responder})
    : responder = responder ?? ((_) => const []);

  final bool framed;
  Responder responder;

  /// Command frames received, unwrapped.
  final List<Uint8List> commands = [];

  /// Raw bytes as the link received them.
  final List<Uint8List> raw = [];

  @override
  RadioProtocol get protocol => RadioProtocol.meshcore;

  @override
  LinkKind get kind => framed ? LinkKind.bluetooth : LinkKind.tcp;

  @override
  String get label => 'scripted';

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
    final frame = framed ? data : _unwrap(data);
    commands.add(frame);
    final replies = responder(frame);
    scheduleMicrotask(() {
      for (final r in replies) {
        push(r);
      }
    });
  }

  /// Sends a frame from the "radio" to the app.
  void push(Uint8List frame) {
    if (framed) {
      deliver(frame);
    } else {
      // Split in two to prove the decoder reassembles.
      final wrapped = Uint8List.fromList([
        0x3e,
        frame.length & 0xff,
        frame.length >> 8,
        ...frame,
      ]);
      final mid = wrapped.length ~/ 2;
      deliver(Uint8List.sublistView(wrapped, 0, mid));
      deliver(Uint8List.sublistView(wrapped, mid));
    }
  }

  static Uint8List _unwrap(Uint8List data) {
    expectWrapped(data);
    return Uint8List.sublistView(data, 3);
  }

  static void expectWrapped(Uint8List data) {
    final length = data[1] | (data[2] << 8);
    if (data[0] != 0x3c || length != data.length - 3) {
      throw StateError('bad outbound wrapping: ${toHex(data)}');
    }
  }

  /// Makes sure [wrapStreamFrame] stays in use for stream links.
  static Uint8List wrap(Uint8List f) => wrapStreamFrame(f);
}

/// Builders for frames a v1.18 companion sends, following the firmware.
abstract final class RadioFrames {
  static Uint8List ok([int? value]) {
    final w = ByteWriter()..u8(0);
    if (value != null) w.u32(value);
    return w.toBytes();
  }

  static Uint8List err(int code) => Uint8List.fromList([1, code]);

  static Uint8List key(int seed) =>
      Uint8List.fromList(List.generate(32, (i) => (seed + i) & 0xff));

  static Uint8List selfInfo({String name = 'Ridge Base'}) {
    final w = ByteWriter()
      ..u8(5)
      ..u8(1) // ADV_TYPE_CHAT
      ..u8(22)
      ..u8(30)
      ..bytes(key(0x10))
      ..i32(45123456)
      ..i32(-122654321)
      ..u8(0)
      ..u8(1)
      ..u8(0x15)
      ..u8(0)
      ..u32(910525)
      ..u32(62500)
      ..u8(7)
      ..u8(5)
      ..bytes(utf8.encode(name));
    return w.toBytes();
  }

  static Uint8List deviceInfo({int maxContacts = 350}) {
    final w = ByteWriter()
      ..u8(13)
      ..u8(14)
      ..u8(maxContacts ~/ 2)
      ..u8(40)
      ..u32(123456)
      ..fixedString('06 Oct 2026', 12)
      ..fixedString('Heltec V3', 40)
      ..fixedString('v1.18.0', 20)
      ..u8(0)
      ..u8(1);
    return w.toBytes();
  }

  static Uint8List contact({
    int code = 3,
    int seed = 0x40,
    String name = 'Alpha',
    int type = 1,
    int pathLength = 0x02,
    int lastModified = 1000,
    int flags = 1,
    int lastAdvert = 1762500000,
  }) {
    final path = Uint8List(64)
      ..[0] = 0xaa
      ..[1] = 0xbb;
    final w = ByteWriter()
      ..u8(code)
      ..bytes(key(seed))
      ..u8(type)
      ..u8(flags)
      ..u8(pathLength)
      ..bytes(path)
      ..fixedString(name, 32)
      ..u32(lastAdvert)
      ..i32(44500000)
      ..i32(-121000000)
      ..u32(lastModified);
    return w.toBytes();
  }

  static Uint8List contactsStart(int total) =>
      (ByteWriter()
            ..u8(2)
            ..u32(total))
          .toBytes();

  static Uint8List endOfContacts(int mark) =>
      (ByteWriter()
            ..u8(4)
            ..u32(mark))
          .toBytes();

  static Uint8List channelMessageV3({
    int channel = 0,
    String text = 'Bob: hello all',
    int snrTimes4 = 26,
  }) {
    final w = ByteWriter()
      ..u8(17)
      ..u8(snrTimes4 & 0xff)
      ..u8(0)
      ..u8(0)
      ..u8(channel)
      ..u8(3)
      ..u8(0)
      ..u32(1762500100)
      ..bytes(utf8.encode(text));
    return w.toBytes();
  }

  static Uint8List contactMessageV3({String text = 'hi', bool signed = false}) {
    final w = ByteWriter()
      ..u8(16)
      ..u8((-8) & 0xff)
      ..u8(0)
      ..u8(0)
      ..bytes(key(0x40).sublist(0, 6))
      ..u8(0xff)
      ..u8(signed ? 2 : 0)
      ..u32(1762500200);
    if (signed) w.bytes([1, 2, 3, 4]);
    w.bytes(utf8.encode(text));
    return w.toBytes();
  }

  static Uint8List sent({
    int ack = 0xdeadbeef,
    bool flood = false,
    int timeoutMs = 9000,
  }) =>
      (ByteWriter()
            ..u8(6)
            ..u8(flood ? 1 : 0)
            ..u32(ack)
            ..u32(timeoutMs))
          .toBytes();

  static Uint8List sendConfirmed(int ack) =>
      (ByteWriter()
            ..u8(0x82)
            ..u32(ack)
            ..u32(1450))
          .toBytes();

  static Uint8List noMore() => Uint8List.fromList([10]);
  static Uint8List waiting() => Uint8List.fromList([0x83]);
}
