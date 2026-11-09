import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../radio/radio_link.dart';
import 'model.dart';

/// One packet the radio heard or relayed to the app, for the live log.
class PacketLogEntry {
  const PacketLogEntry({
    required this.time,
    required this.protocol,
    required this.kind,
    this.from,
    this.to,
    this.path = PathFacts.none,
    this.bytes,
    this.detail,
    this.encrypted = false,
    this.otherMesh = false,
  });

  final DateTime time;
  final RadioProtocol protocol;

  /// What it carries: "Advert", "Channel message", "Position", …
  final String kind;

  /// Sender, when the packet says (Meshtastic always does; MeshCore keeps
  /// it inside the encrypted payload).
  final String? from;
  final String? to;
  final PathFacts path;
  final int? bytes;

  /// Extra facts, e.g. the MeshCore path hashes.
  final String? detail;

  /// The payload couldn't be read by this radio (another channel's key).
  final bool encrypted;

  /// Belongs to the other mesh, heard by accident.
  final bool otherMesh;
}

/// The Meshtastic sender in [raw] if a radio's raw packet is a Meshtastic
/// broadcast, else null.
///
/// Only broadcasts count: `ff ff ff ff` as the destination is distinctive,
/// and a MeshCore packet can't start that way in practice. The flags byte
/// must also hold a sane hop count (hops left never above hops at start).
int? meshtasticBroadcastSender(Uint8List raw) {
  if (raw.length < 16) return null;
  if (raw.sublist(0, 4).any((b) => b != 0xff)) return null;
  final from = ByteData.sublistView(raw).getUint32(4, Endian.little);
  if (from == 0 || from == 0xffffffff) return null;
  final flags = raw[12];
  final hopLimit = flags & 0x07;
  final hopStart = flags >> 5;
  return hopStart != 0 && hopLimit > hopStart ? null : from;
}

/// What a radio has heard of the other mesh since connecting.
class OtherMeshSummary {
  const OtherMeshSummary({
    required this.packets,
    required this.senders,
    required this.lastHeard,
    this.strongestRssi,
  });

  final int packets;
  final int senders;
  final DateTime lastHeard;
  final int? strongestRssi;
}

/// The newest [capacity] packets, oldest first; notifies on each new one.
class PacketLog extends ChangeNotifier {
  PacketLog({this.capacity = 500});

  final int capacity;
  final ListQueue<PacketLogEntry> _entries = ListQueue();
  bool _paused = false;

  List<PacketLogEntry> get entries => List.unmodifiable(_entries);

  /// While paused, packets are still counted but the list stops moving.
  bool get paused => _paused;
  set paused(bool value) {
    _paused = value;
    notifyListeners();
  }

  int _dropped = 0;

  /// Packets heard while paused and not shown.
  int get missedWhilePaused => _dropped;

  int _otherPackets = 0;
  final Set<String> _otherSenders = {};
  DateTime? _otherLast;
  int? _otherRssi;

  /// The other mesh's traffic so far; null if none. Clearing the log
  /// keeps it, and it still counts while paused.
  OtherMeshSummary? get otherMesh => _otherLast == null
      ? null
      : OtherMeshSummary(
          packets: _otherPackets,
          senders: _otherSenders.length,
          lastHeard: _otherLast!,
          strongestRssi: _otherRssi,
        );

  void add(PacketLogEntry e) {
    if (e.otherMesh) {
      _otherPackets++;
      if (e.from != null) _otherSenders.add(e.from!);
      _otherLast = e.time;
      final rssi = e.path.rssi;
      if (rssi != null && (_otherRssi == null || rssi > _otherRssi!)) {
        _otherRssi = rssi;
      }
    }
    if (_paused) {
      _dropped++;
      notifyListeners();
      return;
    }
    _entries.addLast(e);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _dropped = 0;
    notifyListeners();
  }
}

/// One reading of how busy and noisy the channel is.
class RadioSample {
  const RadioSample({
    required this.time,
    this.noiseFloor,
    this.channelUtilization,
    this.airUtilTx,
    this.lastSnr,
    this.lastRssi,
  });

  final DateTime time;

  /// Background noise in dBm (MeshCore; newer Meshtastic firmware).
  final int? noiseFloor;

  /// Percent of time the channel is busy (Meshtastic).
  final double? channelUtilization;

  /// Percent of the last hour spent transmitting (Meshtastic).
  final double? airUtilTx;
  final double? lastSnr;
  final int? lastRssi;
}

/// Readings over time, newest last, at most [capacity].
class RadioSamples extends ChangeNotifier {
  RadioSamples({this.capacity = 240});

  final int capacity;
  final ListQueue<RadioSample> _samples = ListQueue();

  List<RadioSample> get samples => List.unmodifiable(_samples);
  RadioSample? get latest => _samples.isEmpty ? null : _samples.last;

  void add(RadioSample s) {
    _samples.addLast(s);
    while (_samples.length > capacity) {
      _samples.removeFirst();
    }
    notifyListeners();
  }
}

/// One hop of a trace: who, and how well they heard it.
class TraceHop {
  const TraceHop(this.label, this.snr, {this.node});

