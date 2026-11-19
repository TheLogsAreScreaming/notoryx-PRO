import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../mesh/diagnostics.dart' show haversineKm;
import '../mesh/model.dart';
import '../mesh/range_rings.dart';

/// The size of a ring label and of a compass tag, in logical pixels.
const ringLabelSize = Size(80, 20);
const compassTagSize = Size(24, 20);

/// The box a node pin covers on the map, in logical pixels.
const ringPinSize = Size(44, 44);

/// Where a ring's label may go, in order: its north point first, then
/// round the ring, so a label pushed off one side shows on another.
const ringLabelBearings = [0.0, 45.0, 315.0, 90.0, 270.0, 135.0, 225.0, 180.0];

/// [at] moved just enough that a [size] box centred on it lies inside
/// [area]; centred in [area] when the box is bigger than it.
Offset clampInto(Offset at, Size size, Rect area) {
  double clamp(double v, double lo, double hi) =>
      lo > hi ? (lo + hi) / 2 : v.clamp(lo, hi);
  return Offset(
    clamp(at.dx, area.left + size.width / 2, area.right - size.width / 2),
    clamp(at.dy, area.top + size.height / 2, area.bottom - size.height / 2),
  );
}

/// The index of the first of [candidates] where a [size] box centred on it
/// lies wholly inside [area] and overlaps none of [taken]; null if none.
int? firstFree(
  List<Offset> candidates,
  Size size,
  Rect area,
  List<Rect> taken,
) {
  for (var i = 0; i < candidates.length; i++) {
    final box = Rect.fromCenter(
      center: candidates[i],
      width: size.width,
      height: size.height,
    );
    final inside =
        box.left >= area.left &&
        box.top >= area.top &&
        box.right <= area.right &&
        box.bottom <= area.bottom;
    if (inside && !taken.any(box.overlaps)) return i;
  }
  return null;
}

/// Among [candidates] whose [size] box lies wholly inside [area] and
/// overlaps none of [taken], the index of the one [covers] overlap least
/// (by area); null if none qualifies.
int? leastCovered(
  List<Offset> candidates,
  Size size,
  Rect area,
  List<Rect> taken,
  List<Rect> covers,
) {
  int? best;
  var bestCovered = double.infinity;
  for (var i = 0; i < candidates.length; i++) {
    final box = Rect.fromCenter(
      center: candidates[i],
      width: size.width,
      height: size.height,
    );
    final inside =
        box.left >= area.left &&
        box.top >= area.top &&
        box.right <= area.right &&
        box.bottom <= area.bottom;
    if (!inside || taken.any(box.overlaps)) continue;
    var covered = 0.0;
    for (final c in covers) {
      final o = box.intersect(c);
      if (o.width > 0 && o.height > 0) covered += o.width * o.height;
    }
    if (covered < bestCovered) {
      best = i;
      bestCovered = covered;
    }
  }
  return best;
}

/// Which part of the range rings a [RangeRingsLayer] draws: the map puts
/// the rings under its pins and the labels over them, so a label never
/// hides under a pin.
enum RingsPart { all, rings, labels }

/// The part of a [size] map not covered by [insets] (toolbars, banners);
/// the whole map when the insets leave nothing.
Rect unobscured(Size size, EdgeInsets insets) {
  final area = insets.deflateRect(Offset.zero & size);
  return area.width > 0 && area.height > 0 ? area : Offset.zero & size;
}

/// Four distance rings around [center], sized to the part of the map you
/// can see, with a label on each ring, faint spokes every 45° and N/E/S/W
/// just outside the outer ring. Labels stay clear of [insets], the edges
/// the map's own controls cover, and off the node [pins] where a clear
/// spot exists. Rebuilds as the map moves.
class RangeRingsLayer extends StatelessWidget {
  const RangeRingsLayer({
    super.key,
    required this.center,
    this.imperial = false,
    this.insets = EdgeInsets.zero,
    this.pins = const [],
    this.part = RingsPart.all,
  });

  /// Which part to draw; see [RingsPart].
  final RingsPart part;

  /// Your position.
  final LatLng center;

  /// Distances in miles rather than metres.
  final bool imperial;

  /// How far in from each edge the map is covered by its controls.
  final EdgeInsets insets;

