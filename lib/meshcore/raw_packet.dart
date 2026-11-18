import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// How a MeshCore packet is routed (header bits 0-1).
enum MeshCoreRoute { transportFlood, flood, direct, transportDirect }

/// What a MeshCore packet carries (header bits 2-5), per docs/packet_format.md.
enum MeshCorePayload {
  request('Request'),
  response('Response'),
  text('Direct message'),
  ack('Ack'),
  advert('Advert'),
  groupText('Channel message'),
  groupData('Channel data'),
  anonRequest('Anonymous request'),
  path('Path'),
  trace('Trace'),
  multipart('Multipart'),
  control('Control'),
  reserved12('Reserved'),
  reserved13('Reserved'),
  reserved14('Reserved'),
  rawCustom('Custom');

  const MeshCorePayload(this.label);

  /// English name; the UI may translate by enum name later.
  final String label;
}

/// The outer layer of a raw MeshCore packet, as heard on air.
///
/// Payloads stay encrypted; only the routing header is read, so the packet
/// log can show what kind of traffic is around without decrypting anything.
class MeshCorePacketInfo {
  MeshCorePacketInfo({
    required this.route,
    required this.payload,
    required this.version,
    required this.hops,
    required this.hashSize,
    required this.path,
    required this.payloadLength,
    Uint8List? body,
  }) : body = body ?? Uint8List(0);

  final MeshCoreRoute route;
  final MeshCorePayload payload;
  final int version;

  /// Repeaters it has passed (flood) or still has to pass (direct).
  final int hops;
  final int hashSize;
  final Uint8List path;
  final int payloadLength;

  /// The payload bytes after the path. Mostly encrypted; only the plain
  /// routing fields at the start are read (see [originKeyHex] and
  /// [originHash]).
  final Uint8List body;

  bool get isFlood =>
      route == MeshCoreRoute.flood || route == MeshCoreRoute.transportFlood;

  /// Path as hex hashes, e.g. `a1 b2`.
  String get pathText => [
    for (var i = 0; i + hashSize <= path.length; i += hashSize)
      toHex(path.sublist(i, i + hashSize)),
  ].join(' ');

  /// Reads [raw]; null if it is too short or malformed.
  static MeshCorePacketInfo? parse(Uint8List raw) {
    if (raw.length < 2) return null;
    final header = raw[0];
    final route = MeshCoreRoute.values[header & 0x03];
    var i = 1;
    if (route == MeshCoreRoute.transportFlood ||
        route == MeshCoreRoute.transportDirect) {
      i += 4;
    }
    if (raw.length <= i) return null;
    final pathLength = raw[i++];
    final hops = pathLength & 0x3f;
    final sizeBits = (pathLength >> 6) & 0x03;
    if (sizeBits == 3) return null;
    final hashSize = sizeBits + 1;
    final pathBytes = hops * hashSize;
    if (raw.length < i + pathBytes) return null;
    return MeshCorePacketInfo(
      route: route,
      payload: MeshCorePayload.values[(header >> 2) & 0x0f],
      version: (header >> 6) & 0x03,
      hops: hops,
      hashSize: hashSize,
      path: Uint8List.fromList(raw.sublist(i, i + pathBytes)),
      payloadLength: raw.length - i - pathBytes,
      body: Uint8List.fromList(raw.sublist(i + pathBytes)),
    );
  }

  /// The sender's full public key as hex, when the payload carries it in
  /// the clear: adverts start with it, anonymous requests put it after the
  /// one-byte destination hash.
  String? get originKeyHex => switch (payload) {
    MeshCorePayload.advert when body.length >= 32 => toHex(body.sublist(0, 32)),
    MeshCorePayload.anonRequest when body.length >= 33 => toHex(
      body.sublist(1, 33),
    ),
    _ => null,
  };

  /// The sender's one-byte hash as hex, for payloads that start with
  /// destination and source hashes (requests, responses, direct messages
  /// and returned paths).
  String? get originHash => switch (payload) {
    MeshCorePayload.request ||
    MeshCorePayload.response ||
    MeshCorePayload.text ||
    MeshCorePayload.path when body.length >= 2 => toHex(body.sublist(1, 2)),
    _ => null,
  };

  /// The repeaters this packet has passed, in order, as hex hashes.
  ///
  /// A flooded packet's path grows by one hash at each repeater. A direct
  /// packet's path lists the hops still ahead, so nothing has been passed
  /// that we can see. A trace keeps its route in the payload (after a
  /// 4-byte tag, 4-byte code and a flags byte) and one SNR per hop done in
  /// the path.
  List<String> get hopsPassed {
    if (payload == MeshCorePayload.trace) {
      if (body.length < 9) return const [];
      final size = 1 << (body[8] & 0x03);
      if (size > 4) return const [];
      final out = <String>[];
      for (var i = 9; i + size <= body.length && out.length < hops; i += size) {
        out.add(toHex(body.sublist(i, i + size)));
      }
      return out;
    }
    if (!isFlood) return const [];
    return [
      for (var i = 0; i + hashSize <= path.length; i += hashSize)
        toHex(path.sublist(i, i + hashSize)),
    ];
  }

  /// Where an advert says its node is, from the app data after the key,
  /// timestamp and signature: a flags byte, then (when bit 0x10 is set)
  /// latitude and longitude as millionths of a degree.
  ({double latitude, double longitude})? get advertLocation {
    if (payload != MeshCorePayload.advert || body.length < 101) return null;
    final flags = body[100];
    if (flags & 0x10 == 0 || body.length < 109) return null;
    final d = ByteData.sublistView(body, 101, 109);
    final lat = d.getInt32(0, Endian.little) / 1e6;
    final lon = d.getInt32(4, Endian.little) / 1e6;
    if (lat.abs() > 90 || lon.abs() > 180 || (lat == 0 && lon == 0)) {
      return null;
    }
    return (latitude: lat, longitude: lon);
  }

  /// The name an advert gives, from its app data (bit 0x80 of the flags),
  /// after the location and the two optional 2-byte feature fields.
  String? get advertName {
    if (payload != MeshCorePayload.advert || body.length < 101) return null;
    final flags = body[100];
    if (flags & 0x80 == 0) return null;
    var i = 101;
    if (flags & 0x10 != 0) i += 8;
    if (flags & 0x20 != 0) i += 2;
    if (flags & 0x40 != 0) i += 2;
    if (i >= body.length) return null;
    var end = body.indexOf(0, i);
    if (end < 0) end = body.length;
    final name = utf8.decode(body.sublist(i, end), allowMalformed: true).trim();
    return name.isEmpty ? null : name;
  }
}
