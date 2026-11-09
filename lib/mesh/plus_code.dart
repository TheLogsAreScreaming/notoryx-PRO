/// Open Location Codes ("Plus Codes"), written from the published spec:
/// https://github.com/google/open-location-code/blob/main/Documentation/Specification/specification.md
///
/// Only the standard 10-digit form (about 14 m) is handled, which is all
/// the app sends. It is 11 characters where `lat,lon` to four places can
/// take 18.
abstract final class PlusCode {
  static const _alphabet = '23456789CFGHJMPQRVWX';
  static final _shape = RegExp('^[$_alphabet]{8}\\+[$_alphabet]{2}\$');

  /// Cells per degree at 10 digits.
  static const _cells = 8000;

  /// The 10-digit code for a position.
  static String encode(double latitude, double longitude) {
    final lat = ((latitude.clamp(-90.0, 90.0) + 90) * _cells).floor().clamp(
      0,
      180 * _cells - 1,
    );
    final lon = (((longitude + 180) % 360) * _cells).floor();
    final digits = List.filled(10, '');
    var (a, b) = (lat, lon);
    for (var i = 8; i >= 0; i -= 2) {
      digits[i] = _alphabet[a % 20];
      digits[i + 1] = _alphabet[b % 20];
      a ~/= 20;
      b ~/= 20;
    }
    final s = digits.join();
    return '${s.substring(0, 8)}+${s.substring(8)}';
  }

  /// The centre of a 10-digit code; null if [code] isn't one.
  static (double, double)? decode(String code) {
    final c = code.toUpperCase();
    if (!_shape.hasMatch(c)) return null;
    final digits = c.replaceFirst('+', '');
    var (lat, lon) = (0, 0);
    for (var i = 0; i < 10; i += 2) {
      lat = lat * 20 + _alphabet.indexOf(digits[i]);
      lon = lon * 20 + _alphabet.indexOf(digits[i + 1]);
    }
    final latitude = (lat + .5) / _cells - 90;
    final longitude = (lon + .5) / _cells - 180;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return (latitude, longitude);
  }
}