  /// Node name, or its ID/hash when unknown.
  final String label;

  /// SNR in dB at the receiving end of this hop; null when not reported.
  final double? snr;
  final Node? node;
}

/// The result of a trace path / traceroute, protocol-neutral.
class TraceResult {
  const TraceResult({
    required this.target,
    required this.towards,
    this.back = const [],
    required this.time,
  });

  final NodeKey target;

  /// Hops from us towards the target (the last is the target or last
  /// repeater).
  final List<TraceHop> towards;

  /// Hops on the way back, when the protocol reports them.
  final List<TraceHop> back;
  final DateTime time;

  /// The weakest hop, if any SNR was reported.
  TraceHop? get weakest {
    final known = [...towards, ...back].where((h) => h.snr != null).toList();
    if (known.isEmpty) return null;
    known.sort((a, b) => a.snr!.compareTo(b.snr!));
    return known.first;
  }
}

/// A finished trace kept in the database.
class SavedTrace {
  const SavedTrace({
    required this.id,
    required this.targetName,
    required this.result,
  });

  final int id;

  /// What the node was called when it was traced.
  final String targetName;

  /// The trace; its hops keep their names and SNR but not their [Node]s.
  final TraceResult result;
}

/// A likely reason a message didn't arrive, with what to try.
enum DeliveryHint {
  /// The recipient hasn't been heard for a long time.
  notHeardRecently,

  /// No known route; the message had to flood.
  noRoute,

  /// The route is long; each hop can lose it.
  longRoute,

  /// The last hop's signal is weak.
  weakSignal,

  /// MeshCore: the recipient must have you as a contact to decrypt it.
  needsYourContact,

  /// Meshtastic: the node doesn't know your key yet.
  unknownKey,

  /// The radio itself couldn't send (queue full, duty cycle).
  radioBusy,
}

/// Works out likely reasons an outgoing direct message failed or is slow.
///
/// [recipient] is the stored node, if known; [now] is for tests.
List<DeliveryHint> diagnoseDelivery(
  Message message,
  Node? recipient, {
  DateTime? now,
}) {
  if (!message.outgoing) return const [];
  final state = message.delivery;
  if (state is Delivered || state is Received) return const [];
  final hints = <DeliveryHint>[];
  final reason = state is Failed ? state.reason.toLowerCase() : '';
  if (reason.contains('key')) hints.add(DeliveryHint.unknownKey);
  if (reason.contains('busy') ||
      reason.contains('duty') ||
      reason.contains('full') ||
      reason.contains('too fast')) {
    hints.add(DeliveryHint.radioBusy);
  }
  if (message.conversation is! DirectConversation) return hints;
  final n = recipient;
  if (n == null) return hints;
  final heard = n.lastHeard;
  final t = now ?? DateTime.now();
  if (heard == null || t.difference(heard) > const Duration(hours: 24)) {
    hints.add(DeliveryHint.notHeardRecently);
  }
  if (n.protocol == RadioProtocol.meshcore) {
    if (n.path.route == RouteKind.flood || n.path.hops == null) {
      hints.add(DeliveryHint.noRoute);
    }
    if (state is Failed && !hints.contains(DeliveryHint.unknownKey)) {
      hints.add(DeliveryHint.needsYourContact);
    }
  }
  if ((n.path.hops ?? 0) >= 4) hints.add(DeliveryHint.longRoute);
  final snr = n.path.snr;
  if (snr != null && snr < -7) hints.add(DeliveryHint.weakSignal);
  return hints;
}

/// Radio line-of-sight numbers between two points, without terrain data.
///
/// Uses a 4/3-Earth radius for normal refraction. It tells you how high
/// both antennas must be above any obstacle at mid-path; it can't tell
/// whether a hill is in the way.
class LineOfSight {
  LineOfSight._(this.distanceKm, this.fresnelM, this.earthBulgeM);

  /// Works it out for [a]→[b] at [frequencyMHz].
  factory LineOfSight.between(GeoPoint a, GeoPoint b, double frequencyMHz) {
    final d = haversineKm(a, b);
    final half = d / 2;
    // First Fresnel zone radius at mid-path: 17.32·√(d1·d2 / (f·d)), km/GHz.
    final fGHz = frequencyMHz / 1000;
    final fresnel = d == 0 ? 0.0 : 17.32 * math.sqrt(half * half / (fGHz * d));
    // Earth bulge at mid-path with k = 4/3: d1·d2 / (12.75·k) metres.
    final bulge = half * half / (12.75 * (4 / 3));
    return LineOfSight._(d, fresnel, bulge);
  }

  final double distanceKm;

  /// Radius of the first Fresnel zone at mid-path, metres.
  final double fresnelM;

  /// How far the Earth's curve rises into the path at mid-point, metres.
  final double earthBulgeM;

  /// Clearance needed above obstacles at mid-path: the bulge plus 60 % of
  /// the Fresnel zone (the usual rule for a clean link), metres.
  double get clearanceM => earthBulgeM + 0.6 * fresnelM;
}

/// Great-circle distance in km.
double haversineKm(GeoPoint a, GeoPoint b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}
