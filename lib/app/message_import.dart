import 'dart:convert';
import 'dart:typed_data';

import '../mesh/model.dart';
import '../mesh/node_look.dart';
import '../store/mesh_store.dart';

/// Why a file can't be restored at all.
enum RestoreProblem { notAnExport, tooNew }

/// A file that can't be restored; nothing has been changed.
class RestoreRefused implements Exception {
  const RestoreRefused(this.problem);
  final RestoreProblem problem;
}

/// The readable contents of an export file.
class ParsedExport {
  const ParsedExport(this.messages, this.unreadable, {this.looks = const {}});

  /// Messages in the order they arrived.
  final List<Message> messages;

  /// Node colours and photos, keyed by `NodeKey` text.
  final Map<String, NodeLook> looks;

  /// Entries that couldn't be understood and will be left out.
  final int unreadable;
}

/// Reads a JSON export made by `messagesToJson`.
///
/// The file may have been edited or come from someone else, so every field
/// is checked. For the same reason the "sender proven by encryption" flag
/// is never taken from a file: anyone could set it to fake a verified badge.
///
/// Throws [RestoreRefused] if this isn't an export this version can read.
ParsedExport parseExport(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const RestoreRefused(RestoreProblem.notAnExport);
  }
  if (root is! Map<String, Object?> ||
      root['format'] != 'notoryx-pro-messages' ||
      root['formatVersion'] is! int ||
      root['messages'] is! List<Object?>) {
    throw const RestoreRefused(RestoreProblem.notAnExport);
  }
  if ((root['formatVersion']! as int) > 1) {
    throw const RestoreRefused(RestoreProblem.tooNew);
  }
  final out = <Message>[];
  var unreadable = 0;
  for (final entry in root['messages']! as List<Object?>) {
    final m = entry is Map<String, Object?> ? _message(entry) : null;
    if (m == null) {
      unreadable++;
    } else {
      out.add(m);
    }
  }
  out.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  return ParsedExport(out, unreadable, looks: _looks(root['nodeLooks']));
}

/// The largest photo accepted from a file, so a crafted backup can't fill
/// the database.
const maxLookPhotoBytes = 256 * 1024;

Map<String, NodeLook> _looks(Object? raw) {
  if (raw is! List<Object?>) return const {};
  final out = <String, NodeLook>{};
  for (final e in raw.take(5000)) {
    if (e is! Map<String, Object?>) continue;
    final node = e['node'];
    if (node is! String || NodeKey.tryParse(node) == null) continue;
    final color = e['color'];
    Uint8List? photo;
    if (e['photo'] case final String b64) {
      try {
        final bytes = base64Decode(b64);
        if (bytes.length <= maxLookPhotoBytes) photo = bytes;
      } on FormatException {
        // Leave the photo out; keep the colour.
      }
    }
    final look = NodeLook(color: color is int ? color : null, photo: photo);
    if (!look.isEmpty) out[node] = look;
  }
  return out;
}

T? _as<T>(Object? v) => v is T ? v : null;

DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

Message? _message(Map<String, Object?> j) {
  final key = _as<String>(j['conversation']);
  final conversation = key == null ? null : Conversation.tryParse(key);
  final text = _as<String>(j['text']);
  final outgoing = _as<bool>(j['outgoing']);
  final sentAt = _time(j['sentAtUtc']);
  final receivedAt = _time(j['receivedAtUtc']);
  if (conversation == null ||
      text == null ||
      outgoing == null ||
      sentAt == null ||
      receivedAt == null) {
    return null;
  }
  final from = _as<String>(j['from']);
  return Message(
    conversation: conversation,
    text: text,
    outgoing: outgoing,
    sentAt: sentAt,
    receivedAt: receivedAt,
    delivery: MeshStore.deliveryFromExport(
      _as<String>(j['delivery']),
      _as<String>(j['deliveryReason']),
      outgoing: outgoing,
    ),
    from: from == null ? null : NodeKey.tryParse(from),
    senderName: _as<String>(j['senderName']),
    path: PathFacts(
      hops: _as<int>(j['hops']),
      snr: _as<num>(j['snr'])?.toDouble(),
      rssi: _as<int>(j['rssi']),
      route: RouteKind.values.asNameMap()[j['route']] ?? PathFacts.none.route,
      viaMqtt: _as<bool>(j['viaMqtt']) ?? false,
    ),
    nativeId: _as<int>(j['nativeId']),
    replyTo: _as<int>(j['replyTo']),
    isReaction: _as<bool>(j['isReaction']) ?? false,
    attempts: _as<int>(j['attempts']) ?? 0,
  );
}
