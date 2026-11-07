import 'dart:convert';
import 'dart:typed_data';

/// Longest protobuf a Meshtastic node sends or accepts over USB/TCP.
const meshtasticMaxFrame = 512;

/// Wraps one `ToRadio` for USB or TCP: `0x94 0xC3`, length (u16 big-endian),
/// then the protobuf. Bluetooth writes the protobuf as it is.
Uint8List wrapMeshtasticFrame(Uint8List protobuf) {
  if (protobuf.isEmpty || protobuf.length > meshtasticMaxFrame) {
    throw ArgumentError.value(
      protobuf.length,
      'protobuf',
      'must be 1..$meshtasticMaxFrame bytes',
    );
  }
  return Uint8List.fromList([
    0x94,
    0xc3,
    protobuf.length >> 8,
    protobuf.length & 0xff,
    ...protobuf,
  ]);
}

/// Splits a Meshtastic node's USB/TCP byte stream into `FromRadio` frames.
///
/// Anything outside a frame is the node's debug console; complete lines of
/// it are collected in [consoleLines] (capped) for the connection log.
class MeshtasticFrameDecoder {
  MeshtasticFrameDecoder({this.maxConsoleLines = 50});

  /// Most console lines kept.
  final int maxConsoleLines;

  final List<int> _buffer = [];
  final List<int> _console = [];

  /// Debug console lines seen so far, newest last.
  final List<String> consoleLines = [];

  /// Adds received bytes and returns any frames now complete.
  List<Uint8List> add(List<int> data) {
    _buffer.addAll(data);
    final frames = <Uint8List>[];
    while (_buffer.isNotEmpty) {
      final start = _findMagic();
      if (start < 0) {
        // Keep a trailing 0x94 in case its 0xC3 is in the next read.
        final keep = _buffer.last == 0x94 ? 1 : 0;
        _takeConsole(_buffer.length - keep);
        break;
      }
      _takeConsole(start);
      if (_buffer.length < 4) break;
      final length = (_buffer[2] << 8) | _buffer[3];
      if (length == 0 || length > meshtasticMaxFrame) {
        _buffer.removeRange(0, 2);
        continue;
      }
      if (_buffer.length < 4 + length) break;
      frames.add(Uint8List.fromList(_buffer.sublist(4, 4 + length)));
      _buffer.removeRange(0, 4 + length);
    }
    return frames;
  }

  int _findMagic() {
    for (var i = 0; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == 0x94 && _buffer[i + 1] == 0xc3) return i;
    }
    return -1;
  }

  void _takeConsole(int count) {
    if (count <= 0) return;
    for (final b in _buffer.take(count)) {
      if (b == 0x0a) {
        final line = utf8.decode(_console, allowMalformed: true).trim();
        _console.clear();
        if (line.isNotEmpty) {
          consoleLines.add(line);
          if (consoleLines.length > maxConsoleLines) consoleLines.removeAt(0);
        }
      } else if (b != 0x0d && _console.length < 400) {
        _console.add(b);
      }
    }
    _buffer.removeRange(0, count);
  }

  /// Drops buffered bytes, for example after reconnecting.
  void reset() {
    _buffer.clear();
    _console.clear();
  }
}

/// Wakes a node's serial API: some boards need these bytes before the first
/// frame (32 × 0xC3), as the Meshtastic clients send.
Uint8List meshtasticSerialWake() => Uint8List.fromList(List.filled(32, 0xc3));
