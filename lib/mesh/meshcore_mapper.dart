import 'dart:typed_data';

import '../meshcore/meshcore.dart';
import 'model.dart';

/// Key of MeshCore's built-in "Public" channel (from the protocol docs).
const meshCorePublicKeyHex = '8b3387e9c5cdea6ac9e5edbaa115cd72';

/// Turns MeshCore frames into the shared model.
class MeshCoreMapper {
  MeshCoreMapper(this.radioId, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The radio these frames came from.
  final RadioId radioId;
  final DateTime Function() _clock;

  /// The radio itself, from the start-up handshake.
  static Radio radio(MeshCoreHandshake h) {
    final key = toHex(h.self.publicKey);
    final hasPosition = h.self.latitude != 0 || h.self.longitude != 0;
    return Radio(
      id: RadioId.meshcore(key),
      name: h.self.name,
      self: NodeKey.meshcore(key),
      firmware: h.device.version ?? 'protocol ${h.device.firmwareCode}',
      model: h.device.model ?? '',
      maxChannels: h.device.maxChannels,
      position: hasPosition
          ? GeoPoint(h.self.latitude, h.self.longitude)
          : null,
    );
  }

  /// A contact, or a node heard advertising.
  Node node(ContactFrame c) => Node(
    key: NodeKey.meshcore(c.keyHex),
    radioId: radioId,
    name: c.name,
    kind: switch (c.type) {
      NodeType.chat => NodeKind.person,
      NodeType.repeater => NodeKind.relay,
      NodeType.room => NodeKind.room,
      NodeType.sensor => NodeKind.sensor,
      NodeType.unknown => NodeKind.unknown,
    },
    position: c.latitude == null ? null : GeoPoint(c.latitude!, c.longitude!),
    lastHeard: _seconds(c.lastAdvert),
    path: PathFacts(
      hops: c.hops,
      route: c.hasPath ? RouteKind.direct : RouteKind.flood,
    ),
    isFavorite: c.flags & 1 != 0,
  );

  /// A channel slot; null for an unused one.
  Channel? channel(ChannelInfoFrame f) {
    if (f.isEmpty) return null;
    final kind = toHex(f.secret) == meshCorePublicKeyHex
        ? ChannelKind.public
        : f.name.startsWith('#')
        ? ChannelKind.hashtag
        : ChannelKind.private;
    return Channel(radioId: radioId, index: f.index, name: f.name, kind: kind);
  }

  /// A received message; null for frames that aren't messages.
  ///
  /// Direct messages name the sender by the first 6 bytes of its key;
  /// [findContact] turns that into the full key. If no contact matches,
  /// the key is the 12-digit prefix until the sender is known.
  Message? received(
    MeshCoreFrame frame, {
    NodeKey? Function(Uint8List keyPrefix)? findContact,
  }) {
    final now = _clock();
    switch (frame) {
      case ContactMessageFrame():
        final from =
            findContact?.call(frame.keyPrefix) ??
            NodeKey.meshcore(toHex(frame.keyPrefix));
        return Message(
          conversation: DirectConversation(radioId, from),
          text: frame.text,
          outgoing: false,
          sentAt: _seconds(frame.timestamp) ?? now,
          receivedAt: now,
          delivery: const Received(),
          from: from,
          path: _path(frame.pathLength, frame.snr),
        );
      case ChannelMessageFrame():
        return Message(
          conversation: ChannelConversation(radioId, frame.channel),
          text: frame.body,
          outgoing: false,
          sentAt: _seconds(frame.timestamp) ?? now,
          receivedAt: now,
          delivery: const Received(),
          senderName: frame.senderName,
          path: _path(frame.pathLength, frame.snr),
        );
      default:
        return null;
    }
  }

  /// Delivery after the radio accepted a direct message.
  static DeliveryState sent(SentFrame f) => Sent(flood: f.flood);

  /// Delivery after the recipient's acknowledgement arrived.
  static DeliveryState confirmed(SendConfirmedPush p) =>
      Delivered(roundTrip: Duration(milliseconds: p.roundTripMs));

  /// In received frames, 0xFF means it came along a direct path; anything
  /// else is the flood path length (low 6 bits = hops).
  static PathFacts _path(int pathLength, double? snr) => pathLength == 0xff
      ? PathFacts(route: RouteKind.direct, snr: snr)
      : PathFacts(route: RouteKind.flood, hops: pathLength & 0x3f, snr: snr);

  static DateTime? _seconds(int unix) => unix <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
}
