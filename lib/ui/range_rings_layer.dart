import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../mesh/diagnostics.dart' show haversineKm;
import '../mesh/model.dart';
import '../mesh/range_rings.dart';

/// Four distance rings around [center], sized to the visible map, with a
/// label at each ring's north point, faint spokes every 45° and N/E/S/W
/// just outside the outer ring. Rebuilds as the map moves.
class RangeRingsLayer extends StatelessWidget {
  const RangeRingsLayer({
    super.key,
    required this.center,
    this.imperial = false,
  });

  /// Your position.
  final LatLng center;

  /// Distances in miles rather than metres.
  final bool imperial;

  static GeoPoint _geo(LatLng p) => GeoPoint(p.latitude, p.longitude);
  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  /// Metres from the view's centre to its nearer edge.
  static double nearEdgeMetres(MapCamera camera) {
    final b = camera.visibleBounds;
    final c = _geo(camera.center);
    final toNorth = haversineKm(c, GeoPoint(b.north, c.longitude));
    final toSouth = haversineKm(c, GeoPoint(b.south, c.longitude));
    final toEast = haversineKm(c, GeoPoint(c.latitude, b.east));
    final toWest = haversineKm(c, GeoPoint(c.latitude, b.west));
    return [toNorth, toSouth, toEast, toWest].reduce((a, b) => a < b ? a : b) *
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final radii = ringRadii(nearEdgeMetres(camera), imperial: imperial);
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
    return Stack(
      key: const Key('range-rings'),
      children: [
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
        MarkerLayer(
          markers: [
            for (final r in radii)
              Marker(
                point: _ll(pointAt(from, 0, r)),
                width: 80,
                height: 20,
                child: tag(ringLabel(r, imperial: imperial)),
              ),
            for (final (bearing, name) in const [
              (0.0, 'N'),
              (90.0, 'E'),
              (180.0, 'S'),
              (270.0, 'W'),
            ])
              Marker(
                point: _ll(pointAt(from, bearing, outer * 1.12)),
                width: 24,
                height: 20,
                child: tag(name),
              ),
          ],
        ),
      ],
    );
  }
}
