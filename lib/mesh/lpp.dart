import 'dart:typed_data';

import 'model.dart';
import 'telemetry.dart';

/// Data sizes of the Cayenne LPP types MeshCore nodes send, by type byte.
/// Each reading is `[channel][type][data]`; the size is needed to step
/// over readings this app doesn't use.
const _lppSizes = <int, int>{
  0: 1, // digital in
  1: 1, // digital out
  2: 2, // analog in
  3: 2, // analog out
  100: 4, // generic
  101: 2, // light
  102: 1, // presence
  103: 2, // temperature
  104: 1, // humidity
  113: 6, // accelerometer
  115: 2, // pressure
  116: 2, // voltage
  117: 2, // current
  118: 4, // frequency
  120: 1, // percentage
  121: 2, // altitude
  125: 2, // concentration
  128: 2, // power
  130: 4, // distance
  131: 4, // energy
  132: 2, // direction
  133: 4, // unix time
  134: 6, // gyrometer
  135: 3, // colour
  136: 9, // GPS
  142: 1, // switch
};

const _lppGps = 136;

int _int24(Uint8List b, int at) {
  final v = (b[at] << 16) | (b[at + 1] << 8) | b[at + 2];
  return v & 0x800000 != 0 ? v - 0x1000000 : v;
}

/// The first GPS position in a Cayenne LPP payload; null when there is
/// none, it is 0,0, or the payload holds a type this reader can't step
/// over before reaching it.
GeoPoint? lppPosition(Uint8List lpp) {
  var at = 0;
  while (at + 2 <= lpp.length) {
    final type = lpp[at + 1];
    final size = _lppSizes[type];
    if (size == null || at + 2 + size > lpp.length) return null;
    if (type == _lppGps) {
      final lat = _int24(lpp, at + 2) / 10000;
      final lon = _int24(lpp, at + 5) / 10000;
      final alt = (_int24(lpp, at + 8) / 100).round();
      if ((lat == 0 && lon == 0) || lat.abs() > 90 || lon.abs() > 180) {
        return null;
      }
      return GeoPoint(lat, lon, altitude: alt);
    }
    at += 2 + size;
  }
  return null;
}

int _uint(Uint8List b, int at, int size) {
  var v = 0;
  for (var i = 0; i < size; i++) {
    v = (v << 8) | b[at + i];
  }
  return v;
}

int _int(Uint8List b, int at, int size) {
  final v = _uint(b, at, size);
  final top = 1 << (size * 8 - 1);
  return v & top != 0 ? v - (top << 1) : v;
}

/// The battery and weather readings in a Cayenne LPP payload, as a
/// [TelemetryPoint] for [node]; null when there are none this app keeps.
/// The first reading of each kind wins (channel 1 is the node's own).
TelemetryPoint? lppTelemetry(
  Uint8List lpp, {
  required RadioId radioId,
  required NodeKey node,
  required DateTime time,
}) {
  int? percent;
  double? volts, celsius, humidity, hpa;
  var at = 0;
  while (at + 2 <= lpp.length) {
    final type = lpp[at + 1];
    final size = _lppSizes[type];
    if (size == null || at + 2 + size > lpp.length) break;
    final d = at + 2;
    switch (type) {
      case 116:
        volts ??= _uint(lpp, d, 2) / 100;
      case 103:
        celsius ??= _int(lpp, d, 2) / 10;
      case 104:
        humidity ??= lpp[d] / 2;
      case 115:
        hpa ??= _uint(lpp, d, 2) / 10;
      case 120:
        percent ??= lpp[d];
    }
    at += 2 + size;
  }
  final p = TelemetryPoint(
    radioId: radioId,
    node: node,
    time: time,
    batteryLevel: percent,
    voltage: volts,
    temperature: celsius,
    relativeHumidity: humidity,
    barometricPressure: hpa,
  );
  return p.isEmpty ? null : p;
}
