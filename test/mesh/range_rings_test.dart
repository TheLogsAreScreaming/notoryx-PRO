import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/diagnostics.dart' show haversineKm;
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/range_rings.dart';

void main() {
  group('niceStep', () {
    test('rounds down to 1, 2 or 5 × 10ⁿ metres', () {
      expect(niceStep(1), 10, reason: 'never below 10 m');
      expect(niceStep(10), 10);
      expect(niceStep(19.9), 10);
      expect(niceStep(20), 20);
      expect(niceStep(49), 20);
      expect(niceStep(50), 50);
      expect(niceStep(99), 50);
      expect(niceStep(100), 100);
      expect(niceStep(740), 500);
      expect(niceStep(1999), 1000);
      expect(niceStep(2500), 2000);
      expect(niceStep(123456), 100000);
    });

    test('in miles, from 0.1 mi', () {
      const mi = metresPerMile;
      expect(niceStep(10, imperial: true), closeTo(0.1 * mi, 1e-6));
      expect(niceStep(0.19 * mi, imperial: true), closeTo(0.1 * mi, 1e-6));
      expect(niceStep(0.2 * mi, imperial: true), closeTo(0.2 * mi, 1e-6));
      expect(niceStep(0.3 * mi, imperial: true), closeTo(0.2 * mi, 1e-6));
      expect(niceStep(0.7 * mi, imperial: true), closeTo(0.5 * mi, 1e-6));
      expect(niceStep(1 * mi, imperial: true), closeTo(1 * mi, 1e-6));
      expect(niceStep(4.9 * mi, imperial: true), closeTo(2 * mi, 1e-6));
      expect(niceStep(12 * mi, imperial: true), closeTo(10 * mi, 1e-6));
    });

    test('odd input falls back to the smallest step', () {
      expect(niceStep(0), 10);
      expect(niceStep(-3), 10);
      expect(niceStep(double.nan), 10);
    });
  });

  group('ringRadii', () {
    test('four rings, a quarter of the nearer edge, rounded down', () {
      expect(ringRadii(3000), [500, 1000, 1500, 2000]);
      expect(ringRadii(4000), [1000, 2000, 3000, 4000]);
      expect(ringRadii(30), [10, 20, 30, 40], reason: 'smallest step');
      final mi = ringRadii(2 * metresPerMile, imperial: true);
      expect(mi, hasLength(ringCount));
      expect(mi.first, closeTo(0.5 * metresPerMile, 1e-6));
      expect(mi.last, closeTo(2 * metresPerMile, 1e-6));
    });
  });

  group('ringLabel', () {
    test('metres under 1 km, then km', () {
      expect(ringLabel(10), '10 m');
      expect(ringLabel(500), '500 m');
      expect(ringLabel(1000), '1 km');
      expect(ringLabel(1500), '1.5 km');
      expect(ringLabel(20000), '20 km');
    });

    test('miles', () {
      expect(ringLabel(0.1 * metresPerMile, imperial: true), '0.1 mi');
      expect(ringLabel(0.3 * metresPerMile, imperial: true), '0.3 mi');
      expect(ringLabel(1.5 * metresPerMile, imperial: true), '1.5 mi');
      expect(ringLabel(20 * metresPerMile, imperial: true), '20 mi');
    });

    test('every ring of a metric or imperial set reads cleanly', () {
      for (final r in ringRadii(700, imperial: true)) {
        expect(ringLabel(r, imperial: true), matches(r'^\d+(\.\d{1,2})? mi$'));
      }
      for (final r in ringRadii(7000)) {
        expect(ringLabel(r), matches(r'^\d+(\.\d{1,2})? k?m$'));
      }
    });
  });

  group('pointAt', () {
    const home = GeoPoint(45.0, -122.0);

    test('lands the asked distance away in each direction', () {
      for (var b = 0; b < 360; b += 45) {
        final p = pointAt(home, b.toDouble(), 2000);
        expect(haversineKm(home, p) * 1000, closeTo(2000, 0.5));
      }
    });

    test('north and east move the right coordinate', () {
      final n = pointAt(home, 0, 1000);
      expect(n.longitude, closeTo(home.longitude, 1e-9));
      expect(n.latitude, greaterThan(home.latitude));
      // 1 km is about 0.008993° of latitude.
      expect(n.latitude - home.latitude, closeTo(0.008993, 1e-5));
      final e = pointAt(home, 90, 1000);
      expect(e.longitude, greaterThan(home.longitude));
      expect(e.latitude, closeTo(home.latitude, 1e-4));
      final s = pointAt(home, 180, 1000);
      expect(s.latitude, lessThan(home.latitude));
      final w = pointAt(home, 270, 1000);
      expect(w.longitude, lessThan(home.longitude));
    });

    test('wraps across the antimeridian', () {
      final p = pointAt(const GeoPoint(0, 179.999), 90, 1000);
      expect(p.longitude, lessThan(-179));
    });

    test('zero distance stays put', () {
      final p = pointAt(home, 123, 0);
      expect(p.latitude, closeTo(home.latitude, 1e-12));
      expect(p.longitude, closeTo(home.longitude, 1e-12));
    });
  });

  test('miles only where they are the local unit', () {
    expect(usesMiles('US'), isTrue);
    expect(usesMiles('us'), isTrue);
    expect(usesMiles('GB'), isFalse);
    expect(usesMiles('DE'), isFalse);
    expect(usesMiles(null), isFalse);
  });
}
