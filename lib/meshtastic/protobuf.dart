import 'dart:convert';
import 'dart:typed_data';

/// Protocol Buffers wire types.
abstract final class WireType {
  static const varint = 0;
  static const fixed64 = 1;
  static const lengthDelimited = 2;
  static const fixed32 = 5;
}

/// Thrown for bytes that aren't valid protobuf.
class ProtobufException implements Exception {
  const ProtobufException(this.message);
  final String message;
  @override
  String toString() => 'ProtobufException: $message';
}

/// One field read from a message.
///
/// [value] is an `int` for varint, fixed32 and fixed64 fields and a
/// [Uint8List] for length-delimited ones (strings, bytes, sub-messages).
class ProtoField {
  const ProtoField(this.number, this.wireType, this.value);

  final int number;
  final int wireType;
  final Object value;

  /// Unsigned integer value.
  int get asInt => value as int;

  /// Varint as a bool.
  bool get asBool => asInt != 0;

  /// Varint as a signed 32-bit `int32` (negatives are sent as 64-bit).
  int get asInt32 => asInt.toSigned(32);

  /// ZigZag-encoded `sint32`.
  int get asSint32 => (asInt >> 1) ^ -(asInt & 1);

  /// `fixed32` read as signed (`sfixed32`).
  int get asSfixed32 => asInt.toSigned(32);

  /// `fixed32` bits read as a 32-bit float.
  double get asFloat {
    final d = ByteData(4)..setUint32(0, asInt, Endian.little);
    return d.getFloat32(0, Endian.little);
  }

  /// Length-delimited bytes.
  Uint8List get asBytes => value as Uint8List;

  /// Length-delimited UTF-8 text.
  String get asString => utf8.decode(asBytes, allowMalformed: true);

  /// Values of a repeated `fixed32` field (packed or one per field).
  List<int> get asFixed32List {
    if (wireType == WireType.fixed32) return [asInt];
    final b = asBytes;
    final d = ByteData.sublistView(b);
    return [
      for (var i = 0; i + 4 <= b.length; i += 4) d.getUint32(i, Endian.little),
    ];
  }

  /// Values of a repeated `int32` field (packed or one per field).
  List<int> get asInt32List {
    if (wireType == WireType.varint) return [asInt32];
    return [for (final f in readPackedVarints(asBytes)) f.toSigned(32)];
  }
}

/// Decodes a packed run of varints.
List<int> readPackedVarints(Uint8List data) {
  final out = <int>[];
  var i = 0;
  while (i < data.length) {
    var result = 0;
    var shift = 0;
    while (true) {
      if (i >= data.length) throw const ProtobufException('truncated varint');
      final b = data[i++];
      if (shift < 64) result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
      if (shift > 63) throw const ProtobufException('varint too long');
    }
    out.add(result);
  }
  return out;
}

/// Reads every field of a message, in order. Unknown fields are kept, so
/// callers simply ignore numbers they don't need.
List<ProtoField> readFields(Uint8List data) {
  final fields = <ProtoField>[];
  var i = 0;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (i >= data.length) throw const ProtobufException('truncated varint');
      final b = data[i++];
      if (shift < 64) result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const ProtobufException('varint too long');
    }
  }

  while (i < data.length) {
    final key = varint();
    final number = key >> 3;
    final type = key & 7;
    if (number == 0) throw const ProtobufException('field number 0');
    switch (type) {
      case WireType.varint:
        fields.add(ProtoField(number, type, varint()));
      case WireType.fixed64:
        if (i + 8 > data.length) throw const ProtobufException('truncated');
        final v = ByteData.sublistView(
          data,
          i,
          i + 8,
        ).getUint64(0, Endian.little);
        i += 8;
        fields.add(ProtoField(number, type, v));
      case WireType.lengthDelimited:
        final length = varint();
        if (length < 0 || i + length > data.length) {
          throw const ProtobufException('truncated bytes');
        }
        fields.add(
          ProtoField(
            number,
            type,
            Uint8List.fromList(data.sublist(i, i + length)),
          ),
        );
        i += length;
      case WireType.fixed32:
        if (i + 4 > data.length) throw const ProtobufException('truncated');
        final v = ByteData.sublistView(
          data,
          i,
          i + 4,
        ).getUint32(0, Endian.little);
        i += 4;
        fields.add(ProtoField(number, type, v));
      default:
        throw ProtobufException('unsupported wire type $type');
    }
  }
  return fields;
}

/// Builds a protobuf message. Fields at their default value are skipped,
/// as proto3 does, unless written with `always: true`.
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void _varint(int value) {
    var v = value;
    // Negative int32/int64 values are sent as 10-byte two's complement.
    for (var n = 0; n < 10; n++) {
      final byte = v & 0x7f;
      v = v >>> 7;
      if (v == 0) {
        _b.addByte(byte);
        return;
      }
      _b.addByte(byte | 0x80);
    }
  }

  void _key(int number, int type) => _varint((number << 3) | type);

  /// `uint32`, `int32`, enum.
  void uint(int number, int value, {bool always = false}) {
    if (value == 0 && !always) return;
    _key(number, WireType.varint);
    _varint(value);
  }

  /// `bool`.
  void boolean(int number, bool value) {
    if (!value) return;
    _key(number, WireType.varint);
    _varint(1);
  }

  /// `fixed32` / `sfixed32`.
  void fixed32(int number, int value, {bool always = false}) {
    if (value == 0 && !always) return;
    _key(number, WireType.fixed32);
    final d = ByteData(4)..setUint32(0, value & 0xffffffff, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  /// `bytes` or an encoded sub-message.
  void bytes(int number, List<int> value, {bool always = false}) {
    if (value.isEmpty && !always) return;
    _key(number, WireType.lengthDelimited);
    _varint(value.length);
    _b.add(value);
  }

  /// `string`.
  void string(int number, String value) => bytes(number, utf8.encode(value));

  /// The encoded message.
  Uint8List toBytes() => _b.toBytes();
}
