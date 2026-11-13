import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../mesh/mesh.dart';
import '../mesh/trace_card.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'map_tiles.dart';

/// Builds a card for [result] from what [store] knows about [radio], and
/// opens it.
Future<void> openTraceCard(
  BuildContext context, {
  required MeshStore store,
  required RadioId radio,
  required TraceResult result,
  required String targetName,
  MapTiles? tiles,
}) async {
  final navigator = Navigator.of(context);
  final fallback = context.l10n.tcYou;
  final radios = await store.radios();
  final me = radios.where((r) => r.id == radio).firstOrNull;
  final known = await store.nodes(radio);
  final self = me == null
      ? null
      : known.where((n) => n.key == me.self).firstOrNull;
  final data = TraceCardData.from(
    result: result,
    protocol: radio.protocol,
    senderName: me?.name ?? fallback,
    senderPosition: me?.position ?? self?.position,
    targetName: targetName,
    known: known,
  );
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => TraceCardScreen(card: data, tiles: tiles),
    ),
  );
}

/// The card as plain text, for sharing where images don't fit.
String traceCardText(
  AppLocalizations l,
  MaterialLocalizations m,
  TraceCardData d,
) {
  String stop(TraceStop s) => s.snr == null
      ? s.label
      : '${s.label} (${l.pathSnr(s.snr!.toStringAsFixed(1))})';
  final local = d.time.toLocal();
  final when =
      '${m.formatShortDate(local)} '
      '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  return [
    l.tcHeading(
      d.protocol == RadioProtocol.meshcore ? 'MeshCore' : 'Meshtastic',
    ),
    l.tcTitle(d.senderName, d.targetName),
    [
      when,
      l.tcHops(d.hopsOut),
      if (d.roundTrip case final rt?)
        l.tcRoundTrip((rt.inMilliseconds / 1000).toStringAsFixed(1)),
    ].join(' · '),
    l.tcOutLine(d.out.map(stop).join(' → ')),
    if (d.back.isNotEmpty) l.tcBackLine(d.back.map(stop).join(' → ')),
  ].join('\n');
}

/// A trace card on its own screen, with buttons to share it as an image
/// or as text.
class TraceCardScreen extends StatefulWidget {
  const TraceCardScreen({super.key, required this.card, this.tiles});

  final TraceCardData card;

  /// Map background; null draws the route on a plain background.
  final MapTiles? tiles;

  @override
  State<TraceCardScreen> createState() => _TraceCardScreenState();
}

