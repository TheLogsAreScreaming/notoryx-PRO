/// The protocol-neutral model every screen works with.
///
/// Each object carries the [RadioProtocol] it came from and the [RadioId]
/// of the radio that heard it, so one MeshCore and one Meshtastic radio can
/// be connected at once without their data mixing. A person seen on both
/// meshes is two [Node]s; the app never merges them by itself.
library;

import '../radio/radio_link.dart';

/// Identifies one radio the app talks to.
///
/// MeshCore radios are keyed by their public key, Meshtastic nodes by their
/// node number; both stay the same across reconnects and transports.
final class RadioId {
  const RadioId._(this.protocol, this.native);

  /// A MeshCore companion, by its 32-byte public key in hex.
  factory RadioId.meshcore(String publicKeyHex) =>
      RadioId._(RadioProtocol.meshcore, publicKeyHex.toLowerCase());

  /// A Meshtastic node, by node number.
  factory RadioId.meshtastic(int nodeNum) =>
      RadioId._(RadioProtocol.meshtastic, meshtasticNodeId(nodeNum));

  /// Reads the form written by [toString].
  static RadioId? tryParse(String text) {
    final i = text.indexOf(':');
    if (i < 0) return null;
    final protocol = RadioProtocol.values
        .where((p) => p.name == text.substring(0, i))
        .firstOrNull;
    if (protocol == null) return null;
    return RadioId._(protocol, text.substring(i + 1));
  }

  final RadioProtocol protocol;

  /// Public key hex (MeshCore) or `!xxxxxxxx` (Meshtastic).
  final String native;

  @override
  bool operator ==(Object other) =>
      other is RadioId && other.protocol == protocol && other.native == native;

  @override
  int get hashCode => Object.hash(protocol, native);

  /// Stable text form, e.g. `meshtastic:!a1b2c3d4`; used as a database key.
  @override
  String toString() => '${protocol.name}:$native';
}

/// Identifies a node on one mesh.
final class NodeKey {
  const NodeKey._(this.protocol, this.native);

  /// A MeshCore node by public key hex.
  factory NodeKey.meshcore(String publicKeyHex) =>
      NodeKey._(RadioProtocol.meshcore, publicKeyHex.toLowerCase());

  /// A Meshtastic node by node number.
  factory NodeKey.meshtastic(int nodeNum) =>
      NodeKey._(RadioProtocol.meshtastic, meshtasticNodeId(nodeNum));

  final RadioProtocol protocol;
  final String native;

  /// The Meshtastic node number, or null for MeshCore.
  int? get meshtasticNum => protocol == RadioProtocol.meshtastic
      ? int.tryParse(native.substring(1), radix: 16)
      : null;

  /// A short form to show, such as the first 8 hex digits of a key.
  String get short => protocol == RadioProtocol.meshcore
      ? native.substring(0, native.length < 8 ? native.length : 8)
      : native;

  @override
  bool operator ==(Object other) =>
      other is NodeKey && other.protocol == protocol && other.native == native;

  @override
  int get hashCode => Object.hash(protocol, native);

  @override
  String toString() => '${protocol.name}:$native';
}

/// `!` and 8 hex digits, as Meshtastic writes node numbers.
String meshtasticNodeId(int num) =>
    '!${(num & 0xffffffff).toRadixString(16).padLeft(8, '0')}';

/// What a node does on the mesh, in terms that make sense for both.
enum NodeKind {
  /// A person's device (MeshCore chat, Meshtastic client).
  person,

  /// Repeats traffic (MeshCore repeater, Meshtastic router/repeater).
  relay,

  /// A MeshCore room server.
  room,

  /// A sensor or tracker.
  sensor,

  unknown,
}

/// A position in degrees.
final class GeoPoint {
  const GeoPoint(this.latitude, this.longitude, {this.altitude});

  final double latitude;
  final double longitude;

  /// Metres above sea level, if known.
  final int? altitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.altitude == altitude;

  @override
  int get hashCode => Object.hash(latitude, longitude, altitude);
}

