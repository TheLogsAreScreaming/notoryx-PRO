import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/elevation.dart';
import '../mesh/diagnostics.dart';
import '../mesh/model.dart';
import '../mesh/terrain.dart';
import 'common.dart';

/// Line of sight between two positions: mid-path numbers straight away,
/// and a terrain profile with the Fresnel zone once the user asks for it.
///
/// Ground heights are only fetched when "Check terrain" is tapped.
class LineOfSightSheet extends StatefulWidget {
  const LineOfSightSheet({
    super.key,
    required this.ends,
    this.initialFrom = 0,
    this.initialTo = 1,
    required this.frequencyMHz,
    this.elevation,
  }) : assert(ends.length >= 2);

  /// Places to pick from: a label and a position.
  final List<(String, GeoPoint)> ends;
  final int initialFrom;
  final int initialTo;
  final double frequencyMHz;

  /// Ground heights; defaults to Open-Meteo.
  final ElevationLookup? elevation;

  @override
  State<LineOfSightSheet> createState() => _LineOfSightSheetState();
}

enum _Load { idle, loading, failed }

class _LineOfSightSheetState extends State<LineOfSightSheet> {
  late int _a = widget.initialFrom.clamp(0, widget.ends.length - 1);
  late int _b = widget.initialTo.clamp(0, widget.ends.length - 1);
  final _hA = TextEditingController(text: '2');
  final _hB = TextEditingController(text: '2');
  late final ElevationLookup _lookup = widget.elevation ?? OpenMeteoElevation();
  TerrainProfile? _profile;
  _Load _load = _Load.idle;
  int _request = 0;

  @override
  void dispose() {
    _hA.dispose();
    _hB.dispose();
    super.dispose();
  }

  GeoPoint get _from => widget.ends[_a].$2;
  GeoPoint get _to => widget.ends[_b].$2;

  double _height(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '.'));
    return v == null || !v.isFinite ? 2 : v.clamp(0, 500).toDouble();
  }

  void _changed(VoidCallback f) => setState(() {
    f();
    _profile = null;
    _load = _Load.idle;
    _request++;
  });

  Future<void> _check() async {
    final request = ++_request;
    final from = _from;
    final to = _to;
    setState(() => _load = _Load.loading);
    try {
      final heights = await _lookup.heights(profilePoints(from, to));
      if (!mounted || request != _request) return;
      setState(() {
        _profile = TerrainProfile.between(
          from,
          to,
          elevationsM: heights,
          frequencyMHz: widget.frequencyMHz,
          startAntennaM: _height(_hA),
          endAntennaM: _height(_hB),
        );
        _load = _Load.idle;
      });
    } on ElevationException {
      if (!mounted || request != _request) return;
      setState(() => _load = _Load.failed);
    }
  }

  Widget _end(String label, int value, void Function(int) set) =>
      DropdownButtonFormField<int>(
        key: Key('los-$label'),
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var i = 0; i < widget.ends.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(widget.ends[i].$1, overflow: TextOverflow.fade),
            ),
        ],
        onChanged: (v) => _changed(() => set(v!)),
      );

  Widget _antenna(Key key, TextEditingController c, String label) => Expanded(
    child: TextField(
      key: key,
      controller: c,
      onChanged: (_) => _changed(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final same = _a == _b;
    final los = LineOfSight.between(_from, _to, widget.frequencyMHz);
    String m(double v) => l.losMetres(v.toStringAsFixed(1));
    final profile = _profile;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.lineOfSight, style: Theme.of(context).textTheme.titleLarge),
            Text(l.losAt(widget.frequencyMHz.toStringAsFixed(1))),
            _end(l.placesFrom, _a, (v) => _a = v),
            _end(l.placesTo, _b, (v) => _b = v),
            const SizedBox(height: 12),
            _Row(l.losDistance, l.losKm(los.distanceKm.toStringAsFixed(2))),
            _Row(l.losFresnel, m(los.fresnelM)),
            _Row(l.losBulge, m(los.earthBulgeM)),
            _Row(l.losClearance, m(los.clearanceM)),
            const SizedBox(height: 8),
            Text(l.losExplain),
            const Divider(height: 24),
            Text(l.losTerrain, style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                _antenna(const Key('los-antenna-from'), _hA, l.losAntennaFrom),
                const SizedBox(width: 8),
                _antenna(const Key('los-antenna-to'), _hB, l.losAntennaTo),
              ],
            ),
            const SizedBox(height: 8),
            Text(l.losTerrainSends),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('los-check-terrain'),
              icon: const Icon(Icons.terrain),
              label: Text(l.losCheckTerrain),
              onPressed: same || _load == _Load.loading ? null : _check,
            ),
            if (same) Text(l.losSamePoint),
            if (_load == _Load.loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l.losTerrainLoading)),
                  ],
                ),
              ),
            if (_load == _Load.failed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l.losTerrainFailed,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (profile != null) ...[
              const SizedBox(height: 12),
              _Verdict(profile),
              const SizedBox(height: 8),
              _ProfileChart(profile),
              const SizedBox(height: 8),
              Text(l.losLegend, style: Theme.of(context).textTheme.bodySmall),
              Text(l.losSource, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

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

/// The verdict in words and an icon, so it never relies on colour alone.
class _Verdict extends StatelessWidget {
  const _Verdict(this.profile);

  final TerrainProfile profile;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title) = switch (profile.verdict) {
      TerrainVerdict.clear => (
        Icons.check_circle,
        scheme.primary,
        l.losVerdictClear,
      ),
      TerrainVerdict.partial => (
        Icons.warning_amber,
        scheme.tertiary,
        l.losVerdictPartial,
      ),
      TerrainVerdict.blocked => (
        Icons.block,
        scheme.error,
        l.losVerdictBlocked,
      ),
    };
    final w = profile.worst;
    final km = w == null ? null : (w.distanceM / 1000).toStringAsFixed(2);
    final detail = w == null
        ? null
        : w.clearanceM < 0
        ? l.losWorstBlocked(km!, (-w.clearanceM).toStringAsFixed(0))
        : l.losWorstOpen(
            km!,
            (math.min(w.zoneOpen!, 1) * 100).toStringAsFixed(0),
          );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const Key('los-verdict'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail != null) Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileChart extends StatelessWidget {
  const _ProfileChart(this.profile);

  final TerrainProfile profile;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 2,
        child: CustomPaint(
          key: const Key('los-profile'),
          painter: TerrainProfilePainter(
            profile,
            ground: scheme.outline,
            groundFill: scheme.surfaceContainerHighest,
            zone: scheme.primary,
            line: scheme.onSurface,
            curve: scheme.secondary,
            labelStyle: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
            kmLabel: l.losKm,
            mLabel: l.losMetres,
          ),
        ),
      ),
    );
  }
}

