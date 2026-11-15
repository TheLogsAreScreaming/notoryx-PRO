import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../mesh/model.dart';

/// Looks up ground heights, metres above sea level, for a list of points.
abstract interface class ElevationLookup {
  /// One height per point, in order. Throws [ElevationException] when the
  /// heights can't be fetched.
  Future<List<double>> heights(List<GeoPoint> points);
}

/// Why ground heights couldn't be fetched.
final class ElevationException implements Exception {
  const ElevationException(this.reason);

  final String reason;

  @override
  String toString() => 'ElevationException: $reason';
}

/// Ground heights from Open-Meteo's free elevation API (Copernicus DEM,
/// about 90 m grid). Only the points asked about are sent, rounded to
/// about 1 m, and only when [heights] is called.
final class OpenMeteoElevation implements ElevationLookup {
  OpenMeteoElevation({http.Client? client}) : _client = client;

  /// The API takes at most this many points per request.
  static const maxPoints = 100;

  static final _base = Uri.parse('https://api.open-meteo.com/v1/elevation');

  final http.Client? _client;

  @override
  Future<List<double>> heights(List<GeoPoint> points) async {
    if (points.isEmpty) return const [];
    if (points.length > maxPoints) {
      throw const ElevationException('too many points');
    }
    String join(double Function(GeoPoint) f) =>
        points.map((p) => f(p).toStringAsFixed(5)).join(',');
    final uri = _base.replace(
      queryParameters: {
        'latitude': join((p) => p.latitude),
        'longitude': join((p) => p.longitude),
      },
    );
    final client = _client ?? http.Client();
    try {
      final r = await client.get(uri).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw ElevationException('HTTP ${r.statusCode}');
      }
      return parseOpenMeteoElevations(r.body, points.length);
    } on ElevationException {
      rethrow;
    } on FormatException catch (e) {
      throw ElevationException('bad reply: ${e.message}');
    } on TimeoutException {
      throw const ElevationException('timed out');
    } on Exception catch (e) {
      throw ElevationException('$e');
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// Reads `{"elevation": [...]}` from Open-Meteo, expecting [count] numbers.
List<double> parseOpenMeteoElevations(String body, int count) {
  final json = jsonDecode(body);
  final list = json is Map ? json['elevation'] : null;
  if (list is! List || list.length != count) {
    throw const FormatException('no elevation list of the right length');
  }
  return [
    for (final v in list)
      if (v is num && v.isFinite)
        v.toDouble()
      else
        throw const FormatException('missing height'),
  ];
}
