import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/app_controller.dart';
import '../app/follow.dart';
import '../mesh/compass.dart';
import '../mesh/mesh.dart';
import 'common.dart';
import 'map_tiles.dart';

/// Starts following [node] for 15 minutes and opens the live view.
void followNode(
  BuildContext context, {
  required AppController app,
  required Node node,
  MapTiles? tiles,
}) {
  if (!app.follow.isFollowing(node)) app.follow.start(node);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FollowScreen(app: app, node: node, tiles: tiles),
    ),
  );
}

/// A followed node's trail, its distance and bearing from your radio, and
/// the time left.
class FollowScreen extends StatefulWidget {
  const FollowScreen({
    super.key,
    required this.app,
    required this.node,
    this.tiles,
  });

  final AppController app;
  final Node node;
  final MapTiles? tiles;

  @override
  State<FollowScreen> createState() => _FollowScreenState();
}

class _FollowScreenState extends State<FollowScreen> {
  Timer? _tick;
  final _map = MapController();
  bool _moved = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  GeoPoint? get _me =>
      widget.app.connectionForRadio(widget.node.radioId)?.radio?.position;

  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final f = widget.app.follow;
    return ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        final on = f.isFollowing(widget.node);
        final trail = on ? f.trail : const <FollowFix>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(l.followTitle(widget.node.displayName)),
            actions: [
              if (on)
                IconButton(
                  key: const Key('follow-ask'),
                  tooltip: l.followAskNow,
                  icon: const Icon(Icons.my_location),
                  onPressed: () => unawaited(f.askNow()),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: on ? _status(f, trail) : _stopped(f),
              ),
              Expanded(child: _mapView(trail)),
            ],
          ),
        );
      },
    );
  }

  Widget _status(FollowTracker f, List<FollowFix> trail) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final last = trail.isEmpty ? null : trail.last;
    final me = _me;
    String headline;
    if (last == null) {
      headline = l.followWaiting;
    } else if (me == null) {
      headline = l.followNoOwnPosition;
    } else {
      final km = haversineKm(me, last.position);
      final deg = bearingDegrees(me, last.position);
      headline = l.followFromYou(
        km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km',
        deg.round(),
      );
    }
    final age = last == null ? null : f.now.difference(last.time);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(headline, style: theme.textTheme.titleMedium)),
            Semantics(
              label: l.followTimeLeft(f.remaining.inMinutes + 1),
              excludeSemantics: true,
              child: Chip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: Text(_clock(f.remaining)),
              ),
            ),
          ],
        ),
        Text(
          [
            if (age != null)
              l.followLastFix(
                age.inSeconds < 60
                    ? l.followSecondsAgo(age.inSeconds)
                    : l.followMinutesAgo(age.inMinutes),
              ),
            l.followAnswers(f.answered, f.asked),
            l.followPoints(trail.length),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(l.followHint, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('follow-stop'),
              onPressed: f.stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(l.followStop),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stopped(FollowTracker f) {
    final l = context.l10n;
    return Row(
      children: [
        Expanded(child: Text(l.followStopped)),
        FilledButton.icon(
          key: const Key('follow-again'),
          onPressed: () => f.start(widget.node),
          icon: const Icon(Icons.radar),
          label: Text(l.followButton),
        ),
      ],
    );
  }

  Widget _mapView(List<FollowFix> trail) {
    final l = context.l10n;
    final points = [for (final f in trail) _ll(f.position)];
    final me = _me == null ? null : _ll(_me!);
    final all = [...points, ?me];
    if (all.isEmpty && widget.node.position != null) {
      all.add(_ll(widget.node.position!));
    }
    if (all.isEmpty) return Center(child: Text(l.followWaiting));
    if (!_moved && all.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _moved) return;
        try {
          _map.fitCamera(
            CameraFit.coordinates(
              coordinates: all,
              padding: const EdgeInsets.all(48),
              maxZoom: 17,
            ),
          );
        } on Object catch (_) {
          // Not laid out yet; the next frame fits it.
        }
      });
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: all.last,
        initialZoom: 15,
        onPositionChanged: (_, gesture) {
          if (gesture) _moved = true;
        },
      ),
      children: [
        if (widget.tiles case final tiles?)
          TileLayer(
            urlTemplate: MapTiles.urlTemplate,
            userAgentPackageName: MapTiles.userAgentPackageName,
            tileProvider: tiles.provider,
            reset: tiles.reload,
            tileBuilder: dark ? darkModeTileBuilder : null,
          ),
        PolylineLayer(
          polylines: [
            if (points.length > 1)
              Polyline(points: points, strokeWidth: 4, color: scheme.primary),
            if (me != null && points.isNotEmpty)
              Polyline(
                points: [me, points.last],
                strokeWidth: 2,
                color: scheme.outline,
                pattern: StrokePattern.dashed(segments: const [8, 6]),
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final p in points.take(points.length - 1))
              Marker(
                point: p,
                width: 10,
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (points.isNotEmpty)
              Marker(
                point: points.last,
                width: 40,
                height: 40,
                child: Icon(
                  Icons.person_pin_circle,
                  size: 40,
                  color: scheme.primary,
                  semanticLabel: widget.node.displayName,
                ),
              ),
            if (me != null)
              Marker(
                point: me,
                width: 28,
                height: 28,
                child: Icon(
                  Icons.navigation,
                  color: scheme.tertiary,
                  semanticLabel: l.followYou,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
