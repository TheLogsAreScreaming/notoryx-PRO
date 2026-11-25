import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../mesh/mesh.dart';
import 'backdrop.dart';
import 'common.dart';
import 'themes.dart';

/// The legend name of a packet kind.
String trafficKindName(BuildContext context, TrafficKind k) {
  final l = context.l10n;
  return switch (k) {
    TrafficKind.advert => l.trafficAdvert,
    TrafficKind.direct => l.trafficDirect,
    TrafficKind.channel => l.trafficChannel,
    TrafficKind.ack => l.trafficAck,
    TrafficKind.trace => l.trafficTrace,
    TrafficKind.path => l.trafficPath,
  };
}

/// One route being animated.
class PlayingRoute {
  PlayingRoute(this.route, this.controller);

  final TrafficRoute route;
  final AnimationController controller;
}

/// Plays heard routes on the map: at most [maxActive] at once, the rest
/// waiting in a short queue (oldest dropped first).
class TrafficPlayer extends ChangeNotifier {
  TrafficPlayer({
    required this.vsync,
    this.maxActive = 3,
    this.maxQueued = 12,
    this.duration = const Duration(milliseconds: 3600),
  });

  final TickerProvider vsync;
  final int maxActive;
  final int maxQueued;
  final Duration duration;
  final List<PlayingRoute> _active = [];
  final Queue<TrafficRoute> _queue = Queue();
  bool _disposed = false;

  List<PlayingRoute> get active => List.unmodifiable(_active);
  int get queued => _queue.length;

  /// Plays [route] now, or once a slot frees up. Routes with fewer than
  /// two located stops are skipped.
  void play(TrafficRoute route) {
    if (_disposed || !route.drawable) return;
    if (_active.length < maxActive) {
      _start(route);
    } else {
      _queue.addLast(route);
      while (_queue.length > maxQueued) {
        _queue.removeFirst();
      }
    }
  }

  void _start(TrafficRoute route) {
    final c = AnimationController(vsync: vsync, duration: duration);
    final playing = PlayingRoute(route, c);
    c
      ..addListener(notifyListeners)
      ..addStatusListener((s) {
        if (s != AnimationStatus.completed || _disposed) return;
        _active.remove(playing);
        c.dispose();
        if (_queue.isNotEmpty) _start(_queue.removeFirst());
        notifyListeners();
      });
    _active.add(playing);
    c.forward();
    notifyListeners();
  }

  /// Stops everything playing or waiting.
  void clear() {
    for (final p in _active) {
      p.controller.dispose();
    }
    _active.clear();
    _queue.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}

/// A map layer drawing [player]'s routes; goes inside a [FlutterMap].
class TrafficMapLayer extends StatelessWidget {
  const TrafficMapLayer({
    super.key,
    required this.player,
    this.showLabels = true,
  });

  final TrafficPlayer player;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return MobileLayerTransformer(
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.infinite,
          painter: TrafficPainter(
            player: player,
            project: (p) =>
                camera.getOffsetFromOrigin(LatLng(p.latitude, p.longitude)),
            reduceMotion: reduceMotion,
            labelStyle: showLabels ? labelStyle : null,
          ),
        ),
      ),
    );
  }
}

/// Where along a route's animation things are, for a progress [t] in 0–1.
///
/// The packet travels for the first [travelShare] of the time, one leg
/// after another, then the whole route fades out.
@immutable
class RouteFrame {
  factory RouteFrame(
    double t, {
    required int legs,
    bool reduceMotion = false,
    double travelShare = .6,
  }) {
    final travel = reduceMotion ? 0.0 : travelShare;
    final travelled = travel == 0 ? 1.0 : (t / travel).clamp(0.0, 1.0);
    final along = travelled * legs;
    final leg = math.min(along.floor(), legs - 1);
    final fade = t <= travel ? 1.0 : 1 - (t - travel) / (1 - travel);
    return RouteFrame._(
      leg: leg,
      legProgress: travelled >= 1 ? 1 : along - leg,
      arrived: travelled >= 1,
      opacity: fade.clamp(0.0, 1.0),
      sinceArrival: t - travel,
    );
  }

