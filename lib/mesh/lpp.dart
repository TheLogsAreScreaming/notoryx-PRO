import 'dart:typed_data';

import 'model.dart';

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
