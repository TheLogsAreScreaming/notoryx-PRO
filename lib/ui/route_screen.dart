import 'package:flutter/material.dart';

import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../mesh/route_planner.dart';
import 'common.dart';
import 'diagnostics_screen.dart';

/// A MeshCore node's route: each repeater on the way with how well each
/// link heard, other routes the saved traces measured (best first, with a
/// suggestion when one is clearly better), and a way to build one by hand.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.connection, required this.node});

  final MeshCoreConnection connection;
  final Node node;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  late Node _node = widget.node;
  late Future<(RoutePlan, List<Node>)> _plan = _load();
  bool _busy = false;

  Future<(RoutePlan, List<Node>)> _load() async {
    final store = widget.connection.store;
    final fresh = await store.node(_node.radioId, _node.key);
    if (fresh != null) _node = fresh;
    final known = await store.nodes(_node.radioId);
    final traces = await store.traces(_node.radioId, _node.key);
    return (RoutePlan.build(_node, traces, known, now: DateTime.now()), known);
  }

  void _reload() {
    final next = _load();
    setState(() => _plan = next);
  }

  Future<void> _apply(List<String> hops) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      _node = await widget.connection.setRoute(_node, hops);
      messenger.showSnackBar(
        SnackBar(content: Text(hops.isEmpty ? l.rpFloodSet : l.rpSet)),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.rpFailed(RadioConnection.describeError(e)))),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _trace() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TraceSheet(connection: widget.connection, node: _node),
    );
    if (mounted) _reload();
  }

  Future<void> _build(List<Node> known) async {
    final size = _node.route.isEmpty
        ? (widget.connection.pathHashBytes ?? 1)
        : _node.routeHashSize;
    final hops = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => RouteEditorSheet(
        candidates: routeCandidates(_node, known),
        hashSize: size,
      ),
    );
    if (hops == null || hops.isEmpty || !mounted) return;
    await _apply(hops);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.rpTitle(_node.displayName))),
      body: FutureBuilder<(RoutePlan, List<Node>)>(
        future: _plan,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              l.rpFailed(RadioConnection.describeError(snap.error!)),
              icon: Icons.error_outline,
            );
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (plan, known) = data;
          final current = plan.current;
          final you = widget.connection.radio?.name ?? l.rpYou;
          final heard = [
            if (_node.path.snr != null)
              l.pathSnr(_node.path.snr!.toStringAsFixed(1)),
            if (_node.path.rssi != null) l.pathRssi(_node.path.rssi!),
          ].join(' · ');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l.rpCurrent, style: text.titleMedium),
              const SizedBox(height: 8),
              if (current != null)
                RouteChart(choice: current, from: you, to: _node.displayName)
              else
                Text(
                  _node.path.hops == 0 && _node.path.route == RouteKind.direct
                      ? l.rpDirectLink
                      : l.rpFlooding,
                ),
              if (heard.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(l.rpLastHeard(heard), style: text.bodySmall),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.connection.canTrace(_node))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.timeline),
                      label: Text(l.rpTrace),
                      onPressed: _busy ? null : _trace,
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_road_outlined),
                    label: Text(l.rpBuild),
                    onPressed: _busy ? null : () => _build(known),
                  ),
                  if (current != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.wifi_tethering),
                      label: Text(l.rpFlood),
                      onPressed: _busy ? null : () => _apply(const []),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(l.rpOthers, style: text.titleMedium),
              const SizedBox(height: 8),
              if (plan.others.isEmpty) Text(l.rpNoOthers),
              for (final c in plan.others)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (identical(c, plan.better))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.recommend_outlined),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l.rpSuggested,
                                    style: text.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        RouteChart(choice: c, from: you, to: _node.displayName),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton.tonal(
                            onPressed: _busy ? null : () => _apply(c.hashes),
                            child: Text(l.rpUse),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(l.rpHelp, style: text.bodySmall),
            ],
          );
        },
      ),
    );
  }
}

/// One route drawn as a chain of hops, each with a bar for its weakest
/// measured link and the SNR both ways in words.
class RouteChart extends StatelessWidget {
  const RouteChart({
    super.key,
    required this.choice,
    required this.from,
    required this.to,
  });

