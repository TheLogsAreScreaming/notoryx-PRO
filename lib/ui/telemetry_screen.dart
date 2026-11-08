import 'package:flutter/material.dart';

import '../mesh/mesh.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'line_chart.dart';

/// A node's battery, radio load and sensor readings over time.
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({
    super.key,
    required this.store,
    required this.radioId,
    required this.node,
    required this.name,
    this.now,
  });

  final MeshStore store;
  final RadioId radioId;
  final NodeKey node;
  final String name;

  /// The current time; replaceable in tests.
  final DateTime Function()? now;

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  static const _ranges = [Duration(days: 1), Duration(days: 7), telemetryKeep];
  Duration _range = _ranges.first;
  late Stream<List<TelemetryPoint>> _points = _watch();

  Stream<List<TelemetryPoint>> _watch() => widget.store.watchTelemetry(
    widget.radioId,
    widget.node,
    since: (widget.now ?? DateTime.now)().subtract(_range),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.telemetryTitle(widget.name))),
      body: StreamBuilder<List<TelemetryPoint>>(
        stream: _points,
        builder: (context, snap) {
          final points = snap.data ?? const <TelemetryPoint>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<Duration>(
                segments: [
                  ButtonSegment(value: _ranges[0], label: Text(l.telemetryDay)),
                  ButtonSegment(
                    value: _ranges[1],
                    label: Text(l.telemetryWeek),
                  ),
                  ButtonSegment(
                    value: _ranges[2],
                    label: Text(l.telemetryFortnight),
                  ),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() {
                  _range = s.first;
                  _points = _watch();
                }),
              ),
              const SizedBox(height: 8),
              if (!snap.hasData)
                const Center(child: CircularProgressIndicator())
              else if (points.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text(l.telemetryEmpty, textAlign: TextAlign.center),
                )
              else ...[
                Text(l.telemetryReadings(points.length)),
                ..._charts(context, points),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _charts(BuildContext context, List<TelemetryPoint> points) {
    final l = context.l10n;
    String pct(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0)}%';
    final latestBattery = points.lastWhere(
      (p) => p.batteryLevel != null,
      orElse: () => points.last,
    );
    return [
      _MetricChart(
        title: l.telemetryBattery,
        values: [
          for (final p in points)
            if (p.batteryLevel case final b? when b <= 100) b.toDouble(),
        ],
        format: (v) => '${v.round()}%',
        note: latestBattery.isPowered ? l.telemetryPowered : null,
      ),
      _MetricChart(
        title: l.telemetryVoltage,
        values: [for (final p in points) ?p.voltage],
        format: (v) => '${v.toStringAsFixed(2)} V',
      ),
      _MetricChart(
        title: l.telemetryChannel,
        values: [for (final p in points) ?p.channelUtilization],
        format: pct,
      ),
      _MetricChart(
        title: l.telemetryAirtime,
        values: [for (final p in points) ?p.airUtilTx],
        format: pct,
      ),
      _MetricChart(
        title: l.telemetryTemperature,
        values: [for (final p in points) ?p.temperature],
        format: (v) => '${v.toStringAsFixed(1)} °C',
      ),
      _MetricChart(
        title: l.telemetryHumidity,
        values: [for (final p in points) ?p.relativeHumidity],
        format: (v) => '${v.round()}%',
      ),
      _MetricChart(
        title: l.telemetryPressure,
        values: [for (final p in points) ?p.barometricPressure],
        format: (v) => '${v.round()} hPa',
      ),
    ];
  }
}

/// One reading over time: latest value, range and a line.
class _MetricChart extends StatelessWidget {
  const _MetricChart({
    required this.title,
    required this.values,
    required this.format,
    this.note,
  });

  final String title;
  final List<double> values;
  final String Function(double) format;
  final String? note;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty && note == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        trailing: Text(note!, style: theme.textTheme.titleMedium),
      );
    }
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final latest = format(values.last);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Semantics(
        container: true,
        label: l.telemetryChartLabel(title, latest, format(low), format(high)),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                  Text(
                    note == null ? latest : '$latest · $note',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              Text(
                l.telemetryRange(format(low), format(high)),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: LineChart(
                    values,
                    color: theme.colorScheme.primary,
                    grid: theme.colorScheme.outlineVariant,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
