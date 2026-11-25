import '../radio/connection_log.dart';

/// One connected radio, as far as a bug report needs it: no name, no ID.
class RadioSummary {
  const RadioSummary({
    required this.protocol,
    required this.transport,
    required this.status,
    this.firmware = '',
    this.model = '',
  });

  /// "MeshCore" or "Meshtastic".
  final String protocol;

  /// "Bluetooth", "USB" or "Wi-Fi".
  final String transport;

  /// The link's state, such as `connected` or `reconnecting`.
  final String status;
  final String firmware;
  final String model;
}

/// A plain-text report to attach to a bug report.
///
/// It says which app, system and radios are involved and what the
/// connection log recorded, and leaves out everything personal: no
/// messages, contacts, positions, keys, node or radio names, node IDs,
/// Bluetooth addresses or full IP addresses. Every name or address in
/// [private] is replaced by a placeholder wherever it appears.
String supportReport({
  required String appVersion,
  required String system,
  required String locale,
  required List<RadioSummary> radios,
  required List<LogEntry> log,
  Iterable<String> private = const [],
  DateTime? now,
}) {
  final b = StringBuffer()
    ..writeln('NOTORYX PRO support report')
    ..writeln('Made: ${(now ?? DateTime.now()).toUtc().toIso8601String()}')
    ..writeln('App: $appVersion')
    ..writeln('System: $system')
    ..writeln('Language: $locale')
    ..writeln()
    ..writeln('Radios (${radios.length}):');
  final scrub = Scrubber(private);
  if (radios.isEmpty) b.writeln('  none connected');
  for (final (i, r) in radios.indexed) {
    final parts = [
      r.protocol,
      r.transport,
      r.status,
      if (r.firmware.isNotEmpty) 'firmware ${r.firmware}',
      if (r.model.isNotEmpty) r.model,
    ];
    b.writeln(scrub('  radio ${i + 1}: ${parts.join(', ')}'));
  }
  b
    ..writeln()
    ..writeln(
      'Connection log (${log.length} lines, names and addresses removed):',
    );
  for (final e in log) {
    b.writeln(scrub('$e'));
  }
  b
    ..writeln()
    ..writeln(
      'Not included: messages, contacts, positions, keys, '
      'node and radio names, node IDs and addresses.',
    );
  return b.toString();
}

/// Replaces private text with placeholders.
///
/// Each distinct value of three or more characters in the given list
/// becomes `[name 1]`, `[name 2]`…
/// (longest first, so "Base Camp 2" goes before "Base Camp"). Then anything
/// that looks like a Bluetooth address, a Meshtastic node ID, a long hex key
/// or a full IPv4 address is replaced too, whether or not it was listed.
class Scrubber {
  Scrubber(Iterable<String> private)
    : _names = {
        for (final p in private)
          if (p.trim().length >= 3) p.trim(),
      }.toList()..sort((a, b) => b.length.compareTo(a.length));

  final List<String> _names;

  static final _patterns = <RegExp, String>{
    RegExp(r'\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b'): '[address]',
    RegExp(r'![0-9A-Fa-f]{8}\b'): '[node]',
    RegExp(r'\b[0-9A-Fa-f]{16,}\b'): '[key]',
    RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'): '[ip]',
    RegExp(
      r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
      r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b',
    ): '[device]',
  };

  String call(String text) {
    var out = text;
    for (final (i, name) in _names.indexed) {
      out = out.replaceAll(name, '[name ${i + 1}]');
    }
    for (final MapEntry(key: re, value: label) in _patterns.entries) {
      out = out.replaceAll(re, label);
    }
    return out;
  }
}