  /// Where the map draws pins (nodes and your radio). Ring labels pick a
  /// spot on their ring that no pin covers; a ring with no such spot gets
  /// its label where pins cover it least, drawn over them when the map
  /// puts the labels part above its pins.
  final List<LatLng> pins;

  static GeoPoint _geo(LatLng p) => GeoPoint(p.latitude, p.longitude);
  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  /// Metres from the centre of [area] (in screen pixels) to its nearer
  /// edge.
  static double nearEdgeMetres(MapCamera camera, Rect area) {
    final c = _geo(camera.screenOffsetToLatLng(area.center));
    double to(Offset edge) =>
        haversineKm(c, _geo(camera.screenOffsetToLatLng(edge)));
    return [
          to(area.topCenter),
          to(area.bottomCenter),
          to(area.centerLeft),
          to(area.centerRight),
        ].reduce((a, b) => a < b ? a : b) *
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final area = unobscured(
      camera.nonRotatedSize,
      insets + const EdgeInsets.all(4),
    );
    final radii = ringRadii(nearEdgeMetres(camera, area), imperial: imperial);
    final outer = radii.last;
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.onSurface.withValues(alpha: .55);
    final faint = scheme.onSurface.withValues(alpha: .2);
    final from = _geo(center);
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    Widget tag(String text) => ExcludeSemantics(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(text, style: textStyle, maxLines: 1),
          ),
        ),
      ),
    );
    Offset screen(GeoPoint p) => camera.latLngToScreenOffset(_ll(p));

    // Compass tags point the way even when pushed in from an edge.
    final taken = <Rect>[];
    final compass = <Marker>[];
    for (final (bearing, name) in const [
      (0.0, 'N'),
      (90.0, 'E'),
      (180.0, 'S'),
      (270.0, 'W'),
    ]) {
      final at = clampInto(
        screen(pointAt(from, bearing, outer * 1.12)),
        compassTagSize,
        area,
      );
      taken.add(
        Rect.fromCenter(
          center: at,
          width: compassTagSize.width,
          height: compassTagSize.height,
        ),
      );
      compass.add(
        Marker(
          point: camera.screenOffsetToLatLng(at),
          width: compassTagSize.width,
          height: compassTagSize.height,
          child: tag(name),
        ),
      );
    }
    // Pins on screen, so a label can sit somewhere none of them covers.
    final pinBoxes = [
      for (final p in pins)
        Rect.fromCenter(
          center: camera.latLngToScreenOffset(p),
          width: ringPinSize.width,
          height: ringPinSize.height,
        ),
    ];
    // Each ring's label sits on the ring, wherever it can be seen and clear
    // of pins if it can be; a ring with no visible spot goes unlabelled.
    final labels = <Marker>[];
    for (final r in radii) {
      final spots = [for (final b in ringLabelBearings) pointAt(from, b, r)];
      final onScreen = [for (final p in spots) screen(p)];
      final i =
          firstFree(onScreen, ringLabelSize, area, [...taken, ...pinBoxes]) ??
          leastCovered(onScreen, ringLabelSize, area, taken, pinBoxes);
      if (i == null) continue;
      final at = screen(spots[i]);
      taken.add(
        Rect.fromCenter(
          center: at,
          width: ringLabelSize.width,
          height: ringLabelSize.height,
        ),
      );
      labels.add(
        Marker(
          point: _ll(spots[i]),
          width: ringLabelSize.width,
          height: ringLabelSize.height,
          child: tag(ringLabel(r, imperial: imperial)),
        ),
      );
    }
    final drawn = <Widget>[
      if (part != RingsPart.labels) ...[
        PolylineLayer(
          polylines: [
            for (var b = 0; b < 360; b += 45)
              Polyline(
                points: [center, _ll(pointAt(from, b.toDouble(), outer))],
                strokeWidth: 1,
                color: faint,
              ),
          ],
        ),
        CircleLayer(
          circles: [
            for (final r in radii)
              CircleMarker(
                point: center,
                radius: r,
                useRadiusInMeter: true,
                color: scheme.surface.withValues(alpha: 0),
                borderColor: line,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
      ],
      // Labels never take a tap meant for a pin they sit over.
      if (part != RingsPart.rings)
        IgnorePointer(child: MarkerLayer(markers: [...labels, ...compass])),
    ];
    return Stack(
      key: Key(part == RingsPart.labels ? 'range-ring-labels' : 'range-rings'),
      children: drawn,
    );
  }
}
