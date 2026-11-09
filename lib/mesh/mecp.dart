import 'dart:convert';

import 'mecp_codes.dart';
import 'plus_code.dart';

/// MECP severities, most serious first; `index` is the digit on the air.
enum MecpSeverity { mayday, urgent, safety, routine }

/// A structured MECP emergency message (`MECP/<severity>/<codes> [text]`).
class MecpMessage {
  const MecpMessage({
    required this.severity,
    required this.codes,
    this.freetext = '',
  });

  final MecpSeverity severity;

  /// Codes as sent; ones this app doesn't know are kept.
  final List<String> codes;

  /// Everything after the codes, conventions included.
  final String freetext;

  /// MECP's size limit, in bytes, for a whole message.
  static const maxBytes = 200;

  static final _shape = RegExp(r'^MECP/([0-3])/(.*)$', dotAll: true);
  static final _code = RegExp(r'^[A-Z]\d\d$');
  static final _pax = RegExp(r'^(\d+)pax$');
  static final _gps = RegExp(r'^(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)$');
  static final _time = RegExp(r'^@(\d{4})$');
  static final _language = RegExp(r'^@([a-z]{2})$');

  /// Reads [text]; null unless it is an MECP message with at least one code.
  static MecpMessage? tryParse(String text) {
    final match = _shape.firstMatch(text.trim());
    if (match == null) return null;
    final words = match[2]!.trim().split(' ');
    final codes = words.takeWhile(_code.hasMatch).toList();
    if (codes.isEmpty) return null;
    return MecpMessage(
      severity: MecpSeverity.values[int.parse(match[1]!)],
      codes: codes,
      freetext: words.skip(codes.length).join(' ').trim(),
    );
  }

  /// The text to send.
  String encode() => [
    'MECP/${severity.index}/${codes.join(' ')}',
    if (freetext.isNotEmpty) freetext,
  ].join(' ');

  /// Size of the encoded message in bytes.
  int get bytes => utf8.encode(encode()).length;

  /// A practice or test (D01, D02), not a real emergency.
  bool get isDrill => codes.contains('D01') || codes.contains('D02');

  List<String> get _words =>
      freetext.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  /// People affected, from `<n>pax`.
  int? get people {
    for (final w in _words) {
      final m = _pax.firstMatch(w);
      if (m != null) return int.tryParse(m[1]!);
    }
    return null;
  }

  /// Coordinates, from `lat,lon` or a Plus Code, if they are on Earth.
  (double, double)? get position {
    for (final w in _words) {
      final m = _gps.firstMatch(w);
      if (m == null) continue;
      final lat = double.parse(m[1]!);
      final lon = double.parse(m[2]!);
      if (lat.abs() <= 90 && lon.abs() <= 180) return (lat, lon);
    }
    for (final w in _words) {
      final p = PlusCode.decode(w);
      if (p != null) return p;
    }
    return null;
  }

  /// The sender's stated time as `HH:MM`, from `@HHMM`.
  String? get time {
    for (final w in _words) {
      final m = _time.firstMatch(w);
      if (m != null) {
        return '${m[1]!.substring(0, 2)}:${m[1]!.substring(2)}';
      }
    }
    return null;
  }

  /// The free text with the recognised conventions taken out.
  String get note => _words
      .where(
        (w) =>
            !_pax.hasMatch(w) &&
            !_gps.hasMatch(w) &&
            PlusCode.decode(w) == null &&
            !_time.hasMatch(w) &&
            !_language.hasMatch(w),
      )
      .join(' ');

  /// What [code] means, or null if this app doesn't know it.
  static String? label(String code) => mecpCodes[code];
}