  const RouteFrame._({
    required this.leg,
    required this.legProgress,
    required this.arrived,
    required this.opacity,
    required this.sinceArrival,
  });

  /// The leg the packet is on (0-based).
  final int leg;

  /// How far along [leg] it is, 0–1.
  final double legProgress;

  /// Whether it has reached us.
  final bool arrived;

  /// Whole-route opacity.
  final double opacity;

  /// Share of the animation since arrival (negative before).
  final double sinceArrival;
}

/// Paints routes hop by hop: a glowing dot on the leg in flight, a fading
/// solid trail behind it, dotted legs ahead, and pulsing rings at the
/// sender and at us.
class TrafficPainter extends CustomPainter {
  TrafficPainter({
    required this.player,
    required this.project,
    this.reduceMotion = false,
    this.labelStyle,
  }) : super(repaint: player);

  final TrafficPlayer player;
  final Offset Function(GeoPoint) project;
  final bool reduceMotion;

  /// Draws hop names when set.
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in player.active) {
      _paintRoute(canvas, p.route, p.controller.value);
    }
  }

  void _paintRoute(Canvas canvas, TrafficRoute route, double t) {
    final stops = route.onMap;
    final points = [for (final s in stops) project(s.at!)];
    if (points.length < 2) return;
    final legs = points.length - 1;
    final f = RouteFrame(t, legs: legs, reduceMotion: reduceMotion);
    if (f.opacity <= 0) return;
    final color = trafficColor(route.packet.kind);
    final trail = Paint()
      ..color = color.withValues(alpha: .55 * f.opacity)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final live = Paint()
      ..color = color.withValues(alpha: f.opacity)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final ahead = Paint()
      ..color = color.withValues(alpha: .5 * f.opacity)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    Offset? dot;
    for (var i = 0; i < legs; i++) {
      final a = points[i], b = points[i + 1];
      if (f.arrived || i < f.leg) {
        canvas.drawLine(a, b, trail);
      } else if (i == f.leg) {
        dot = Offset.lerp(a, b, f.legProgress)!;
        canvas.drawLine(a, dot, live);
        _dotted(canvas, dot, b, ahead);
      } else {
        _dotted(canvas, a, b, ahead);
      }
    }

    // Rings: the sender as the packet sets off, us as it arrives.
    if (!reduceMotion) {
      final startPulse = (t / .25).clamp(0.0, 1.0);
      if (startPulse < 1) _ring(canvas, points.first, color, startPulse);
      if (f.arrived && f.sinceArrival < .3) {
        _ring(canvas, points.last, color, f.sinceArrival / .3);
      }
    } else {
      _ring(canvas, points.last, color, .5, alpha: f.opacity * .6);
    }

    if (dot != null && !reduceMotion) {
      canvas
        ..drawCircle(
          dot,
          9,
          Paint()
            ..color = color.withValues(alpha: .6 * f.opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        )
        ..drawCircle(
          dot,
          4,
          Paint()..color = trafficDotCore.withValues(alpha: f.opacity),
        );
    }

    if (labelStyle case final style?) {
      for (var i = 0; i < stops.length; i++) {
        if (stops[i].role == StopRole.self) continue;
        _label(canvas, points[i], stops[i].label, style, color, f.opacity);
      }
    }
  }

  void _dotted(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    const dash = 3.0, gap = 6.0;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      final end = math.min(d + dash, length);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
    }
  }

  void _ring(
    Canvas canvas,
    Offset at,
    Color color,
    double phase, {
    double? alpha,
  }) {
    canvas.drawCircle(
      at,
      10 + 22 * phase,
      Paint()
        ..color = color.withValues(alpha: alpha ?? (1 - phase) * .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _label(
    Canvas canvas,
    Offset at,
    String text,
    TextStyle style,
    Color color,
    double opacity,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: trafficLabelInk.withValues(alpha: opacity),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    final box = Rect.fromLTWH(
      at.dx + 12,
      at.dy - tp.height / 2 - 2,
      tp.width + 8,
      tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()..color = trafficLabelBack.withValues(alpha: .55 * opacity),
    );
    tp.paint(canvas, Offset(box.left + 4, box.top + 2));
    tp.dispose();
  }

  /// A new painter comes with each camera move, and projecting a few
  /// routes again is cheap, so always repaint.
  @override
  bool shouldRepaint(TrafficPainter old) => true;
}

/// The frosted card under the map: the latest packet's route, type,
/// signal and the hops that couldn't be placed, with the colour legend.
class TrafficCard extends StatelessWidget {
  const TrafficCard({super.key, required this.route, required this.now});

  final TrafficRoute? route;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final r = route;
    return GlassPanel(
      key: const Key('traffic-card'),
      fill: glassFill(theme),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r == null)
              Text(l.trafficListening, style: theme.textTheme.titleSmall)
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  r.text,
                  key: const Key('traffic-route'),
                  maxLines: 1,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _TypePill(kind: r.packet.kind, label: r.packet.label),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        if (r.heardFrom case final h?)
                          // A repeater's SNR is only the last leg.
                          h.role == StopRole.hop
                              ? l.trafficLastHop(h.label)
                              : l.trafficHeardFrom(h.label),
                        if (r.packet.snr case final snr?) '${_num(snr)} dB',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: small,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(_facts(context, r), style: small),
              if (r.offMap case final off when off.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_off_outlined,
                        size: 14,
                        color: small?.color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l.trafficNotOnMap(off.map((s) => s.label).join(', ')),
                          maxLines: 2,
                          style: small,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            const TrafficLegend(),
          ],
        ),
      ),
    );
  }

  String _facts(BuildContext context, TrafficRoute r) {
    final l = context.l10n;
    final p = r.packet;
    final age = now.difference(p.time).inSeconds.clamp(0, 1 << 30);
    return [
      p.flood ? l.trafficFlood('${p.hopCount ?? '?'}') : l.trafficDirectRoute,
      if (p.rssi case final rssi?) '$rssi dBm',
      if (p.snr case final snr?) 'SNR ${_num(snr)}',
      if (r.offMap.isNotEmpty) l.trafficNotOnMapCount(r.offMap.length),
      l.trafficAge(age),
    ].join(' · ');
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.kind, required this.label});

  final TrafficKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = trafficColor(kind);
    return Semantics(
      label: trafficKindName(context, kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1),
        ),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// A dot and name for each of the six packet colours.