  final RouteChoice choice;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    final measured = choice.measured;
    final weakest = choice.weakestSnr;
    final summary = [
      l.rpHopCount(choice.hops.length),
      if (weakest != null) l.rpWeakest(weakest.toStringAsFixed(1)),
      if (measured == null)
        l.rpNeverMeasured
      else
        l.rpMeasured(
          '${m.formatShortDate(measured.toLocal())} '
          '${m.formatTimeOfDay(TimeOfDay.fromDateTime(measured.toLocal()))}',
        ),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _End(icon: Icons.settings_input_antenna, label: from),
        for (final (i, h) in choice.hops.indexed) _HopRow(index: i + 1, hop: h),
        _End(icon: Icons.person_pin_circle_outlined, label: to),
        const SizedBox(height: 4),
        Text(summary, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _End extends StatelessWidget {
  const _End({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

class _HopRow extends StatelessWidget {
  const _HopRow({required this.index, required this.hop});

  final int index;
  final PlannedHop hop;

  /// Lowest and highest SNR the bar shows, in dB.
  static const _floor = -20.0, _top = 12.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final worst = hop.worstSnr;
    final bars = signalBars(PathFacts(snr: worst));
    final words = [
      if (hop.snr != null) l.rpSnrOut(hop.snr!.toStringAsFixed(1)),
      if (hop.backSnr != null) l.rpSnrBack(hop.backSnr!.toStringAsFixed(1)),
    ];
    final quality = words.isEmpty ? l.rpNotMeasured : words.join(', ');
    final fill = worst == null
        ? 0.0
        : ((worst - _floor) / (_top - _floor)).clamp(0.05, 1.0);
    return Semantics(
      container: true,
      label: l.rpHopLabel(index, hop.label, quality),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 9),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VerticalDivider(width: 2, thickness: 2, color: scheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SignalBars(bars),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(l.rpHopName(index, hop.label)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: fill,
                            minHeight: 6,
                            color: worst == null
                                ? scheme.outlineVariant
                                : scheme.primary,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          quality,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks repeaters, in order, for a hand-built route. Pops the hops as hex
/// prefixes of [hashSize] bytes.
class RouteEditorSheet extends StatefulWidget {
  const RouteEditorSheet({
    super.key,
    required this.candidates,
    required this.hashSize,
  });

  final List<Node> candidates;
  final int hashSize;

  @override
  State<RouteEditorSheet> createState() => _RouteEditorSheetState();
}

class _RouteEditorSheetState extends State<RouteEditorSheet> {
  final List<Node> _hops = [];

  /// At most this many hops fit the radio's 64-byte path.
  int get _max => (64 ~/ widget.hashSize).clamp(1, 63);

  Future<void> _add() async {
    final l = context.l10n;
    final left = [
      for (final n in widget.candidates)
        if (!_hops.contains(n)) n,
    ];
    final picked = await showDialog<Node>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.rpEditorAdd),
        children: [
          if (left.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.rpEditorNoRepeaters),
            ),
          for (final n in left)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, n),
              child: Text(
                '${n.displayName} '
                '(${hopHash(n, widget.hashSize)})',
              ),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _hops.add(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.rpEditorTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(l.rpEditorHelp),
            const SizedBox(height: 8),
            if (_hops.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l.rpEditorEmpty),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, n) in _hops.indexed)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(n.displayName),
                      subtitle: Text(hopHash(n, widget.hashSize)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0)
                            IconButton(
                              tooltip: l.rpMoveUp(n.displayName),
                              icon: const Icon(Icons.arrow_upward),
                              onPressed: () => setState(() {
                                _hops
                                  ..removeAt(i)
                                  ..insert(i - 1, n);
                              }),
                            ),
                          IconButton(
                            tooltip: l.rpRemoveHop(n.displayName),
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _hops.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l.rpEditorAdd),
                  onPressed: _hops.length >= _max ? null : _add,
                ),
                FilledButton(
                  onPressed: _hops.isEmpty
                      ? null
                      : () => Navigator.pop(context, [
                          for (final n in _hops) hopHash(n, widget.hashSize),
                        ]),
                  child: Text(l.rpUse),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
