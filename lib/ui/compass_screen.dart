import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/heading.dart';
import '../mesh/compass.dart';
import '../mesh/mesh.dart';
import 'common.dart';
import 'list_insets.dart';

/// A big arrow pointing at [node], turning with the phone.
class CompassScreen extends StatefulWidget {
  const CompassScreen({
    super.key,
    required this.app,
    required this.node,
    this.sensors = const DeviceCompassSensors(),
  });

  final AppController app;
  final Node node;
  final CompassSensors sensors;

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

enum _From { phone, radio }

class _CompassScreenState extends State<CompassScreen> {
  StreamSubscription<HeadingReading>? _sub;
  bool _hasCompass = true;
  double? _heading;
  int _accuracy = 3;
  double _declination = 0;
  GeoPoint? _here;
  _From? _from;
  bool _locating = false;
  bool _phoneFailed = false;
  bool _onTarget = false;

  @override
  void initState() {
    super.initState();
    final stream = widget.sensors.headings();
    if (stream == null) {
      _hasCompass = false;
    } else {
      _sub = stream.listen(
        _onReading,
        onError: (Object _) {
          if (mounted) setState(() => _hasCompass = false);
        },
      );
    }
    unawaited(_findPosition());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _findPosition() async {
    final phone = await widget.sensors.phonePositionIfAllowed();
    if (!mounted) return;
    if (phone != null) return _use(phone, _From.phone);
    final radio = await _radioPosition();
    if (!mounted || radio == null) return;
    if (_here == null) await _use(radio, _From.radio);
  }

  Future<GeoPoint?> _radioPosition() async {
    final radio = widget.app.connectionForRadio(widget.node.radioId)?.radio;
    if (radio == null) return null;
    return radio.position ??
        (await widget.app.store.node(radio.id, radio.self))?.position;
  }

  Future<void> _use(GeoPoint at, _From from) async {
    setState(() {
      _here = at;
      _from = from;
    });
    final d = await widget.sensors.declination(at);
    if (mounted && d != null) setState(() => _declination = d);
  }

  Future<void> _usePhone() async {
    setState(() {
      _locating = true;
      _phoneFailed = false;
    });
    final p = await widget.sensors.phonePosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _phoneFailed = p == null;
    });
    if (p != null) await _use(p, _From.phone);
  }

  void _onReading(HeadingReading r) {
    if (!mounted) return;
    final next = (r.degrees + _declination + 360) % 360;
    setState(() {
      _heading = _heading == null ? next : smoothHeading(_heading!, next);
      _accuracy = r.accuracy;
    });
  }

  String _distance(BuildContext context, double km) {
    final l = context.l10n;
    return km < 1
        ? l.compassMetres((km * 1000).round())
        : l.losKm(km < 10 ? km.toStringAsFixed(1) : km.round().toString());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final target = widget.node.position;
    final here = _here;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final points = l.compassPoints.split(',');

    Widget body;
    if (target == null || here == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            target == null ? l.compassNoTarget : l.compassNoPosition,
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      final bearing = bearingDegrees(here, target);
      final km = haversineKm(here, target);
      final heading = _hasCompass ? _heading : null;
      final turn = heading == null ? null : turnDegrees(heading, bearing);
      final onTarget = turn != null && turn.abs() <= onTargetDegrees;
      if (onTarget && !_onTarget) unawaited(HapticFeedback.lightImpact());
      _onTarget = onTarget;
      final direction = switch (turn) {
        null => l.compassBearing(
          bearing.round() % 360,
          points[compassPoint(bearing)],
        ),
        _ when onTarget => l.compassOnTarget,
        final t when t < 0 => l.compassTurnLeft(t.abs().round()),
        final t => l.compassTurnRight(t.round()),
      };
      // Read out only coarse changes, not every sensor tick.
      final spoken = switch (turn) {
        null => direction,
        _ when onTarget => l.compassOnTarget,
        final t when t < 0 => l.compassTurnLeft((t.abs() / 15).round() * 15),
        final t => l.compassTurnRight((t / 15).round() * 15),
      };
      final rose = -(heading ?? 0) * math.pi / 180;
      final arrow = (bearing - (heading ?? 0)) * math.pi / 180;
      body = ListView(
        padding: withBottomInset(context, const EdgeInsets.all(16)),
        children: [
          Semantics(
            liveRegion: true,
            label: l.compassSummary(
              widget.node.displayName,
              _distance(context, km),
              spoken,
            ),
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    _distance(context, km),
                    style: text.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    direction,
                    key: const Key('compass-direction'),
                    style: text.titleLarge?.copyWith(
                      color: onTarget ? scheme.primary : null,
                      fontWeight: onTarget ? FontWeight.bold : null,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ExcludeSemantics(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.rotate(
                        angle: rose,
                        child: CustomPaint(
                          painter: _RosePainter(
                            ring: scheme.outline,
                            north: scheme.error,
                            label: scheme.onSurface,
                            points: points,
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: arrow,
                        child: CustomPaint(
                          painter: _ArrowPainter(
                            onTarget ? scheme.primary : scheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (turn != null)
            Text(
              l.compassBearing(
                bearing.round() % 360,
                points[compassPoint(bearing)],
              ),
              textAlign: TextAlign.center,
            ),
          if (!_hasCompass)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.compassNone,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            )
          else if (_accuracy <= 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.compassCalibrate,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _from == _From.phone ? l.compassFromPhone : l.compassFromRadio,
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.compassTitle(widget.node.displayName))),
      body: Column(
        children: [
          Expanded(child: body),
          if (_from != _From.phone)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_phoneFailed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(l.compassNoPhone),
                      ),
                    OutlinedButton.icon(
                      key: const Key('compass-use-phone'),
                      icon: _locating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(l.compassUsePhone),
                      onPressed: _locating ? null : _usePhone,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RosePainter extends CustomPainter {
  _RosePainter({
    required this.ring,
    required this.north,
    required this.label,
    required this.points,
  });

  final Color ring;
  final Color north;
  final Color label;
  final List<String> points;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
    for (var deg = 0; deg < 360; deg += 15) {
      final a = deg * math.pi / 180;
      final major = deg % 90 == 0;
      final inner = r - (major ? 16 : 8);
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c + dir * inner,
        c + dir * r,
        Paint()
          ..strokeWidth = major ? 3 : 1
          ..color = deg == 0 ? north : ring,
      );
    }
    for (var i = 0; i < 8; i += 2) {
      final a = i * 45 * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: points[i],
          style: TextStyle(
            color: i == 0 ? north : label,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = c + Offset(math.sin(a), -math.cos(a)) * (r - 34);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RosePainter old) =>
      old.ring != ring ||
      old.north != north ||
      old.label != label ||
      old.points != points;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 0.62)
      ..lineTo(c.dx + r * 0.2, c.dy + r * 0.05)
      ..lineTo(c.dx + r * 0.07, c.dy + r * 0.05)
      ..lineTo(c.dx + r * 0.07, c.dy + r * 0.45)
      ..lineTo(c.dx - r * 0.07, c.dy + r * 0.45)
      ..lineTo(c.dx - r * 0.07, c.dy + r * 0.05)
      ..lineTo(c.dx - r * 0.2, c.dy + r * 0.05)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