class TrafficLegend extends StatelessWidget {
  const TrafficLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final k in TrafficKind.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 4,
                decoration: BoxDecoration(
                  color: trafficColor(k),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(trafficKindName(context, k), style: style),
            ],
          ),
      ],
    );
  }
}

/// One button of the [MapToolbar].
class MapToolItem {
  const MapToolItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.showLabel = true,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// Whether the label shows under the icon (it is always the tooltip).
  final bool showLabel;
}

/// The frosted vertical pill of map tools on the right.
class MapToolbar extends StatelessWidget {
  const MapToolbar({super.key, required this.items});

  /// About how tall a button with its label is.
  static const labelledHeight = 64.0;

  /// How wide the pill is.
  static const width = 64.0;

  final List<MapToolItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Labels go when the pill would not fit; tooltips keep the names.
        final labelled = items.length * labelledHeight + 12 <= box.maxHeight;
        return GlassPanel(
          fill: glassFill(theme),
          radius: 28,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final i in items)
                  _ToolButton(item: i, showLabel: labelled && i.showLabel),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.item, required this.showLabel});

  final MapToolItem item;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.onPressed == null
        ? scheme.onSurface.withValues(alpha: .38)
        : item.selected
        ? scheme.primary
        : scheme.onSurface;
    return Semantics(
      button: true,
      toggled: item.selected ? true : null,
      enabled: item.onPressed != null,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: InkWell(
          key: item.key,
          onTap: item.onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: MapToolbar.width,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: item.selected
                ? BoxDecoration(
                    color: scheme.primary.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: color, size: 24),
                if (showLabel) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