/// Draws the ground (lifted by the Earth's curve), the direct line, the
/// shaded first Fresnel zone and a dashed line at 60 % of its radius.
class TerrainProfilePainter extends CustomPainter {
  TerrainProfilePainter(
    this.profile, {
    required this.ground,
    required this.groundFill,
    required this.zone,
    required this.line,
    required this.curve,
    required this.labelStyle,
    required this.kmLabel,
    required this.mLabel,
  });

  final TerrainProfile profile;
  final Color ground;
  final Color groundFill;
  final Color zone;
  final Color line;
  final Color curve;
  final TextStyle labelStyle;
  final String Function(String) kmLabel;
  final String Function(String) mLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final s = profile.samples;
    if (s.length < 2 || size.isEmpty) return;
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in s) {
      lo = math.min(lo, math.min(p.groundM, p.lineM - p.fresnelM));
      hi = math.max(hi, math.max(p.effectiveGroundM, p.lineM + p.fresnelM));
    }
    final pad = math.max(5.0, (hi - lo) * 0.08);
    lo -= pad;
    hi += pad;
    final total = profile.distanceM <= 0 ? 1.0 : profile.distanceM;
    Offset at(double d, double h) => Offset(
      size.width * d / total,
      size.height * (1 - (h - lo) / (hi - lo)),
    );
    Path through(double Function(ProfileSample) h) {
      final path = Path()..moveTo(at(0, h(s.first)).dx, at(0, h(s.first)).dy);
      for (final p in s.skip(1)) {
        final o = at(p.distanceM, h(p));
        path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    // Fresnel zone, shaded.
    final zonePath = through((p) => p.lineM + p.fresnelM);
    for (final p in s.reversed) {
      final o = at(p.distanceM, p.lineM - p.fresnelM);
      zonePath.lineTo(o.dx, o.dy);
    }
    zonePath.close();
    canvas.drawPath(zonePath, Paint()..color = zone.withValues(alpha: 0.18));
    canvas.drawPath(
      zonePath,
      Paint()
        ..color = zone.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Earth's curve: sea level as the radio path sees it.
    canvas.drawPath(
      through((p) => lo + pad * 0.5 + p.bulgeM),
      Paint()
        ..color = curve
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Ground including the curve.
    final groundPath = through((p) => p.effectiveGroundM);
    final fill = Path.from(groundPath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = groundFill);
    canvas.drawPath(
      groundPath,
      Paint()
        ..color = ground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 60 % line, dashed.
    _dashed(
      canvas,
      [for (final p in s) at(p.distanceM, p.lineM - 0.6 * p.fresnelM)],
      Paint()
        ..color = zone
        ..strokeWidth = 1.5,
    );

    // Direct line.
    canvas.drawLine(
      at(0, s.first.lineM),
      at(total, s.last.lineM),
      Paint()
        ..color = line
        ..strokeWidth = 2,
    );

    _label(canvas, mLabel(hi.toStringAsFixed(0)), const Offset(4, 2));
    _label(
      canvas,
      kmLabel((total / 1000).toStringAsFixed(1)),
      Offset(size.width - 4, size.height - 2),
      alignEnd: true,
    );
  }

  void _label(Canvas canvas, String text, Offset at, {bool alignEnd = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, alignEnd ? at - Offset(tp.width, tp.height) : at);
  }

  static void _dashed(Canvas canvas, List<Offset> points, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    var on = true;
    var left = dash;
    for (var i = 1; i < points.length; i++) {
      var a = points[i - 1];
      final b = points[i];
      var seg = (b - a).distance;
      while (seg > 0) {
        final step = math.min(left, seg);
        final next = Offset.lerp(a, b, step / (b - a).distance)!;
        if (on) canvas.drawLine(a, next, paint);
        seg -= step;
        left -= step;
        a = next;
        if (left <= 0) {
          on = !on;
          left = on ? dash : gap;
        }
      }
    }
  }

  @override
  bool shouldRepaint(TerrainProfilePainter old) =>
      old.profile != profile ||
      old.zone != zone ||
      old.ground != ground ||
      old.line != line;
}
