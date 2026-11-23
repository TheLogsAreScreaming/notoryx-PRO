import 'package:flutter/material.dart';

import '../app/telemetry_alerts.dart';
import '../mesh/mesh.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'line_chart.dart';
import 'list_insets.dart';

/// A node's battery, radio load and sensor readings over time.
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({
    super.key,
    required this.store,
    required this.radioId,
    required this.node,
    required this.name,
    this.now,
    this.alerts,
    this.readNow,
  });

  /// Where alert limits are kept; no alert buttons without it.
  final TelemetryAlerts? alerts;

  /// Asks the node for a reading now, where its radio can.
  final Future<void> Function()? readNow;

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
  static const _ranges = [
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(days: 1),
    Duration(days: 7),
    telemetryKeep,
  ];
  Duration _range = _ranges[2];
  bool _reading = false;
  Map<TelemetryValue, TelemetryLimit> _limits = const {};

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  Future<void> _loadLimits() async {
    final a = widget.alerts;
    if (a == null) return;
    final limits = <TelemetryValue, TelemetryLimit>{
      for (final v in TelemetryValue.values)
        v: ?await a.limitFor(widget.radioId, widget.node, v),
    };
    if (mounted) setState(() => _limits = limits);
  }

  Future<void> _read() async {
    final read = widget.readNow;
    if (read == null) return;
    setState(() => _reading = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await read();
    } on Object catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.telemetryReadFailed)));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _editLimit(TelemetryValue v, String title, String unit) async {
    final a = widget.alerts;
    if (a == null) return;
    final result = await showDialog<TelemetryLimit>(
      context: context,
      builder: (_) =>
          _LimitDialog(title: title, unit: unit, current: _limits[v]),
    );
    if (result == null) return;
    await a.setLimit(widget.radioId, widget.node, v, result);
    await _loadLimits();
  }

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
      appBar: AppBar(
        title: Text(l.telemetryTitle(widget.name)),
        actions: [
          if (widget.readNow != null)
            IconButton(
              key: const Key('telemetry-read'),
              tooltip: l.telemetryReadNow,
              onPressed: _reading ? null : _read,
              icon: _reading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      body: StreamBuilder<List<TelemetryPoint>>(
        stream: _points,
        builder: (context, snap) {
          final points = snap.data ?? const <TelemetryPoint>[];
          return ListView(
            padding: withBottomInset(context, const EdgeInsets.all(16)),
            children: [
              SegmentedButton<Duration>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _ranges[0],
                    label: Text(l.telemetryHour),
                  ),
                  ButtonSegment(
                    value: _ranges[1],
                    label: Text(l.telemetrySixHours),
                  ),
                  ButtonSegment(value: _ranges[2], label: Text(l.telemetryDay)),
                  ButtonSegment(
                    value: _ranges[3],
                    label: Text(l.telemetryWeek),
                  ),
                  ButtonSegment(
                    value: _ranges[4],
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

  /// The alert line under a chart; null without an alert store.
  Widget? _alert(TelemetryValue v, String title, String unit) {
    if (widget.alerts == null) return null;
    final l = context.l10n;
    final limit = _limits[v];
    String n(double x) => '${x % 1 == 0 ? x.round() : x} $unit';
    final text = limit == null
        ? l.telemetryNoAlert
        : [
            if (limit.above != null) l.telemetryAlertAbove(n(limit.above!)),
            if (limit.below != null) l.telemetryAlertBelow(n(limit.below!)),
          ].join(' · ');
    return Row(
      children: [
        Icon(
          limit == null ? Icons.notifications_none : Icons.notifications_active,
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(
          key: Key('telemetry-alert-${v.name}'),
          onPressed: () => _editLimit(v, title, unit),
          child: Text(l.telemetrySetAlert),
        ),
      ],
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
        alert: _alert(TelemetryValue.battery, l.telemetryBattery, '%'),
      ),
      _MetricChart(
        title: l.telemetryVoltage,
        values: [for (final p in points) ?p.voltage],
        format: (v) => '${v.toStringAsFixed(2)} V',
        alert: _alert(TelemetryValue.voltage, l.telemetryVoltage, 'V'),
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
        alert: _alert(TelemetryValue.temperature, l.telemetryTemperature, '°C'),
      ),
      _MetricChart(
        title: l.telemetryHumidity,
        values: [for (final p in points) ?p.relativeHumidity],
        format: (v) => '${v.round()}%',
        alert: _alert(TelemetryValue.humidity, l.telemetryHumidity, '%'),
      ),
      _MetricChart(
        title: l.telemetryPressure,
        values: [for (final p in points) ?p.barometricPressure],
        format: (v) => '${v.round()} hPa',
        alert: _alert(TelemetryValue.pressure, l.telemetryPressure, 'hPa'),
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
    this.alert,
  });

  /// Alert line shown under the chart.
  final Widget? alert;

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
    final chart = Padding(
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
    final a = alert;
    if (a == null) return chart;
    return Column(children: [chart, a]);
  }
}

/// Above / below limits for one value.
class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.title, required this.unit, this.current});

  final String title;
  final String unit;
  final TelemetryLimit? current;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final _above = TextEditingController(
    text: widget.current?.above?.toString() ?? '',
  );
  late final _below = TextEditingController(
    text: widget.current?.below?.toString() ?? '',
  );

  @override
  void dispose() {
    _above.dispose();
    _below.dispose();
    super.dispose();
  }

  double? _parse(String t) => double.tryParse(t.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final above = _parse(_above.text), below = _parse(_below.text);
    final bad = above != null && below != null && below >= above;
    const keys = TextInputType.numberWithOptions(decimal: true, signed: true);
    return AlertDialog(
      title: Text(l.telemetryAlertTitle(widget.title)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.telemetryAlertHint),
          TextField(
            key: const Key('limit-above'),
            controller: _above,
            keyboardType: keys,
            decoration: InputDecoration(
              labelText: l.telemetryAbove,
              suffixText: widget.unit,
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('limit-below'),
            controller: _below,
            keyboardType: keys,
            decoration: InputDecoration(
              labelText: l.telemetryBelow,
              suffixText: widget.unit,
              errorText: bad ? l.telemetryBelowTooHigh : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const TelemetryLimit()),
            child: Text(l.telemetryRemoveAlert),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('limit-save'),
          onPressed: bad
              ? null
              : () => Navigator.pop(
                  context,
                  TelemetryLimit(above: above, below: below),
                ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
