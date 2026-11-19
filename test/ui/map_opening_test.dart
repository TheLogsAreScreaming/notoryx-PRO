import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:notoryx_pro/ui/map_screen.dart';

void main() {
  test('with nothing to show, the map opens on the whole country', () {
    final o = openingCamera(const []);
    expect(o.center, const LatLng(39.5, -98.35));
    expect(o.zoom, 3);
    expect(o.fit, isNull);
  });

  test('with only your radio, the map opens on it up close', () {
    final o = openingCamera(const [LatLng(41.32, -73.08)]);
    expect(o.center, const LatLng(41.32, -73.08));
    expect(o.zoom, 12);
    expect(o.fit, isNull, reason: 'no camera move after the map opens');
  });

  test('with several points, the map opens with all of them in view', () {
    const points = [LatLng(41.3, -73.1), LatLng(41.5, -72.9)];
    final o = openingCamera(points);
    expect(o.fit, isA<FitCoordinates>());
    expect((o.fit! as FitCoordinates).coordinates, points);
    expect((o.fit! as FitCoordinates).maxZoom, 15);
  });
}
