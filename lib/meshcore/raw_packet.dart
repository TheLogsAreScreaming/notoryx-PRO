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
  const MeshCorePacketInfo({
    required this.route,
    required this.payload,
    required this.version,
    required this.hops,
    required this.hashSize,
    required this.path,
    required this.payloadLength,
  });

  final MeshCoreRoute route;
  final MeshCorePayload payload;
  final int version;

  /// Repeaters it has passed (flood) or still has to pass (direct).
  final int hops;
  final int hashSize;
  final Uint8List path;
  final int payloadLength;

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
    );
  }
}
