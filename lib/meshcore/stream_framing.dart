import 'dart:async';
import 'dart:typed_data';

import 'codes.dart';

/// Wraps one command for a USB or TCP link: `<`, length (u16 LE), frame.
///
/// Bluetooth links carry frames as they are and don't use this.
Uint8List wrapStreamFrame(Uint8List frame) {
  if (frame.isEmpty || frame.length > MeshCoreLimits.maxFrame) {
    throw ArgumentError.value(
      frame.length,
      'frame',
      'must be 1..${MeshCoreLimits.maxFrame} bytes',
    );
  }
  return Uint8List.fromList([
    0x3c,
    frame.length & 0xff,
    frame.length >> 8,
    ...frame,
  ]);
}

/// Splits the radio's USB/TCP byte stream into frames.
///
/// The radio sends `>`, a little-endian 16-bit length, then the frame.
/// Bytes before a `>` (boot messages, debug text) are skipped, and a length
/// of zero or above [maxLength] is treated as noise.
class StreamFrameDecoder {
  StreamFrameDecoder({this.maxLength = 300});

  /// Longest frame accepted.
  final int maxLength;

  final List<int> _buffer = [];

  /// Adds received bytes and returns any frames now complete.
  List<Uint8List> add(List<int> data) {
    _buffer.addAll(data);
    final frames = <Uint8List>[];
    while (true) {
      final start = _buffer.indexOf(0x3e);
      if (start < 0) {
        _buffer.clear();
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < 3) break;
      final length = _buffer[1] | (_buffer[2] << 8);
      if (length == 0 || length > maxLength) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < 3 + length) break;
      frames.add(Uint8List.fromList(_buffer.sublist(3, 3 + length)));
      _buffer.removeRange(0, 3 + length);
    }
    return frames;
  }

  /// Drops anything buffered, for example after reconnecting.
  void reset() => _buffer.clear();
}

/// Turns a byte stream into a frame stream with [StreamFrameDecoder].
Stream<Uint8List> decodeStreamFrames(Stream<Uint8List> bytes) {
  final decoder = StreamFrameDecoder();
  return bytes.expand(decoder.add);
}