/// How a message or advert got here.
enum RouteKind {
  /// Along a known path.
  direct,

  /// Flooded through the mesh.
  flood,

  /// The protocol didn't say.
  unknown,
}

/// The path facts kept for every message and every node sighting.
final class PathFacts {
  const PathFacts({
    this.hops,
    this.snr,
    this.rssi,
    this.route = RouteKind.unknown,
    this.viaMqtt = false,
  });

  static const none = PathFacts();

  /// Repeaters it passed through; 0 = heard directly, null = unknown.
  final int? hops;

  /// Signal-to-noise ratio in dB at our radio.
  final double? snr;

  /// Received signal strength in dBm at our radio.
  final int? rssi;
  final RouteKind route;

  /// Came through an internet (MQTT) gateway, not only over radio.
  final bool viaMqtt;

  @override
  bool operator ==(Object other) =>
      other is PathFacts &&
      other.hops == hops &&
      other.snr == snr &&
      other.rssi == rssi &&
      other.route == route &&
      other.viaMqtt == viaMqtt;

  @override
  int get hashCode => Object.hash(hops, snr, rssi, route, viaMqtt);

  @override
  String toString() =>
      'PathFacts(hops: $hops, snr: $snr, rssi: $rssi, $route, mqtt: $viaMqtt)';
}

/// A radio the app has connected to.
final class Radio {
  const Radio({
    required this.id,
    required this.name,
    required this.self,
    this.firmware = '',
    this.model = '',
    this.maxChannels,
    this.position,
  });

  final RadioId id;
  final String name;

  /// This radio's own node on its mesh.
  final NodeKey self;

  /// Firmware version text, e.g. `v1.18.0` or `2.8.2.d5f1619`.
  final String firmware;

  /// Hardware model, if known.
  final String model;

  /// Channel slots (MeshCore reports it; Meshtastic has 8).
  final int? maxChannels;
  final GeoPoint? position;

  RadioProtocol get protocol => id.protocol;
}

/// A node heard on a mesh, as seen by one radio.
final class Node {
  const Node({
    required this.key,
    required this.radioId,
    required this.name,
    this.shortName = '',
    this.kind = NodeKind.unknown,
    this.position,
    this.lastHeard,
    this.path = PathFacts.none,
    this.isFavorite = false,
    this.batteryPercent,
    this.canMessage = true,
  });

  final NodeKey key;

  /// The radio that knows this node.
  final RadioId radioId;
  final String name;

  /// Up to 4 characters (Meshtastic); empty for MeshCore.
  final String shortName;
  final NodeKind kind;
  final GeoPoint? position;
  final DateTime? lastHeard;

  /// How it was last heard.
  final PathFacts path;
  final bool isFavorite;

  /// 0–100, or null; Meshtastic's 101 ("on external power") is mapped to null.
  final int? batteryPercent;

  /// False for nodes that refuse direct messages.
  final bool canMessage;

  RadioProtocol get protocol => key.protocol;

  /// Name to show, falling back to the short key.
  String get displayName => name.isNotEmpty ? name : key.short;

  Node copyWith({
    String? name,
    String? shortName,
    NodeKind? kind,
    GeoPoint? position,
    DateTime? lastHeard,
    PathFacts? path,
    bool? isFavorite,
    int? batteryPercent,
  }) => Node(
    key: key,
    radioId: radioId,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    kind: kind ?? this.kind,
    position: position ?? this.position,
    lastHeard: lastHeard ?? this.lastHeard,
    path: path ?? this.path,
    isFavorite: isFavorite ?? this.isFavorite,
    batteryPercent: batteryPercent ?? this.batteryPercent,
    canMessage: canMessage,
  );
}

/// Kinds of group channel.
enum ChannelKind {
  /// Everyone on the mesh (MeshCore "Public", Meshtastic primary default).
  public,

  /// Name-derived key (MeshCore `#name`); not private.
  hashtag,

  /// Shared secret key.
  private,
}

