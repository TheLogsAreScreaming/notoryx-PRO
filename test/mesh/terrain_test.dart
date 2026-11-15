import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/app/elevation.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/terrain.dart';

void main() {
  test('Fresnel radius follows sqrt(lambda d1 d2 / d)', () {
    // 915 MHz, 10 km path, mid-point: lambda = 0.32764 m.
    const lambda = 299792458 / 915e6;
    final expected = math.sqrt(lambda * 5000 * 5000 / 10000);
    expect(fresnelRadiusM(5000, 5000, 915), closeTo(expected, 1e-9));
    expect(expected, closeTo(28.62, 0.01));
    expect(fresnelRadiusM(0, 10000, 915), 0);
  });

  test('Earth bulge uses the 4/3 radius', () {
    // 20 km path: about 5.9 m at mid-path.
    expect(earthBulgeM(10000, 10000), closeTo(5.89, 0.01));
    expect(earthBulgeM(0, 20000), 0);
  });

  test('profile points include both ends, evenly spaced', () {
    const a = GeoPoint(40, -75);
    const b = GeoPoint(41, -74);
    final pts = profilePoints(a, b, count: 5);
    expect(pts, hasLength(5));
    expect(pts.first.latitude, 40);
    expect(pts.last.longitude, -74);
    expect(pts[2].latitude, closeTo(40.5, 1e-9));
  });

  TerrainProfile flat(List<double> elev, {double antenna = 10}) =>
      TerrainProfile.fromElevations(
        elevationsM: elev,
        distanceM: 10000,
        frequencyMHz: 915,
        startAntennaM: antenna,
        endAntennaM: antenna,
      );

  test('flat ground with tall masts is clear', () {
    final p = flat(List.filled(21, 100.0), antenna: 60);
    expect(p.verdict, TerrainVerdict.clear);
    expect(p.worst!.zoneOpen, greaterThanOrEqualTo(0.6));
  });

  test('a low rise into the zone is partial', () {
    final elev = List.filled(21, 100.0);
    elev[10] = 100 + 10 - 2; // 2 m under the line, well inside the zone
    final p = flat(elev);
    expect(p.verdict, TerrainVerdict.partial);
    expect(p.worst!.distanceM, closeTo(5000, 1));
  });

  test('a hill above the line is blocked', () {
    final elev = List.filled(21, 100.0);
    elev[7] = 160;
    final p = flat(elev);
    expect(p.verdict, TerrainVerdict.blocked);
    expect(p.worst!.clearanceM, lessThan(0));
    expect(p.worst!.distanceM, closeTo(3500, 1));
  });

  test('the Earth curve alone can block a long low path', () {
    // 60 km at 2 m masts over sea: bulge at mid-path is about 53 m.
    final p = TerrainProfile.fromElevations(
      elevationsM: List.filled(41, 0.0),
      distanceM: 60000,
      frequencyMHz: 869.5,
    );
    expect(p.verdict, TerrainVerdict.blocked);
  });

  group('Open-Meteo', () {
    const pts = [GeoPoint(45.123456, 7.5), GeoPoint(45.2, 7.6)];

    test('sends the points and reads the heights', () async {
      late Uri asked;
      final lookup = OpenMeteoElevation(
        client: MockClient((r) async {
          asked = r.url;
          return http.Response('{"elevation":[312.0, 1045.5]}', 200);
        }),
      );
      expect(await lookup.heights(pts), [312.0, 1045.5]);
      expect(asked.host, 'api.open-meteo.com');
      expect(asked.path, '/v1/elevation');
      expect(asked.queryParameters['latitude'], '45.12346,45.20000');
      expect(asked.queryParameters['longitude'], '7.50000,7.60000');
    });

    test('bad replies become ElevationException', () async {
      for (final reply in [
        http.Response('nope', 500),
        http.Response('{"elevation":[1]}', 200),
        http.Response('{"elevation":[1, null]}', 200),
        http.Response('not json', 200),
      ]) {
        final lookup = OpenMeteoElevation(
          client: MockClient((_) async => reply),
        );
        await expectLater(
          lookup.heights(pts),
          throwsA(isA<ElevationException>()),
        );
      }
    });

    test('too many points are refused without a request', () async {
      var calls = 0;
      final lookup = OpenMeteoElevation(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        lookup.heights(List.filled(101, pts.first)),
        throwsA(isA<ElevationException>()),
      );
      expect(calls, 0);
    });
  });
}
