import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One channel slot as a radio holds it: index, name and 16-byte secret.
class SlotCopy {
  const SlotCopy({
    required this.index,
    required this.name,
    required this.secret,
  });

  final int index;
  final String name;
  final Uint8List secret;

  bool get isEmpty => name.isEmpty && secret.every((b) => b == 0);

  bool sameAs(SlotCopy other) {
    if (name != other.name || secret.length != other.secret.length) {
      return false;
    }
    for (var i = 0; i < secret.length; i++) {
      if (secret[i] != other.secret[i]) return false;
    }
    return true;
  }

  Map<String, Object> toJson() => {
    'i': index,
    'n': name,
    's': base64Encode(secret),
  };

  static SlotCopy? fromJson(Object? json) {
    if (json is! Map) return null;
    final i = json['i'], n = json['n'], s = json['s'];
    if (i is! int || n is! String || s is! String) return null;
    try {
      return SlotCopy(index: i, name: n, secret: base64Decode(s));
    } on FormatException {
      return null;
    }
  }

  /// Short and safe to show: the first four bytes of the secret's SHA-256.
  String get fingerprint {
    final d = sha256.convert(secret).bytes;
    String h(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${h(d[0])}${h(d[1])} ${h(d[2])}${h(d[3])}';
  }
}

/// A slot where the radio no longer holds what the app last saw there.
class ChannelConflict {
  const ChannelConflict({required this.app, this.radio});

  /// What the app last saw (and can write back).
  final SlotCopy app;

  /// What the radio holds now; null when the slot is empty.
  final SlotCopy? radio;

  int get index => app.index;
  bool get nameDiffers => radio == null || radio!.name != app.name;
  bool get secretDiffers => radio == null || !radio!.sameAs(app);
}

/// Compares the app's last copy of a radio's channels with what the radio
/// returned now.
///
/// Slots in [pending] are unanswered conflicts: there the app's side is the
/// pending copy. A slot the app never saw is new, not a conflict. Only
/// slots below [slots] are compared.
List<ChannelConflict> findChannelConflicts({
  required List<SlotCopy> saved,
  required List<SlotCopy> radio,
  required int slots,
  List<SlotCopy> pending = const [],
}) {
  final mine = {
    for (final c in saved)
      if (!c.isEmpty) c.index: c,
    for (final c in pending) c.index: c,
  };
  final theirs = {
    for (final c in radio)
      if (!c.isEmpty) c.index: c,
  };
  return [
    for (final index in mine.keys.toList()..sort())
      if (index < slots && !(theirs[index]?.sameAs(mine[index]!) ?? false))
        ChannelConflict(app: mine[index]!, radio: theirs[index]),
  ];
}

String encodeSlots(Iterable<SlotCopy> slots) =>
    jsonEncode([for (final s in slots) s.toJson()]);

List<SlotCopy> decodeSlots(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [for (final item in list) ?SlotCopy.fromJson(item)];
  } on FormatException {
    return const [];
  }
}
