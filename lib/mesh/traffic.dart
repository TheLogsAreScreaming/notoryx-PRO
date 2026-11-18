import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../meshcore/raw_packet.dart';
import '../meshtastic/meshtastic.dart';
import '../radio/radio_link.dart';
import 'hop_naming.dart';
import 'model.dart';

/// The six colours packets are drawn in on the Traffic map.
enum TrafficKind {
  /// Adverts (MeshCore) and position or node-info packets (Meshtastic).
  advert,

  /// Direct messages, requests and responses to one node.
  direct,

  /// Messages and data on a channel.
  channel,

  /// Acknowledgements and routing replies.
  ack,

  /// Traces and traceroutes.
  trace,

  /// Returned paths, and anything else.
  path,
}

/// The [TrafficKind] a MeshCore payload type is drawn as.
TrafficKind trafficKindOfMeshCore(MeshCorePayload p) => switch (p) {
  MeshCorePayload.advert => TrafficKind.advert,
  MeshCorePayload.text ||
  MeshCorePayload.request ||
  MeshCorePayload.response ||
  MeshCorePayload.anonRequest => TrafficKind.direct,
  MeshCorePayload.groupText || MeshCorePayload.groupData => TrafficKind.channel,
  MeshCorePayload.ack => TrafficKind.ack,
  MeshCorePayload.trace => TrafficKind.trace,
  _ => TrafficKind.path,
};

/// The [TrafficKind] a Meshtastic packet on [port] is drawn as; [broadcast]
/// tells a channel message from a direct one. Unreadable packets
/// (null [port]) count as "other".
TrafficKind trafficKindOfMeshtastic(int? port, {required bool broadcast}) =>
    switch (port) {
      PortNum.position || PortNum.nodeInfo => TrafficKind.advert,
      PortNum.textMessage =>
        broadcast ? TrafficKind.channel : TrafficKind.direct,
      PortNum.routing => TrafficKind.ack,
      PortNum.traceroute => TrafficKind.trace,
      _ => TrafficKind.path,
    };

/// How a hop in a heard packet names its node.
enum HopMatch {
  /// The node's full key (Meshtastic node ID, or a whole MeshCore key).
  key,

  /// The first byte(s) of a MeshCore public key, as hex.
  prefix,

  /// The last byte of a Meshtastic node number, as hex (`relay_node`).
  lastByte,
}

/// One hop of a heard packet, before it is matched to a known node.
@immutable
final class HopId {
  const HopId(this.id, this.match);

  /// Lower-case hex prefix or byte, or the full key's native form.
  final String id;
  final HopMatch match;

  @override
  bool operator ==(Object other) =>
      other is HopId && other.id == id && other.match == match;

  @override
  int get hashCode => Object.hash(id, match);

  @override
  String toString() => 'HopId($id, ${match.name})';
}

/// A packet our radio heard, with what it says about where it came from.
@immutable
final class HeardPacket {
  const HeardPacket({
    required this.time,
    required this.radioId,
    required this.kind,
    required this.label,
    this.origin,
    this.originName,
    this.originAt,
    this.hops = const [],
    this.hopCount,
    this.flood = true,
    this.snr,
    this.rssi,
  });

  final DateTime time;

  /// The radio that heard it.
  final RadioId radioId;
  final TrafficKind kind;

  /// What it is, in the protocol's words ("Advert", "Request", "Position").
  final String label;

  /// Who sent it, when the packet says (full key, or a MeshCore hash).
  final HopId? origin;

  /// The sender's own name, when the packet carries it (MeshCore adverts).
  final String? originName;

  /// Where the sender says it is (MeshCore adverts).
  final GeoPoint? originAt;

  /// Repeaters passed between the sender and us, in order.
  final List<HopId> hops;

  /// Hops taken, when the protocol says; may be more than [hops] lists.
  final int? hopCount;

  /// Flooded rather than sent along a known route.
  final bool flood;
  final double? snr;
  final int? rssi;
}