class _TraceCardScreenState extends State<TraceCardScreen> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  Rect? _origin() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  Future<void> _shareText() async {
    final text = traceCardText(
      context.l10n,
      MaterialLocalizations.of(context),
      widget.card,
    );
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: _origin()),
    );
  }

  Future<void> _shareImage() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final text = traceCardText(
      l,
      MaterialLocalizations.of(context),
      widget.card,
    );
    final origin = _origin();
    setState(() => _sharing = true);
    try {
      final boundary =
          _boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/trace-cards');
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final stamp = widget.card.time.toIso8601String().replaceAll(':', '-');
      final file = File(
        '${dir.path}/notoryx-trace-${stamp.substring(0, 19)}.png',
      );
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: text,
          sharePositionOrigin: origin,
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.tcShareFailed('$e'))));
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tcScreenTitle),
        actions: [
          IconButton(
            tooltip: l.tcShareText,
            icon: const Icon(Icons.notes),
            onPressed: _shareText,
          ),
          IconButton(
            tooltip: l.tcShareImage,
            icon: const Icon(Icons.ios_share),
            onPressed: _sharing ? null : _shareImage,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RepaintBoundary(
              key: _boundary,
              child: TraceCard(card: widget.card, tiles: widget.tiles),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card itself: who traced whom and when, the round trip on a map,
/// and every hop out and back with its signal.
class TraceCard extends StatelessWidget {
  const TraceCard({super.key, required this.card, this.tiles});

  final TraceCardData card;
  final MapTiles? tiles;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final local = card.time.toLocal();
    final facts = [
      '${m.formatShortDate(local)} '
          '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
      l.tcHops(card.hopsOut),
      if (card.roundTrip case final rt?)
        l.tcRoundTrip((rt.inMilliseconds / 1000).toStringAsFixed(1)),
    ].join(' · ');
    final (placed, total) = card.placedCount;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProtocolBadge(card.protocol),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.tcTitle(card.senderName, card.targetName),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(facts, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Semantics(
              label: l.tcMapLabel(placed, total),
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    child: _TraceMap(card: card, tiles: tiles),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Wrap(
                spacing: 16,
                children: [
                  _Legend(dashed: false, label: l.tcLegendOut),
                  if (card.back.isNotEmpty)
                    _Legend(dashed: true, label: l.tcLegendBack),
                ],
              ),
            ),
            if (placed < total)
              Text(
                l.tcUnplaced(total - placed),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            Text(l.tcOut, style: theme.textTheme.titleSmall),
            for (final (i, s) in card.out.indexed) _StopRow(index: i, stop: s),
            if (card.back.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l.tcBack, style: theme.textTheme.titleSmall),
              for (final (i, s) in card.back.indexed)
                _StopRow(index: i, stop: s),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('NOTORYX PRO', style: theme.textTheme.labelSmall),
                ),
                if (tiles != null)
                  Text(l.tcAttribution, style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.index, required this.stop});

  final int index;
  final TraceStop stop;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final snr = stop.snr;
    final signal = index == 0
        ? l.tcStart
        : snr == null
        ? l.traceNotReported
        : l.pathSnr(snr.toStringAsFixed(1));
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                index == 0 ? '•' : '$index',
                textAlign: TextAlign.center,
              ),
            ),
            if (index > 0) SignalBars(signalBars(PathFacts(snr: snr))),
            const SizedBox(width: 8),
            Expanded(child: Text(stop.label)),
            Text(signal, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.dashed, required this.label});

  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(28, 8),
          painter: _LinePainter(
            color: dashed ? scheme.tertiary : scheme.primary,
            dashed: dashed,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), p);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.dashed != dashed;
}

class _TraceMap extends StatelessWidget {
  const _TraceMap({required this.card, this.tiles});

  final TraceCardData card;
  final MapTiles? tiles;

  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final out = card.outLine.map(_ll).toList();
    final back = card.backLine.map(_ll).toList();
    final all = [...out, ...back];
    if (all.isEmpty) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.tcNoPositions, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final distinct = {for (final p in all) '${p.latitude},${p.longitude}'};
    final markers = <Marker>[];
    for (final (i, s) in card.out.indexed) {
      if (s.position == null) continue;
      markers.add(
        Marker(
          point: _ll(s.position!),
          width: 26,
          height: 26,
          child: CircleAvatar(
            backgroundColor: i == 0 ? scheme.primary : scheme.primaryContainer,
            foregroundColor: i == 0
                ? scheme.onPrimary
                : scheme.onPrimaryContainer,
            child: i == 0
                ? const Icon(Icons.settings_input_antenna, size: 14)
                : Text('$i', style: const TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: distinct.length > 1
            ? CameraFit.coordinates(
                coordinates: all,
                padding: const EdgeInsets.all(28),
                maxZoom: 15,
              )
            : null,
        initialCenter: all.first,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        if (tiles case final t?)
          TileLayer(
            urlTemplate: MapTiles.urlTemplate,
            userAgentPackageName: MapTiles.userAgentPackageName,
            tileProvider: t.provider,
          )
        else
          ColoredBox(color: scheme.surfaceContainerHighest),
        PolylineLayer(
          polylines: [
            if (back.length > 1)
              Polyline(
                points: back,
                strokeWidth: 3,
                color: scheme.tertiary,
                pattern: StrokePattern.dashed(segments: const [8, 6]),
              ),
            if (out.length > 1)
              Polyline(points: out, strokeWidth: 4, color: scheme.primary),
          ],
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
