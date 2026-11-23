import 'package:flutter/material.dart';

import '../app/status_history.dart';
import '../mesh/mesh.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'line_chart.dart';

/// A repeater's saved status checks as a chart, by value and time range.
class StatusHistoryCard extends StatefulWidget {
  const StatusHistoryCard({
    super.key,
    required this.store,
    required this.node,
    required this.version,
    this.now,
  });

  final MeshStore store;
  final Node node;

  /// Bumped after each new status check, so the card reloads.
  final int version;

  /// The current time; replaceable in tests.
  final DateTime Function()? now;

  @override
  State<StatusHistoryCard> createState() => _StatusHistoryCardState();
}

class _StatusHistoryCardState extends State<StatusHistoryCard> {
  static const _ranges = [
    Duration(days: 1),
    Duration(days: 7),
    StatusHistory.keep,
  ];
  StatusMetric _metric = StatusMetric.battery;
  Duration _range = _ranges[1];
  late Future<List<StatusCheck>> _checks = _load();

  Future<List<StatusCheck>> _load() =>
      StatusHistory(widget.store).load(widget.node.radioId, widget.node.key);

  @override
  void didUpdateWidget(StatusHistoryCard old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version || old.node.key != widget.node.key) {
      _checks = _load();
    }
  }

  String _name(BuildContext context, StatusMetric m) {
    final l = context.l10n;
    return switch (m) {
      StatusMetric.battery => l.statusBattery,
      StatusMetric.rssi => l.statusHistoryRssi,
      StatusMetric.snr => l.statusHistorySnr,
      StatusMetric.noiseFloor => l.statusNoise,
      StatusMetric.errors => l.statusHistoryErrors,
      StatusMetric.uptime => l.statusUptime,
    };
  }

  String _format(StatusMetric m, double v) => switch (m) {
    StatusMetric.battery => '${v.toStringAsFixed(2)} V',
    StatusMetric.snr => '${v.toStringAsFixed(1)} dB',
    StatusMetric.rssi || StatusMetric.noiseFloor => '${v.round()} dBm',
    StatusMetric.errors => '${v.round()}',
    StatusMetric.uptime => '${v.toStringAsFixed(v < 10 ? 1 : 0)} h',
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return FutureBuilder<List<StatusCheck>>(
      future: _checks,
      builder: (context, snap) {
        final all = snap.data ?? const <StatusCheck>[];
        final since = (widget.now ?? DateTime.now)().subtract(_range);
        final values = [
          for (final c in all)
            if (!c.time.isBefore(since)) c.value(_metric),
        ];
        final name = _name(context, _metric);
        return Column(
          key: const Key('status-history'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Text(l.statusHistoryTitle, style: theme.textTheme.titleMedium),
            Text(
              l.statusHistoryCount(all.length),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in StatusMetric.values)
                  ChoiceChip(
                    label: Text(_name(context, m)),
                    selected: _metric == m,
                    onSelected: (_) => setState(() => _metric = m),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<Duration>(
              segments: [
                ButtonSegment(value: _ranges[0], label: Text(l.telemetryDay)),
                ButtonSegment(value: _ranges[1], label: Text(l.telemetryWeek)),
                ButtonSegment(
                  value: _ranges[2],
                  label: Text(l.statusHistoryMonth),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
            const SizedBox(height: 8),
            if (values.isEmpty)
              Text(
                all.isEmpty ? l.statusHistoryEmpty : l.statusHistoryNoneInRange,
                style: theme.textTheme.bodySmall,
              )
            else
              _chart(context, name, values),
          ],
        );
      },
    );
  }

  Widget _chart(BuildContext context, String name, List<double> values) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final latest = _format(_metric, values.last);
    final lo = _format(_metric, low), hi = _format(_metric, high);
    return Semantics(
      container: true,
      label: l.telemetryChartLabel(name, latest, lo, hi),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
                Text(latest, style: theme.textTheme.titleMedium),
              ],
            ),
            Text(l.telemetryRange(lo, hi), style: theme.textTheme.bodySmall),
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
    );
  }
}
