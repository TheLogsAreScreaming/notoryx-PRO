import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../app/nearby_probe.dart';
import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../radio/radio.dart';
import 'common.dart';

/// One tap asks repeaters (and, on Meshtastic, every node) in direct range
/// to answer, then lists who did with their signal both ways.
class NearbySheet extends StatefulWidget {
  const NearbySheet({
    super.key,
    required this.connection,
    this.listen = const Duration(seconds: 12),
  });

  final RadioConnection connection;

  /// How long to wait for answers.
  final Duration listen;

  /// Shows the sheet for [connection].
  static Future<void> show(BuildContext context, RadioConnection connection) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => NearbySheet(connection: connection),
      );

  /// Repeaters answer only a few requests every 2 minutes, so tests are
  /// spaced at least this far apart.
  static const cooldown = Duration(seconds: 30);

  @override
  State<NearbySheet> createState() => _NearbySheetState();
}

class _NearbySheetState extends State<NearbySheet> {
  static final Map<String, DateTime> _lastRun = {};

  bool _running = false;
  List<NearbyNode>? _found;
  int _answered = 0;
  String? _error;
  bool _infraOnly = false;
  Timer? _tick;

  String get _radioKey => widget.connection.target.address;

  Duration get _wait {
    final last = _lastRun[_radioKey];
    if (last == null) return Duration.zero;
    final left = NearbySheet.cooldown - DateTime.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final l = context.l10n;
    final c = widget.connection;
    setState(() {
      _running = true;
      _error = null;
    });
    _lastRun[_radioKey] = DateTime.now();
    try {
      final answers = await c.probeNearby(listen: widget.listen);
      final radio = c.radio;
      final known = radio == null
          ? const <Node>[]
          : await c.store.nodes(radio.id);
      if (!mounted) return;
      setState(() {
        _answered = answers.length;
        _found = mergeNearby(answers, known, now: DateTime.now());
      });
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          l.nearbyDone(answers.length),
          Directionality.of(context),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = RadioConnection.describeError(e));
    }
    if (!mounted) return;
    setState(() => _running = false);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait == Duration.zero) t.cancel();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final meshcore = widget.connection.protocol == RadioProtocol.meshcore;
    final wait = _wait;
    final shown = [
      for (final n in _found ?? const <NearbyNode>[])
        if (!_infraOnly || n.isInfrastructure) n,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.nearbyTitle, style: text.titleLarge),
            const SizedBox(height: 4),
            Text(meshcore ? l.nearbyHelpMeshCore : l.nearbyHelpMeshtastic),
            const SizedBox(height: 12),
            if (_running)
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(l.nearbyListening(widget.listen.inSeconds)),
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.radar),
                label: Text(
                  wait == Duration.zero
                      ? (_found == null ? l.nearbyRun : l.nearbyRunAgain)
                      : l.nearbyWait(wait.inSeconds + 1),
                ),
                onPressed: wait == Duration.zero ? _run : null,
              ),
            if (_error case final e?) ...[
              const SizedBox(height: 12),
              Text(
                l.nearbyFailed(e),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_found != null) ...[
              const SizedBox(height: 12),
              Text(l.nearbyDone(_answered), style: text.titleSmall),
              if (!meshcore)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.nearbyInfraOnly),
                  value: _infraOnly,
                  onChanged: (v) => setState(() => _infraOnly = v),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l.nearbyNone),
                ),
              for (final n in shown) _NearbyTile(n),
            ],
          ],
        ),
      ),
    );
  }
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile(this.n);

  final NearbyNode n;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final facts = [
      nodeKindName(context, n.kind),
      if (!n.answered && n.lastHeard != null)
        l.nearbyQuiet(ago(context, n.lastHeard!)),
      if (n.snr != null || n.rssi != null)
        l.nearbyYouHear(
          [
            if (n.snr != null) l.pathSnr(n.snr!.toStringAsFixed(1)),
            if (n.rssi != null) l.pathRssi(n.rssi!),
          ].join(', '),
        ),
      if (n.heardUsSnr != null)
        l.nearbyHearsYou(n.heardUsSnr!.toStringAsFixed(1)),
    ].join(' · ');
    return MergeSemantics(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(n.answered ? nodeKindIcon(n.kind) : Icons.history),
        title: Text(n.name),
        subtitle: Text(facts),
        trailing: SignalBars(signalBars(PathFacts(snr: n.snr)), size: 20),
      ),
    );
  }
}
