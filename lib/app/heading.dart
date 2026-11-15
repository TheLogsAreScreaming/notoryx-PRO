import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../mesh/model.dart';

/// One compass reading: degrees clockwise from magnetic north, and the
/// sensor's accuracy (0 unreliable to 3 high, as Android reports it).
typedef HeadingReading = ({double degrees, int accuracy});

/// Where the compass screen gets the phone's heading and position.
abstract interface class CompassSensors {
  /// Heading readings, or null when this device has no compass.
  Stream<HeadingReading>? headings();

  /// Degrees to add to a magnetic heading to get true north at [at],
  /// or null if unknown.
  Future<double?> declination(GeoPoint at);

  /// The phone's position, but only if location is already allowed.
  /// Never shows a permission prompt.
  Future<GeoPoint?> phonePositionIfAllowed();

  /// The phone's position, asking for permission if needed.
  Future<GeoPoint?> phonePosition();
}

/// The real sensors: the native heading channel on Android, the
/// platform location service on Android and iOS, nothing elsewhere.
class DeviceCompassSensors implements CompassSensors {
  const DeviceCompassSensors();

  static const _heading = EventChannel('notoryx/heading');
  static const _declination = MethodChannel('notoryx/declination');

  bool get _phone => Platform.isAndroid || Platform.isIOS;

  @override
  Stream<HeadingReading>? headings() {
    if (!Platform.isAndroid) return null;
    return _heading.receiveBroadcastStream().map((e) {
      final m = e as Map<Object?, Object?>;
      return (
        degrees: (m['heading']! as num).toDouble(),
        accuracy: (m['accuracy'] as num?)?.toInt() ?? 0,
      );
    });
  }

  @override
  Future<double?> declination(GeoPoint at) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _declination.invokeMethod<double>('declination', {
        'lat': at.latitude,
        'lon': at.longitude,
        'alt': (at.altitude ?? 0).toDouble(),
      });
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<GeoPoint?> phonePositionIfAllowed() async {
    if (!_phone) return null;
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.whileInUse &&
          p != LocationPermission.always) {
        return null;
      }
      return await _read();
    } on Exception {
      return null;
    }
  }

  @override
  Future<GeoPoint?> phonePosition() async {
    if (!_phone) return null;
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p != LocationPermission.whileInUse &&
          p != LocationPermission.always) {
        return null;
      }
      return await _read();
    } on Exception {
      return null;
    }
  }

  Future<GeoPoint?> _read() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return GeoPoint(
      p.latitude,
      p.longitude,
      altitude: p.altitude == 0 ? null : p.altitude.round(),
    );
  }
}
