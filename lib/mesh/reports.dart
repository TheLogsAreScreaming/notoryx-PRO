import 'dart:convert';

/// Field report layouts, sent as ordinary text.
enum ReportKind {
  /// Size, Activity, Location, Unit, Time, Equipment.
  salute(prefix: 'SALUTE', tags: ['S', 'A', 'L', 'U', 'T', 'E']),

  /// The nine-line medical evacuation request.
  nineLine(
    prefix: '9LINE',
    tags: ['1', '2', '3', '4', '5', '6', '7', '8', '9'],
  );

  const ReportKind({required this.prefix, required this.tags});

  /// First word of the message.
  final String prefix;

  /// One short tag for each field, in order.
  final List<String> tags;

  /// The message for [values] (one per tag). Empty fields are left out to
  /// save airtime, and tags keep the remaining fields unambiguous.
  String encode(List<String> values) {
    final parts = <String>[prefix];
    for (var i = 0; i < tags.length && i < values.length; i++) {
      final v = values[i].trim().replaceAll(RegExp(r'\s+'), ' ');
      if (v.isNotEmpty) parts.add('${tags[i]}:$v');
    }
    return parts.join(' ');
  }

  /// Size of the encoded message in bytes.
  int bytes(List<String> values) => utf8.encode(encode(values)).length;

  /// The field where position belongs.
  int get locationField => this == salute ? 2 : 0;
}
