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

/// A node a repeater has heard directly: key prefix (lower-case hex), how
/// long ago, and the SNR of that packet in dB.
typedef NeighbourReading = ({String prefix, int secondsAgo, double snr});

final _neighbourLine = RegExp(r'^([0-9A-Fa-f]{2,64}):(\d+):(-?\d+)$');

/// Reads a repeater's reply to the `neighbors` command: one
/// `PREFIX:SECONDS:SNR` line each, SNR in quarter-dB. `-none-` means it
/// hasn't heard anyone. Null when [reply] isn't that reply.
List<NeighbourReading>? parseNeighbours(String reply) {
  final text = reply.replaceFirst(RegExp(r'^\s*>\s*'), '').trim();
  if (text == '-none-') return const [];
  final out = <NeighbourReading>[];
  for (final line in text.split('\n')) {
    final m = _neighbourLine.firstMatch(line.trim());
    if (m == null) return null;
    out.add((
      prefix: m[1]!.toLowerCase(),
      secondsAgo: int.parse(m[2]!),
      snr: int.parse(m[3]!) / 4,
    ));
  }
  return out.isEmpty ? null : out;
}

/// One neighbour's SNR at one moment.
typedef SnrPoint = ({DateTime time, double snr});

/// Each neighbour's SNR every time a repeater's neighbour list was read,
/// kept for a month in the app's database.
class NeighbourHistory {
  const NeighbourHistory(this.store);

  final MeshStore store;

  static const maxPerNeighbour = 200;
  static const maxNeighbours = 64;

  static String _key(RadioId radio, NodeKey server) =>
      'neighbour_snr_v1:$radio:$server';

  /// Every neighbour's readings, oldest first, by key prefix.
  Future<Map<String, List<SnrPoint>>> load(
    RadioId radio,
    NodeKey server,
  ) async {
    final raw = await store.preference(_key(radio, server));
    if (raw == null || raw.isEmpty) return const {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in data.entries)
          if (key is String && value is List)
            key: [
              for (final p in value)
                if (p is List && p.length == 2 && p[0] is int && p[1] is num)
                  (
                    time: DateTime.fromMillisecondsSinceEpoch(p[0] as int),
                    snr: (p[1] as num).toDouble(),
                  ),
            ],
      };
    } on FormatException {
      return const {};
    }
  }

  /// Keeps one neighbour list read at [now]. Each reading is placed when
  /// the repeater last heard that neighbour; the same reading reported
  /// again by a later read is kept once.
  Future<void> add(
    RadioId radio,
    NodeKey server,
    List<NeighbourReading> list,
    DateTime now,
  ) async {
    final all = {
      for (final e in (await load(radio, server)).entries) e.key: [...e.value],
    };
    final cutoff = now.subtract(StatusHistory.keep);
    for (final n in list) {
      final at = now.subtract(Duration(seconds: n.secondsAgo));
      final points = all.putIfAbsent(n.prefix, () => []);
      final repeat = points.any(
        (p) => p.time.difference(at).inSeconds.abs() < 90 && p.snr == n.snr,
      );
      if (!repeat) points.add((time: at, snr: n.snr));
    }
    for (final points in all.values) {
      points
        ..removeWhere((p) => p.time.isBefore(cutoff))
        ..sort((a, b) => a.time.compareTo(b.time));
      if (points.length > maxPerNeighbour) {
        points.removeRange(0, points.length - maxPerNeighbour);
      }
    }
    all.removeWhere((_, p) => p.isEmpty);
    if (all.length > maxNeighbours) {
      final newest = all.keys.toList()
        ..sort((a, b) => all[b]!.last.time.compareTo(all[a]!.last.time));
      for (final k in newest.skip(maxNeighbours)) {
        all.remove(k);
      }
    }
    await store.setPreference(
      _key(radio, server),
      jsonEncode({
        for (final e in all.entries)
          e.key: [
            for (final p in e.value) [p.time.millisecondsSinceEpoch, p.snr],
          ],
      }),
    );
  }
}
