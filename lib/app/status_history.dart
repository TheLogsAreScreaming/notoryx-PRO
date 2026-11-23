import 'dart:convert';

import '../mesh/mesh.dart';
import '../meshcore/meshcore.dart';
import '../store/mesh_store.dart';

/// What one repeater status reply said.
class StatusCheck {
  const StatusCheck({
    required this.time,
    required this.batteryMv,
    required this.rssi,
    required this.snr,
    required this.noiseFloor,
    required this.errors,
    required this.uptimeSeconds,
  });

  factory StatusCheck.fromPush(RepeaterStatusPush s, DateTime time) =>
      StatusCheck(
        time: time,
        batteryMv: s.batteryMv,
        rssi: s.lastRssi,
        snr: s.lastSnr,
        noiseFloor: s.noiseFloor,
        errors: s.errorEvents,
        uptimeSeconds: s.uptimeSeconds,
      );

  final DateTime time;
  final int batteryMv;
  final int rssi;
  final double snr;
  final int noiseFloor;
  final int errors;
  final int uptimeSeconds;

  double value(StatusMetric m) => switch (m) {
    StatusMetric.battery => batteryMv / 1000,
    StatusMetric.rssi => rssi.toDouble(),
    StatusMetric.snr => snr,
    StatusMetric.noiseFloor => noiseFloor.toDouble(),
    StatusMetric.errors => errors.toDouble(),
    StatusMetric.uptime => uptimeSeconds / 3600,
  };

  List<num> toJson() => [
    time.millisecondsSinceEpoch,
    batteryMv,
    rssi,
    snr,
    noiseFloor,
    errors,
    uptimeSeconds,
  ];

  static StatusCheck? fromJson(Object? json) {
    if (json is! List || json.length != 7) return null;
    if (json.any((v) => v is! num)) return null;
    final n = json.cast<num>();
    return StatusCheck(
      time: DateTime.fromMillisecondsSinceEpoch(n[0].toInt()),
      batteryMv: n[1].toInt(),
      rssi: n[2].toInt(),
      snr: n[3].toDouble(),
      noiseFloor: n[4].toInt(),
      errors: n[5].toInt(),
      uptimeSeconds: n[6].toInt(),
    );
  }
}

/// What a status chart can show.
enum StatusMetric { battery, rssi, snr, noiseFloor, errors, uptime }

/// Every status reply the user asked a repeater or room server for, kept
/// for a month in the app's database so it can be charted. Nothing is
/// sent for this; it only keeps the replies that came back.
class StatusHistory {
  const StatusHistory(this.store);

  final MeshStore store;

  static const keep = Duration(days: 30);
  static const maxChecks = 500;

  static String _key(RadioId radio, NodeKey node) =>
      'status_history_v1:$radio:$node';

  /// The kept checks of [node], oldest first.
  Future<List<StatusCheck>> load(RadioId radio, NodeKey node) async {
    final raw = await store.preference(_key(radio, node));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final item in list) ?StatusCheck.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }

  /// Adds [check] for [node] and drops checks past [keep] or [maxChecks].
  Future<void> add(
    RadioId radio,
    NodeKey node,
    StatusCheck check, {
    DateTime? now,
  }) async {
    final cutoff = (now ?? DateTime.now()).subtract(keep);
    final list = [
      for (final c in await load(radio, node))
        if (!c.time.isBefore(cutoff)) c,
      check,
    ]..sort((a, b) => a.time.compareTo(b.time));
    final kept = list.length > maxChecks
        ? list.sublist(list.length - maxChecks)
        : list;
    await store.setPreference(
      _key(radio, node),
      jsonEncode([for (final c in kept) c.toJson()]),
    );
  }

  /// Forgets [node]'s checks.
  Future<void> clear(RadioId radio, NodeKey node) =>
      store.setPreference(_key(radio, node), '[]');
}
