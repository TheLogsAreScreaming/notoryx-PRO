import 'package:xml/xml.dart';

import 'model.dart';
import 'places.dart';

/// A file that isn't GPX.
class NotGpx implements Exception {
  const NotGpx();
}

/// The most points kept from one route or track.
const maxRoutePoints = 5000;

const _fenceType = 'notoryx-geofence';

GeoPoint? _point(XmlElement e) {
  final lat = double.tryParse(e.getAttribute('lat') ?? '');
  final lon = double.tryParse(e.getAttribute('lon') ?? '');
  if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
    return null;
  }
  final ele = e.getElement('ele')?.innerText;
  return GeoPoint(
    lat,
    lon,
    altitude: ele == null ? null : double.tryParse(ele)?.round(),
  );
}

String _name(XmlElement e, String fallback) {
  final n = e.getElement('name')?.innerText.trim() ?? '';
  return n.isEmpty ? fallback : n;
}

/// Reads waypoints, routes and tracks. Bad points are skipped; throws
/// [NotGpx] for anything that isn't a GPX file.
List<Place> parseGpx(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException {
    throw const NotGpx();
  }
  final root = doc.rootElement;
  if (root.localName != 'gpx') throw const NotGpx();
  final out = <Place>[];
  for (final w in root.findElements('wpt')) {
    final p = _point(w);
    if (p == null) continue;
    final type = w.getElement('type')?.innerText ?? '';
    final radius = type.startsWith('$_fenceType:')
        ? double.tryParse(type.substring(_fenceType.length + 1))
        : null;
    out.add(
      Place(
        kind: radius != null && radius > 0
            ? PlaceKind.geofence
            : PlaceKind.waypoint,
        name: _name(w, 'Waypoint'),
        points: [p],
        radiusM: radius != null && radius > 0 ? radius : null,
      ),
    );
  }
  void line(XmlElement e, Iterable<XmlElement> pts, String fallback) {
    final points = [for (final p in pts) ?_point(p)];
    if (points.length < 2) return;
    out.add(
      Place(
        kind: PlaceKind.route,
        name: _name(e, fallback),
        points: points.take(maxRoutePoints).toList(),
      ),
    );
  }

  for (final r in root.findElements('rte')) {
    line(r, r.findElements('rtept'), 'Route');
  }
  for (final t in root.findElements('trk')) {
    line(t, t.findAllElements('trkpt'), 'Track');
  }
  return out;
}

/// GPX 1.1 for [places]. Geofences become waypoints with a `type` that
/// keeps their radius; other apps just see a waypoint.
String writeGpx(List<Place> places) {
  final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
  void at(GeoPoint p) {
    b.attribute('lat', p.latitude);
    b.attribute('lon', p.longitude);
    if (p.altitude != null) b.element('ele', nest: p.altitude);
  }

  b.element(
    'gpx',
    nest: () {
      b.attribute('version', '1.1');
      b.attribute('creator', 'NOTORYX PRO');
      b.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
      for (final p in places) {
        if (p.kind == PlaceKind.route) continue;
        b.element(
          'wpt',
          nest: () {
            at(p.points.first);
            b.element('name', nest: p.name);
            if (p.kind == PlaceKind.geofence) {
              b.element('type', nest: '$_fenceType:${p.radiusM}');
            }
          },
        );
      }
      for (final p in places) {
        if (p.kind != PlaceKind.route) continue;
        b.element(
          'rte',
          nest: () {
            b.element('name', nest: p.name);
            for (final x in p.points) {
              b.element('rtept', nest: () => at(x));
            }
          },
        );
      }
    },
  );
  return b.buildDocument().toXmlString(pretty: true);
}
