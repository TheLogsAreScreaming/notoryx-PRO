import 'dart:async';
import 'dart:convert';

import '../mesh/mesh.dart';
import '../store/mesh_store.dart';
import 'message_alerts.dart';

/// A value a telemetry alert can watch.
enum TelemetryValue { battery, voltage, temperature, humidity, pressure }

double? telemetryValue(TelemetryPoint p, TelemetryValue v) => switch (v) {
  TelemetryValue.battery =>
    p.batteryLevel == null || p.batteryLevel! > 100
        ? null
        : p.batteryLevel!.toDouble(),
  TelemetryValue.voltage => p.voltage,
  TelemetryValue.temperature => p.temperature,
  TelemetryValue.humidity => p.relativeHumidity,
  TelemetryValue.pressure => p.barometricPressure,
};

/// Alert limits for one node's value; either side may be unset.
class TelemetryLimit {
  const TelemetryLimit({this.above, this.below});

  final double? above;
  final double? below;

  bool get isEmpty => above == null && below == null;

  /// true when [v] is above, false when below, null when within.
  bool? outside(double v) {
    if (above != null && v > above!) return true;
    if (below != null && v < below!) return false;
    return null;
  }

  Map<String, double> toJson() => {'above': ?above, 'below': ?below};

  static TelemetryLimit? fromJson(Object? json) {
    if (json is! Map) return null;
    double? d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final l = TelemetryLimit(above: d(json['above']), below: d(json['below']));
    return l.isEmpty ? null : l;
  }
}

/// Notifies when a node's telemetry value crosses a limit the person set.
///
/// Only a crossing alerts (not every reading past the line), and each
/// node and value stays quiet for [gap] after alerting.
class TelemetryAlerts {
  TelemetryAlerts({
    required this.store,
    this.notifier,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _sub = store.newTelemetry.listen((p) => unawaited(check(p)));
  }

  static const gap = Duration(minutes: 30);
  static const _pref = 'telemetry_alerts_v1';

  final MeshStore store;
  final Notifier? notifier;
  final DateTime Function() _now;
  late final StreamSubscription<TelemetryPoint> _sub;
  final Map<String, double> _last = {};
  final Map<String, DateTime> _alerted = {};

  /// Writes the notification text; replaced with the person's language.
  String Function(
    String node,
    TelemetryValue value,
    double now,
    double limit,
    bool above,
  )
  describe = (node, value, now, limit, above) =>
      '$node: ${value.name} $now ${above ? '>' : '<'} $limit';

  /// The alert title; replaced with the person's language.
  String title = 'Sensor alert';

  static String _id(RadioId r, NodeKey n, TelemetryValue v) =>
      '$r|$n|${v.name}';

  Future<Map<String, TelemetryLimit>> _limits() async {
    final raw = await store.preference(_pref);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in m.entries)
          if (key is String) key: ?TelemetryLimit.fromJson(value),
      };
    } on FormatException {
      return {};
    }
  }

  Future<TelemetryLimit?> limitFor(
    RadioId r,
    NodeKey n,
    TelemetryValue v,
  ) async => (await _limits())[_id(r, n, v)];

  /// Sets (or with null or an empty limit, clears) one alert.
  Future<void> setLimit(
    RadioId r,
    NodeKey n,
    TelemetryValue v,
    TelemetryLimit? limit,
  ) async {
    final all = await _limits();
    final id = _id(r, n, v);
    if (limit == null || limit.isEmpty) {
      all.remove(id);
    } else {
      all[id] = limit;
    }
    _alerted.remove(id);
    await store.setPreference(
      _pref,
      jsonEncode(all.map((k, l) => MapEntry(k, l.toJson()))),
    );
  }

  /// Looks at one new reading.
  Future<void> check(TelemetryPoint p) async {
    final limits = await _limits();
    for (final v in TelemetryValue.values) {
      final value = telemetryValue(p, v);
      if (value == null) continue;
      final id = _id(p.radioId, p.node, v);
      final before = _last[id];
      _last[id] = value;
      final limit = limits[id];
      if (limit == null) continue;
      final side = limit.outside(value);
      if (side == null) continue;
      if (before != null && limit.outside(before) == side) continue;
      final last = _alerted[id];
      if (last != null && _now().difference(last) < gap) continue;
      _alerted[id] = _now();
      final node = await store.node(p.radioId, p.node);
      await notifier?.show(
        id: id.hashCode,
        title: title,
        body: describe(
          node?.displayName ?? p.node.short,
          v,
          value,
          side ? limit.above! : limit.below!,
          side,
        ),
        payload: '',
      );
    }
  }

  void dispose() => unawaited(_sub.cancel());
}
