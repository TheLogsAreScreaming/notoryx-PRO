import 'dart:async';

import 'package:flutter/material.dart';

import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'map_tiles.dart';
import 'trace_card.dart';
import 'line_chart.dart';

/// Live packet log and radio readings for one connected radio.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, required this.connection});

  final RadioConnection connection;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '${l.diagnostics}: ${connection.radio?.name ?? connection.target.label}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ProtocolBadge(connection.protocol),
            ],
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: l.diagPackets),
              Tab(text: l.diagRadio),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PacketLogView(log: connection.packetLog),
            RadioStatsView(connection: connection),
          ],
        ),
      ),
    );
  }
}

/// Newest packets first, with pause and clear.
class PacketLogView extends StatelessWidget {
  const PacketLogView({super.key, required this.log});

  final PacketLog log;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final entries = log.entries.reversed.toList();
        final other = log.otherMesh;
        return Column(
          children: [
            if (other != null)
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(l.otherMeshHeard),
                subtitle: Text(
                  [
                    l.otherMeshCounts(other.packets, other.senders),
                    if (other.strongestRssi != null)
                      l.otherMeshRssi(other.strongestRssi!),
                    ago(context, other.lastHeard),
                  ].join(' · '),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: Icon(log.paused ? Icons.play_arrow : Icons.pause),
                    label: Text(log.paused ? l.diagResume : l.diagPause),
                    onPressed: () => log.paused = !log.paused,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.diagClear),
                    onPressed: log.clear,
                  ),
                  const Spacer(),
                  if (log.paused && log.missedWhilePaused > 0)
                    Flexible(child: Text(l.diagMissed(log.missedWhilePaused))),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? EmptyState(l.diagNoPackets, icon: Icons.podcasts)
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) =>
                          _PacketRow(entry: entries[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PacketRow extends StatelessWidget {
  const _PacketRow({required this.entry});

  final PacketLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final e = entry;
    final t = e.time;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final facts = [
      if (e.from != null) e.from!,
      if (e.to != null) '→ ${e.to}',
      if (pathSummary(context, e.path) case final p when p.isNotEmpty) p,
      if (e.bytes != null) '${e.bytes} B',
      if (e.encrypted && e.protocol == RadioProtocol.meshtastic)
        l.diagEncrypted,
    ].join(' · ');
    return ListTile(
      dense: true,
      leading: SignalBars(signalBars(e.path)),
      title: Text('$time  ${e.kind}'),
      subtitle: Text(
        [facts, ?e.detail].where((s) => s.isNotEmpty).join('\n'),
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// Noise floor or channel activity over time, with the latest numbers.
class RadioStatsView extends StatefulWidget {
  const RadioStatsView({super.key, required this.connection});

  final RadioConnection connection;

  @override
  State<RadioStatsView> createState() => _RadioStatsViewState();
}

class _RadioStatsViewState extends State<RadioStatsView> {
  Timer? _timer;
  bool _unsupported = false;

  RadioConnection get c => widget.connection;

  @override
  void initState() {
    super.initState();
    if (c.protocol == RadioProtocol.meshcore) {
      _sample();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _sample());
    }
  }

  Future<void> _sample() async {
    try {
      final s = await c.sampleRadio();
      if (s == null && mounted) setState(() => _unsupported = true);
    } on Object {
      // Not connected right now; try again next tick.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: c.samples,
      builder: (context, _) {
        final samples = c.samples.samples;
        final latest = c.samples.latest;
        final useNoise = samples.any((s) => s.noiseFloor != null);
        final values = [
          for (final s in samples)
            (useNoise ? s.noiseFloor?.toDouble() : s.channelUtilization),
        ].nonNulls.toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              c.protocol == RadioProtocol.meshcore
                  ? l.diagMeshCoreSampling
                  : l.diagMeshtasticSampling,
            ),
            if (_unsupported) ...[
              const SizedBox(height: 8),
              Text(l.diagStatsUnsupported),
            ],
            const SizedBox(height: 16),
            if (latest == null)
              Text(l.diagNoSamples)
            else ...[
              if (latest.noiseFloor != null)
                _Stat(l.diagNoiseFloor, l.diagValueDbm(latest.noiseFloor!)),
              if (latest.channelUtilization != null)
                _Stat(
                  l.diagChannelBusy,
                  l.diagValuePercent(
                    latest.channelUtilization!.toStringAsFixed(1),
                  ),
                ),
              if (latest.airUtilTx != null)
                _Stat(
                  l.diagAirtime,
                  l.diagValuePercent(latest.airUtilTx!.toStringAsFixed(1)),
                ),
              if (latest.lastSnr != null || latest.lastRssi != null)
                _Stat(
                  l.diagLastSignal,
                  pathSummary(
                    context,
                    PathFacts(snr: latest.lastSnr, rssi: latest.lastRssi),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                useNoise ? l.diagNoiseFloor : l.diagChannelBusy,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: Semantics(
                  label: useNoise ? l.diagNoiseFloor : l.diagChannelBusy,
                  child: CustomPaint(
                    painter: LineChart(
                      values,
                      color: Theme.of(context).colorScheme.primary,
                      grid: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

/// Runs a trace to [node] and shows each hop's signal.
class TraceSheet extends StatefulWidget {
  const TraceSheet({
    super.key,
    required this.connection,
    required this.node,
    this.tiles,
  });

  final RadioConnection connection;
  final Node node;

  /// Map background for the shareable card.
  final MapTiles? tiles;

  @override
  State<TraceSheet> createState() => _TraceSheetState();
}

class _TraceSheetState extends State<TraceSheet> {
  late final Future<TraceResult> _trace = widget.connection.traceAndSave(
    widget.node,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FutureBuilder<TraceResult>(
          future: _trace,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                l.traceFailed(RadioConnection.describeError(snap.error!)),
              );
            }
            final r = snap.data;
            if (r == null) {
              return Row(
                children: [
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.traceRunning)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TraceDetails(result: r, targetName: widget.node.displayName),
                _ShareCardButton(
                  store: widget.connection.store,
                  radio: widget.node.radioId,
                  result: r,
                  targetName: widget.node.displayName,
                  tiles: widget.tiles,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The hops of one trace, each way, and which was weakest.
class TraceDetails extends StatelessWidget {
  const TraceDetails({
    super.key,
    required this.result,
    required this.targetName,
  });

  final TraceResult result;
  final String targetName;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget hops(List<TraceHop> list) => Column(
      children: [
        for (final h in list)
          ListTile(
            dense: true,
            leading: SignalBars(signalBars(PathFacts(snr: h.snr))),
            title: Text(h.label),
            trailing: Text(
              h.snr == null
                  ? l.traceNotReported
                  : l.pathSnr(h.snr!.toStringAsFixed(1)),
            ),
          ),
      ],
    );
    final title = Theme.of(context).textTheme.titleSmall;
    final weakest = result.weakest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.traceTowards(targetName), style: title),
        hops(result.towards),
        if (result.back.isNotEmpty) ...[
          Text(l.traceBack, style: title),
          hops(result.back),
        ],
        if (weakest != null) Text(l.traceWeakest(weakest.label)),
      ],
    );
  }
}

/// Opens the shareable card for one trace.
class _ShareCardButton extends StatelessWidget {
  const _ShareCardButton({
    required this.store,
    required this.radio,
    required this.result,
    required this.targetName,
    this.tiles,
  });

  final MeshStore store;
  final RadioId radio;
  final TraceResult result;
  final String targetName;
  final MapTiles? tiles;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      icon: const Icon(Icons.ios_share),
      label: Text(context.l10n.tcButton),
      onPressed: () => openTraceCard(
        context,
        store: store,
        radio: radio,
        result: result,
        targetName: targetName,
        tiles: tiles,
      ),
    ),
  );
}

/// A node's saved traces, newest first; tap one to see its hops.
class SavedTracesSheet extends StatefulWidget {
  const SavedTracesSheet({
    super.key,
    required this.store,
    required this.node,
    this.tiles,
  });

  final MeshStore store;
  final Node node;

  /// Map background for the shareable card.
  final MapTiles? tiles;

  @override
  State<SavedTracesSheet> createState() => _SavedTracesSheetState();
}

class _SavedTracesSheetState extends State<SavedTracesSheet> {
  late Future<List<SavedTrace>> _traces = _load();

  Future<List<SavedTrace>> _load() =>
      widget.store.traces(widget.node.radioId, widget.node.key);

  Future<void> _clear() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.traceClearConfirm(widget.node.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.traceClear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.clearTraces(widget.node.radioId, widget.node.key);
    if (!mounted) return;
    final next = _load();
    setState(() {
      _traces = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    String when(DateTime t) {
      final local = t.toLocal();
      return '${m.formatShortDate(local)} '
          '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FutureBuilder<List<SavedTrace>>(
          future: _traces,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(l.traceHistoryFailed);
            }
            final list = snap.data;
            if (list == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.traceHistoryTitle(widget.node.displayName),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(l.traceHistoryEmpty),
                  ),
                for (final t in list)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(when(t.result.time)),
                    subtitle: Text(l.traceHopCount(t.result.towards.length)),
                    children: [
                      TraceDetails(result: t.result, targetName: t.targetName),
                      _ShareCardButton(
                        store: widget.store,
                        radio: widget.node.radioId,
                        result: t.result,
                        targetName: t.targetName,
                        tiles: widget.tiles,
                      ),
                    ],
                  ),
                if (list.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.traceClear),
                    onPressed: _clear,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Distance, Fresnel zone and Earth bulge between two positions.
class LineOfSightSheet extends StatelessWidget {
  const LineOfSightSheet({
    super.key,
    required this.from,
    required this.to,
    required this.frequencyMHz,
  });

  final GeoPoint from;
  final GeoPoint to;
  final double frequencyMHz;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final los = LineOfSight.between(from, to, frequencyMHz);
    String m(double v) => l.losMetres(v.toStringAsFixed(1));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.lineOfSight, style: Theme.of(context).textTheme.titleLarge),
            Text(l.losAt(frequencyMHz.toStringAsFixed(1))),
            const SizedBox(height: 12),
            _Stat(l.losDistance, l.losKm(los.distanceKm.toStringAsFixed(2))),
            _Stat(l.losFresnel, m(los.fresnelM)),
            _Stat(l.losBulge, m(los.earthBulgeM)),
            _Stat(l.losClearance, m(los.clearanceM)),
            const SizedBox(height: 12),
            Text(l.losExplain),
          ],
        ),
      ),
    );
  }
}