/// What a MeshCore radio heard in a raw packet.
HeardPacket heardMeshCore(
  MeshCorePacketInfo info, {
  required RadioId radioId,
  required DateTime time,
  double? snr,
  int? rssi,
}) {
  final key = info.originKeyHex;
  final hash = info.originHash;
  final at = info.advertLocation;
  return HeardPacket(
    time: time,
    radioId: radioId,
    kind: trafficKindOfMeshCore(info.payload),
    label: info.payload.label,
    origin: key != null
        ? HopId(key, HopMatch.key)
        : hash != null
        ? HopId(hash, HopMatch.prefix)
        : null,
    originName: info.advertName,
    originAt: at == null ? null : GeoPoint(at.latitude, at.longitude),
    hops: [for (final h in info.hopsPassed) HopId(h, HopMatch.prefix)],
    hopCount: info.payload == MeshCorePayload.trace || info.isFlood
        ? info.hops
        : null,
    flood: info.isFlood,
    snr: snr,
    rssi: rssi,
  );
}

/// What a Meshtastic radio heard in [p].
///
/// Meshtastic packets don't carry their path. A traceroute does (its route
/// back, or its route out while still on the way); otherwise only the last
/// byte of the node that relayed it to us is known.
HeardPacket heardMeshtastic(
  MeshPacket p, {
  required RadioId radioId,
  required DateTime time,
  required String label,
}) {
  final data = p.decoded;
  final port = data?.portnum;
  var hops = <HopId>[];
  if (port == PortNum.traceroute && data != null) {
    try {
      final r = RouteDiscovery.decode(data.payload);
      final passed = r.routeBack.isNotEmpty ? r.routeBack : r.route;
      hops = [
        for (final n in passed)
          if (n != p.from && n != broadcastNode)
            HopId(meshtasticNodeId(n), HopMatch.key),
      ];
    } on Object {
      hops = [];
    }
  }
  final relay = p.relayNode & 0xff;
  if (hops.isEmpty &&
      p.relayNode != 0 &&
      relay != p.from & 0xff &&
      (p.hopsTaken ?? 1) > 0) {
    hops = [HopId(relay.toRadixString(16).padLeft(2, '0'), HopMatch.lastByte)];
  }
  return HeardPacket(
    time: time,
    radioId: radioId,
    kind: trafficKindOfMeshtastic(port, broadcast: p.isBroadcast),
    label: label,
    origin: HopId(meshtasticNodeId(p.from), HopMatch.key),
    hops: hops,
    hopCount: p.hopsTaken,
    snr: p.rxSnr,
    rssi: p.rxRssi,
  );
}

/// Where a stop sits on a route.
enum StopRole { origin, hop, self }

/// One stop on a drawn route.
@immutable
final class TrafficStop {
  const TrafficStop({
    required this.label,
    required this.role,
    this.node,
    this.at,
  });

  /// Name, or short ID when the node isn't known.
  final String label;
  final StopRole role;

  /// The known node, if matched.
  final Node? node;

  /// Where to draw it; null keeps it off the map.
  final GeoPoint? at;

  bool get onMap => at != null;
}

/// A heard packet's route: sender, repeaters, then us.
@immutable
final class TrafficRoute {
  const TrafficRoute(this.packet, this.stops);

  final HeardPacket packet;
  final List<TrafficStop> stops;

  /// The stops that have a position, in order.
  List<TrafficStop> get onMap => [
    for (final s in stops)
      if (s.onMap) s,
  ];

  /// Senders and repeaters with no position (our own radio isn't listed).
  List<TrafficStop> get offMap => [
    for (final s in stops)
      if (!s.onMap && s.role != StopRole.self) s,
  ];

  /// Whether there are two or more places to draw a line between.
  bool get drawable => onMap.length >= 2;

  /// The node we heard it from: the last repeater, else the sender.
  TrafficStop? get heardFrom {
    final before = [
      for (final s in stops)
        if (s.role != StopRole.self) s,
    ];
    return before.lastOrNull;
  }

