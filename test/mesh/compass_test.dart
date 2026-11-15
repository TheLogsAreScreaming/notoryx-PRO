import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/compass.dart';
import 'package:notoryx_pro/mesh/model.dart';

void main() {
  test('bearing points the right way', () {
    const o = GeoPoint(0, 0);
    expect(bearingDegrees(o, const GeoPoint(1, 0)), closeTo(0, 1e-6));
    expect(bearingDegrees(o, const GeoPoint(0, 1)), closeTo(90, 1e-6));
    expect(bearingDegrees(o, const GeoPoint(-1, 0)), closeTo(180, 1e-6));
    expect(bearingDegrees(o, const GeoPoint(0, -1)), closeTo(270, 1e-6));
  });

  test('turn is the short way round', () {
    expect(turnDegrees(350, 10), closeTo(20, 1e-9));
    expect(turnDegrees(10, 350), closeTo(-20, 1e-9));
    expect(turnDegrees(90, 270), closeTo(180, 1e-9));
    expect(turnDegrees(0, 45), closeTo(45, 1e-9));
  });

  test('smoothing crosses north without spinning', () {
    final h = smoothHeading(359, 1, fraction: 0.5);
    expect(h, closeTo(0, 1e-9));
    expect(smoothHeading(1, 359, fraction: 0.5), closeTo(0, 1e-9));
    expect(smoothHeading(100, 120), closeTo(105, 1e-9));
  });

  test('compass points', () {
    expect(compassPoint(0), 0);
    expect(compassPoint(359), 0);
    expect(compassPoint(44), 1);
    expect(compassPoint(180), 4);
    expect(compassPoint(300), 7);
  });
}
