import 'dart:convert';

import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// One CSV text cell: quoted when needed, and with a leading `'` when a
/// spreadsheet would otherwise run the text as a formula. Message text
/// comes from strangers on the mesh, so it can't be trusted here.
String csvText(String value) {
  final safe = value.startsWith(RegExp(r'[=+\-@\t\r]')) ? "'$value" : value;
  return safe.contains(RegExp(r'[",\r\n]'))
      ? '"${safe.replaceAll('"', '""')}"'
      : safe;
}

/// Messages as a spreadsheet: times in UTC, one row per message.
///
/// [titles] maps `Conversation.key` to a readable name.
String messagesToCsv(List<StoredMessage> messages, Map<String, String> titles) {
  final out = StringBuffer('﻿')
    ..write(
      'received_utc,sent_utc,conversation,direction,sender,text,delivery,'
      'hops,snr,rssi,via_mqtt\r\n',
    );
  for (final s in messages) {
    final m = s.message;
    out.write(
      [
        m.receivedAt.toUtc().toIso8601String(),
        m.sentAt.toUtc().toIso8601String(),
        csvText(titles[m.conversation.key] ?? m.conversation.key),
        m.outgoing ? 'sent' : 'received',
        csvText(m.senderName ?? m.from?.toString() ?? ''),
        csvText(m.text),
        MeshStore.deliveryCode(m.delivery),
        m.path.hops?.toString() ?? '',
        m.path.snr?.toString() ?? '',
        m.path.rssi?.toString() ?? '',
        m.path.viaMqtt ? 'yes' : 'no',
      ].join(','),
    );
    out.write('\r\n');
  }
  return out.toString();
}

/// Messages as versioned JSON, with every path fact the app keeps.
String messagesToJson(
  List<StoredMessage> messages,
  Map<String, String> titles, {
  required DateTime exportedAt,
}) => const JsonEncoder.withIndent('  ').convert({
  'format': 'notoryx-pro-messages',
  'formatVersion': 1,
  'exportedAtUtc': exportedAt.toUtc().toIso8601String(),
  'messages': [for (final s in messages) _messageJson(s.message, titles)],
});

Map<String, Object?> _messageJson(Message m, Map<String, String> titles) => {
  'conversation': m.conversation.key,
  'conversationTitle': titles[m.conversation.key],
  'outgoing': m.outgoing,
  'text': m.text,
  'sentAtUtc': m.sentAt.toUtc().toIso8601String(),
  'receivedAtUtc': m.receivedAt.toUtc().toIso8601String(),
  'delivery': MeshStore.deliveryCode(m.delivery),
  'deliveryReason': switch (m.delivery) {
    Failed(:final reason) => reason,
    _ => null,
  },
  'from': m.from?.toString(),
  'senderName': m.senderName,
  'hops': m.path.hops,
  'snr': m.path.snr,
  'rssi': m.path.rssi,
  'route': m.path.route.name,
  'viaMqtt': m.path.viaMqtt,
  'authenticated': m.authenticated,
  'isReaction': m.isReaction,
  'nativeId': m.nativeId,
  'replyTo': m.replyTo,
  'attempts': m.attempts,
};
