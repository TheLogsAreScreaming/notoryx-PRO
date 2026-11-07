import '../meshtastic/meshtastic.dart';
import 'model.dart';

/// Turns Meshtastic session data into the shared model.
class MeshtasticMapper {
  MeshtasticMapper(this.radioId, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The radio this data came from.
  final RadioId radioId;
  final DateTime Function() _clock;

  /// Meshtastic radios always have 8 channel slots.
  static const channelSlots = 8;

  /// The radio itself, from the config download.
  static Radio radio(MeshtasticConfig c) {
    final num = c.myInfo.nodeNum;
    final user = c.self?.user;
    final pos = c.self?.position;
    return Radio(
      id: RadioId.meshtastic(num),
      name: (user?.longName.isNotEmpty ?? false)
          ? user!.longName
          : meshtasticNodeId(num),
      self: NodeKey.meshtastic(num),
      firmware: c.metadata?.firmwareVersion ?? '',
      model: c.myInfo.pioEnv,
      maxChannels: channelSlots,
      position: _point(pos),
    );
  }

  /// A node from the node database.
  Node node(MeshNodeInfo n) {
    final user = n.user;
    final battery = n.metrics?.batteryLevel;
    return Node(
      key: NodeKey.meshtastic(n.num),
      radioId: radioId,
      name: user?.longName ?? '',
      shortName: user?.shortName ?? '',
      kind: kindForRole(user?.role ?? 0),
      position: _point(n.position),
      lastHeard: _seconds(n.lastHeard),
      path: PathFacts(hops: n.hopsAway, snr: n.snr, viaMqtt: n.viaMqtt),
      isFavorite: n.isFavorite,
      batteryPercent: battery != null && battery <= 100 ? battery : null,
      canMessage: !(user?.isUnmessagable ?? false),
    );
  }

  /// Applies news heard on the mesh to [existing] (or a new node).
  Node update(Node? existing, NodeUpdate u) {
    final base =
        existing ??
        Node(key: NodeKey.meshtastic(u.num), radioId: radioId, name: '');
    final user = u.user;
    return base.copyWith(
      name: user?.longName,
      shortName: user?.shortName,
      kind: user == null ? null : kindForRole(user.role),
      position: _point(u.position),
      lastHeard: _clock(),
      path: PathFacts(hops: u.hops, snr: u.snr, viaMqtt: u.viaMqtt),
    );
  }

  /// A channel slot; null when disabled.
  Channel? channel(MeshChannel c) {
    if (!c.isEnabled) return null;
    final psk = c.psk;
    // No key, or a one-byte index into the well-known default keys, means
    // anyone with the app defaults can read it.
    final open = psk == null || psk.length <= 1;
    final primary = c.role == ChannelRole.primary;
    return Channel(
      radioId: radioId,
      index: c.index,
      name: c.name.isNotEmpty
          ? c.name
          : (primary ? 'Primary' : 'Channel ${c.index}'),
      kind: open ? ChannelKind.public : ChannelKind.private,
      isPrimary: primary,
    );
  }

  /// A received text message.
  Message received(MeshtasticText t) {
    final now = _clock();
    final from = NodeKey.meshtastic(t.from);
    final rx = t.packet.rxTime;
    return Message(
      conversation: t.isDirect
          ? DirectConversation(radioId, from)
          : ChannelConversation(radioId, t.channel),
      text: t.text,
      outgoing: false,
      // Meshtastic texts carry no sender clock; the node's receive time is
      // the closest.
      sentAt: _seconds(rx ?? 0) ?? now,
      receivedAt: now,
      delivery: const Received(),
      from: from,
      path: PathFacts(
        hops: t.hops,
        snr: t.snr,
        rssi: t.rssi,
        viaMqtt: t.viaMqtt,
      ),
      nativeId: t.id,
      replyTo: t.replyId == 0 ? null : t.replyId,
      isReaction: t.isReaction,
    );
  }

  /// The delivery state for a [DeliveryUpdate].
  static DeliveryState delivery(DeliveryUpdate u) => switch (u.status) {
    DeliveryStatus.queued => const Sent(),
    DeliveryStatus.relayed => const Relayed(),
    DeliveryStatus.delivered => const Delivered(),
    DeliveryStatus.failed => Failed((u.error ?? RoutingError.unknown).message),
  };

  /// Meshtastic device roles (config.proto `DeviceConfig.Role`).
  static NodeKind kindForRole(int role) => switch (role) {
    0 || 1 || 8 || 12 => NodeKind.person, // client, mute, hidden, base
    2 || 3 || 4 || 11 => NodeKind.relay, // router, router-client, repeater
    5 || 6 || 10 || 9 => NodeKind.sensor, // tracker, sensor, TAK tracker
    7 => NodeKind.person, // TAK
    _ => NodeKind.unknown,
  };

  static GeoPoint? _point(MeshPosition? p) {
    if (p == null || p.latitude == null || p.longitude == null) return null;
    if (p.latitude == 0 && p.longitude == 0) return null;
    return GeoPoint(p.latitude!, p.longitude!, altitude: p.altitude);
  }

  static DateTime? _seconds(int unix) => unix <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
}
