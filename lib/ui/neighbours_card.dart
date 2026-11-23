import 'package:flutter/material.dart';

import '../app/status_history.dart';
import '../l10n/app_localizations.dart';
import '../mesh/mesh.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'line_chart.dart';

/// A repeater's latest neighbour list; each row opens that neighbour's SNR
/// over every list read so far.
class NeighboursCard extends StatelessWidget {
  const NeighboursCard({
    super.key,
    required this.store,
    required this.server,
    required this.neighbours,
  });

  final MeshStore store;
  final Node server;
  final List<NeighbourReading> neighbours;

  Future<Map<String, String>> _names() async {
    final nodes = await store.nodes(server.radioId);
    return {
      for (final n in neighbours)
        n.prefix:
            nodes
                .where((m) => m.key.native.toLowerCase().startsWith(n.prefix))
                .firstOrNull
                ?.displayName ??
            n.prefix.toUpperCase(),
    };
  }

  static String _ago(AppLocalizations l, int seconds) {
    if (seconds < 60) return l.neighboursSecondsAgo(seconds);
    if (seconds < 3600) return l.neighboursMinutesAgo(seconds ~/ 60);
    return l.neighboursHoursAgo(seconds ~/ 3600);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, String>>(
      future: _names(),
      builder: (context, snap) {
        final names = snap.data ?? const <String, String>{};
        return Column(
          key: const Key('neighbours'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Text(
              l.neighboursTitle(neighbours.length),
              style: theme.textTheme.titleMedium,
            ),
            if (neighbours.isEmpty) Text(l.neighboursNone),
            for (final n in neighbours)
              ListTile(
                key: Key('neighbour-${n.prefix}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cell_tower),
                title: Text(names[n.prefix] ?? n.prefix.toUpperCase()),
                subtitle: Text(_ago(l, n.secondsAgo)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${n.snr.toStringAsFixed(1)} dB'),
                    const SizedBox(width: 8),
                    Icon(Icons.show_chart, semanticLabel: l.neighboursChart),
                  ],
                ),
                onTap: () => _showTrend(
                  context,
                  n.prefix,
                  names[n.prefix] ?? n.prefix.toUpperCase(),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showTrend(BuildContext context, String prefix, String name) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FutureBuilder<Map<String, List<SnrPoint>>>(
              future: NeighbourHistory(store).load(server.radioId, server.key),
              builder: (context, snap) {
                final l = context.l10n;
                final theme = Theme.of(context);
                final points = snap.data?[prefix] ?? const <SnrPoint>[];
                final values = [for (final p in points) p.snr];
                String db(double v) => '${v.toStringAsFixed(1)} dB';
                return Column(
                  key: const Key('neighbour-trend'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.neighboursTrendTitle(name),
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(l.neighboursTrendHint),
                    const SizedBox(height: 12),
                    if (values.isNotEmpty) ...[
                      Text(
                        l.telemetryRange(
                          db(values.reduce((a, b) => a < b ? a : b)),
                          db(values.reduce((a, b) => a > b ? a : b)),
                        ),
                      ),
                      Text(
                        l.neighboursReadings(values.length),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        container: true,
                        label: l.telemetryChartLabel(
                          'SNR',
                          db(values.last),
                          db(values.reduce((a, b) => a < b ? a : b)),
                          db(values.reduce((a, b) => a > b ? a : b)),
                        ),
                        child: ExcludeSemantics(
                          child: SizedBox(
                            height: 140,
                            child: CustomPaint(
                              painter: LineChart(
                                values,
                                color: theme.colorScheme.primary,
                                grid: theme.colorScheme.outlineVariant,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );
}
