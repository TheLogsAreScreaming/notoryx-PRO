import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One pre-written message snippet.
@immutable
class CannedMessage {
  const CannedMessage({required this.id, required this.text});

  final int id;
  final String text;

  Map<String, Object> toJson() => {'id': id, 't': text};

  static CannedMessage? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final (id, t) = (j['id'], j['t']);
    if (id is! int || t is! String) return null;
    final trimmed = t.trim();
    if (trimmed.isEmpty) return null;
    return CannedMessage(id: id, text: trimmed);
  }
}

/// The saved list of canned messages.
@immutable
class CannedMessages {
  const CannedMessages({this.messages = const []});

  static const prefName = 'canned_messages';

  final List<CannedMessage> messages;

  String encode() =>
      jsonEncode({'messages': [for (final m in messages) m.toJson()]});

  static CannedMessages decode(String? saved) {
    if (saved == null) return const CannedMessages();
    try {
      final j = jsonDecode(saved);
      if (j is! Map<String, Object?>) return const CannedMessages();
      final msgs = j['messages'];
      return CannedMessages(
        messages: msgs is List<Object?>
            ? [for (final m in msgs) ?CannedMessage.fromJson(m)]
            : const [],
      );
    } on FormatException {
      return const CannedMessages();
    }
  }

  CannedMessages add(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return this;
    final nextId = messages.fold(0, (m, e) => e.id > m ? e.id : m) + 1;
    return CannedMessages(
      messages: [...messages, CannedMessage(id: nextId, text: trimmed)],
    );
  }

  CannedMessages remove(int id) =>
      CannedMessages(messages: [for (final m in messages) if (m.id != id) m]);
}