/// A group channel slot on one radio. Keys never live in this model.
final class Channel {
  const Channel({
    required this.radioId,
    required this.index,
    required this.name,
    required this.kind,
    this.isPrimary = false,
  });

  final RadioId radioId;

  /// Slot on the radio.
  final int index;
  final String name;
  final ChannelKind kind;

  /// Meshtastic primary channel (sets the radio's preset).
  final bool isPrimary;

  RadioProtocol get protocol => radioId.protocol;

  @override
  bool operator ==(Object other) =>
      other is Channel &&
      other.radioId == radioId &&
      other.index == index &&
      other.name == name &&
      other.kind == kind &&
      other.isPrimary == isPrimary;

  @override
  int get hashCode => Object.hash(radioId, index, name, kind, isPrimary);
}

/// A thread: a direct conversation with a node, or a channel.
sealed class Conversation {
  const Conversation(this.radioId);
  final RadioId radioId;

  /// Stable text form, used as a database key.
  String get key;

  @override
  bool operator ==(Object other) => other is Conversation && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Direct messages with one node.
final class DirectConversation extends Conversation {
  const DirectConversation(super.radioId, this.node);
  final NodeKey node;

  @override
  String get key => '$radioId/dm/$node';
}

/// A channel slot.
final class ChannelConversation extends Conversation {
  const ChannelConversation(super.radioId, this.index);
  final int index;

  @override
  String get key => '$radioId/ch/$index';
}

/// Where a sent message is.
sealed class DeliveryState {
  const DeliveryState();
}

/// Waiting to go to the radio, or for the radio to accept it.
final class Pending extends DeliveryState {
  const Pending();
}

/// The radio has sent it; nothing heard back yet.
final class Sent extends DeliveryState {
  const Sent({this.flood = false});

  /// MeshCore: it went by flood rather than a known path.
  final bool flood;
}

/// Another node was heard repeating it (all a broadcast can get).
final class Relayed extends DeliveryState {
  const Relayed();
}

/// The recipient confirmed it.
final class Delivered extends DeliveryState {
  const Delivered({this.roundTrip});
  final Duration? roundTrip;
}

/// It didn't get through.
final class Failed extends DeliveryState {
  const Failed(this.reason);

  /// Text to show people.
  final String reason;
}

/// Received messages have no delivery state of their own.
final class Received extends DeliveryState {
  const Received();
}

/// One message, sent or received, on either mesh.
final class Message {
  const Message({
    required this.conversation,
    required this.text,
    required this.outgoing,
    required this.sentAt,
    required this.receivedAt,
    required this.delivery,
    this.from,
    this.senderName,
    this.path = PathFacts.none,
    this.nativeId,
    this.replyTo,
    this.isReaction = false,
  });

  final Conversation conversation;
  final String text;
  final bool outgoing;

  /// Sender's clock.
  final DateTime sentAt;

  /// Our clock when it arrived (or was sent, for outgoing).
  final DateTime receivedAt;
  final DeliveryState delivery;

  /// The sender, when the protocol says (MeshCore channel posts only carry
  /// a name, in [senderName]).
  final NodeKey? from;

  /// The name the sender used, if any.
  final String? senderName;
  final PathFacts path;

  /// Protocol ID used to match acks and replies: the MeshCore ack code or
  /// the Meshtastic packet ID.
  final int? nativeId;

  /// The Meshtastic packet ID this replies to.
  final int? replyTo;

  /// An emoji reaction to [replyTo].
  final bool isReaction;

  RadioId get radioId => conversation.radioId;
  RadioProtocol get protocol => radioId.protocol;

  Message withDelivery(DeliveryState state) => Message(
    conversation: conversation,
    text: text,
    outgoing: outgoing,
    sentAt: sentAt,
    receivedAt: receivedAt,
    delivery: state,
    from: from,
    senderName: senderName,
    path: path,
    nativeId: nativeId,
    replyTo: replyTo,
    isReaction: isReaction,
  );
}
