import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a frame is shorter than its layout needs.
class FrameTooShort implements Exception {
  const FrameTooShort(this.needed, this.available);

  /// Bytes the read needed.
  final int needed;

  /// Bytes that were left.
  final int available;

  @override
  String toString() => 'FrameTooShort: needed $needed, had $available';
}

/// Reads little-endian fields from a MeshCore frame, front to back.
class ByteReader {
  ByteReader(this._data) : _view = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _view;
  int _offset = 0;

  /// Bytes not read yet.
  int get remaining => _data.length - _offset;

  void _need(int n) {
    if (remaining < n) throw FrameTooShort(n, remaining);
  }

  /// Unsigned byte.
  int u8() {
    _need(1);
    return _data[_offset++];
  }

  /// Signed byte.
  int i8() {
    _need(1);
    return _view.getInt8(_offset++);
  }

  /// Unsigned 16-bit.
  int u16() {
    _need(2);
    final v = _view.getUint16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  /// Unsigned 32-bit.
  int u32() {
    _need(4);
    final v = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  /// Signed 32-bit.
  int i32() {
    _need(4);
    final v = _view.getInt32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  /// The next [n] bytes, copied.
  Uint8List bytes(int n) {
    _need(n);
    final out = Uint8List.fromList(_data.sublist(_offset, _offset + n));
    _offset += n;
    return out;
  }

  /// Skips [n] bytes.
  void skip(int n) {
    _need(n);
    _offset += n;
  }

  /// A fixed-size, zero-padded UTF-8 field.
  String fixedString(int n) => decodeText(bytes(n), stopAtNull: true);

  /// Everything left, as UTF-8 text.
  String restAsText() => decodeText(bytes(remaining));

  /// Everything left, as bytes.
  Uint8List rest() => bytes(remaining);
}

/// Decodes UTF-8 leniently (radios can cut a character in half).
String decodeText(List<int> data, {bool stopAtNull = false}) {
  var end = data.length;
  if (stopAtNull) {
    final nul = data.indexOf(0);
    if (nul >= 0) end = nul;
  }
  return utf8.decode(data.sublist(0, end), allowMalformed: true);
}

/// Builds a little-endian MeshCore frame.
class ByteWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  /// Appends one byte.
  void u8(int v) => _b.addByte(v & 0xff);

  /// Appends an unsigned 32-bit value.
  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v & 0xffffffff, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  /// Appends a signed 32-bit value.
  void i32(int v) {
    final d = ByteData(4)..setInt32(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  /// Appends raw bytes.
  void bytes(List<int> v) => _b.add(v);

  /// Appends [text] as UTF-8 in a field of exactly [n] bytes, zero-padded.
  void fixedString(String text, int n) {
    final encoded = utf8.encode(text);
    if (encoded.length > n) {
      throw ArgumentError.value(text, 'text', 'longer than $n bytes');
    }
    _b.add(encoded);
    _b.add(Uint8List(n - encoded.length));
  }

  /// The frame built so far.
  Uint8List toBytes() => _b.toBytes();
}

/// Lower-case hex of [data].
String toHex(List<int> data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Bytes from a hex string; spaces are ignored.
Uint8List fromHex(String hex) {
  final clean = hex.replaceAll(' ', '');
  if (clean.length.isOdd) throw FormatException('Odd-length hex', hex);
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