  /// `Sender → hop → … → us`.
  String get text => stops.map((s) => s.label).join(' → ');
}

/// A short ID to show for [h] when no node matches it.
String hopLabel(HopId h) => switch (h.match) {
  HopMatch.key when h.id.startsWith('!') => h.id,
  HopMatch.key =>
    h.id.substring(0, h.id.length < 8 ? h.id.length : 8).toUpperCase(),
  HopMatch.prefix => h.id.toUpperCase(),
  HopMatch.lastByte => '…${h.id.toUpperCase()}',
};

/// The nodes in [candidates] that [h] could be.
List<Node> matchHop(HopId h, Iterable<Node> candidates) {
  final id = h.id.toLowerCase();
  return switch (h.match) {
    HopMatch.key => [
      for (final n in candidates)
        if (n.key.native == id || n.key.native == h.id) n,
    ],
    HopMatch.prefix => [
      for (final n in candidates)
        if (n.protocol == RadioProtocol.meshcore && n.key.native.startsWith(id))
          n,
    ],
    HopMatch.lastByte => [
      for (final n in candidates)
        if (n.key.meshtasticNum case final num?
            when (num & 0xff) == int.parse(id, radix: 16))
          n,
    ],
  };
}

/// Builds [p]'s route through [known] nodes, ending at our radio.
///
/// Each hop is matched to a node the same radio knows. When several match,
/// [naming] (if given) picks the one nearest the previous stop or a
/// remembered pick; otherwise the hop stays unnamed. Nodes without a
/// position stay in the route but off the map, so the drawn line jumps
/// from one located stop to the next.
TrafficRoute buildTrafficRoute(
  HeardPacket p,
  Iterable<Node> known, {
  required String selfLabel,
  NodeKey? self,
  GeoPoint? selfAt,
  HopNaming? naming,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final candidates = [
    for (final n in known)
      if (n.radioId == p.radioId && n.key != self) n,
  ];
  Node? pick(HopId h, GeoPoint? previous) {
    final matches = matchHop(h, candidates);
    return switch (matches.length) {
      0 => null,
      1 => matches.single,
      _ => naming?.choose(h.id, matches, previous, at),
    };
  }

  final stops = <TrafficStop>[];
  GeoPoint? previous;
  if (p.origin case final o?) {
    final node = pick(o, selfAt);
    final where = node?.position ?? p.originAt;
    stops.add(
      TrafficStop(
        label: node?.displayName ?? p.originName ?? hopLabel(o),
        role: StopRole.origin,
        node: node,
        at: where,
      ),
    );
    previous = where;
  }
  for (final h in p.hops) {
    final node = pick(h, previous);
    // A relay that is the sender itself adds nothing.
    if (node != null && stops.isNotEmpty && stops.last.node?.key == node.key) {
      continue;
    }
    stops.add(
      TrafficStop(
        label: node?.displayName ?? hopLabel(h),
        role: StopRole.hop,
        node: node,
        at: node?.position,
      ),
    );
    previous = node?.position ?? previous;
  }
  stops.add(TrafficStop(label: selfLabel, role: StopRole.self, at: selfAt));
  return TrafficRoute(p, stops);
}

/// The newest packets a radio heard for the Traffic map; notifies on each.
class TrafficLog extends ChangeNotifier {
  TrafficLog({this.capacity = 50});

  final int capacity;
  final ListQueue<HeardPacket> _recent = ListQueue();
  int _count = 0;

  /// Packets added so far, ever; tells listeners how many are new.
  int get count => _count;

  /// The newest packets, oldest first.
  List<HeardPacket> get recent => List.unmodifiable(_recent);

  /// The packets added after the first [seen] of [count].
  List<HeardPacket> since(int seen) {
    final fresh = (_count - seen).clamp(0, _recent.length);
    return _recent.toList().sublist(_recent.length - fresh);
  }

  void add(HeardPacket p) {
    _recent.addLast(p);
    while (_recent.length > capacity) {
      _recent.removeFirst();
    }
    _count++;
    notifyListeners();
  }
}
