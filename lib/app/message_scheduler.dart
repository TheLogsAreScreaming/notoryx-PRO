import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// Where a scheduled message has got to.
enum ScheduleState { waiting, missed, failed }

/// A message to send later.
@immutable
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.conversation,
    required this.text,
    required this.at,
    this.state = ScheduleState.waiting,
  });

  final int id;
  final Conversation conversation;
  final String text;
  final DateTime at;
  final ScheduleState state;

  ScheduledMessage withState(ScheduleState s) => ScheduledMessage(
    id: id,
    conversation: conversation,
    text: text,
    at: at,
    state: s,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'c': conversation.key,
    't': text,
    'at': at.toUtc().toIso8601String(),
    's': state.name,
  };

  static ScheduledMessage? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final id = j['id'];
    final key = j['c'];
    final text = j['t'];
    final at = j['at'];
    if (id is! int || key is! String || text is! String || at is! String) {
      return null;
    }
    final c = Conversation.tryParse(key);
    final time = DateTime.tryParse(at);
    if (c == null || time == null) return null;
    return ScheduledMessage(
      id: id,
      conversation: c,
      text: text,
      at: time.toLocal(),
      state: ScheduleState.values.asNameMap()[j['s']] ?? ScheduleState.waiting,
    );
  }
}

/// Sends messages at the time people asked for, while the app is running.
///
/// Sends at most once: a message leaves the saved list before it goes to
/// the radio, so a crash can lose one but never repeat one. If the radio
/// isn't connected when it falls due, it waits up to [grace], then stays
/// on the list marked as missed instead of going out long after it
/// stopped making sense.
class MessageScheduler {
  MessageScheduler({
    required this.store,
    required this.send,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Preference the list is saved under.
  static const prefName = 'scheduled';

  /// How late a message may still go out.
  static const grace = Duration(hours: 1);

  final MeshStore store;

  /// Sends now; false if the radio isn't connected. Throws if sending fails.
  final Future<bool> Function(Conversation, String) send;
  final DateTime Function() _now;

  Timer? _timer;
  Future<void> _queue = Future.value();

  static List<ScheduledMessage> decode(String? saved) {
    if (saved == null) return const [];
    try {
      final list = jsonDecode(saved);
      if (list is! List<Object?>) return const [];
      return [for (final j in list) ?ScheduledMessage.fromJson(j)]
        ..sort((a, b) => a.at.compareTo(b.at));
    } on FormatException {
      return const [];
    }
  }

  /// The list as it changes.
  Stream<List<ScheduledMessage>> watch() =>
      store.watchPreference(prefName).map(decode);

  Future<List<ScheduledMessage>> _read() async =>
      decode(await store.preference(prefName));

  Future<void> _write(List<ScheduledMessage> items) => store.setPreference(
    prefName,
    jsonEncode([for (final m in items) m.toJson()]),
  );

  Future<T> _serial<T>(Future<T> Function() job) {
    final done = _queue.then((_) => job());
    _queue = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  /// Adds a message to send at [at].
  Future<void> add(Conversation conversation, String text, DateTime at) =>
      _serial(() async {
        final items = await _read();
        final id = _now().microsecondsSinceEpoch;
        await _write([
          ...items,
          ScheduledMessage(
            id: id,
            conversation: conversation,
            text: text,
            at: at,
          ),
        ]);
      });

  /// Removes a message from the list.
  Future<void> remove(int id) => _serial(() async {
    await _write([
      for (final m in await _read())
        if (m.id != id) m,
    ]);
  });

  /// Sends whatever is due.
  Future<void> tick() => _serial(() async {
    final now = _now();
    for (final m in await _read()) {
      if (m.state != ScheduleState.waiting || m.at.isAfter(now)) continue;
      if (now.difference(m.at) > grace) {
        await _replace(m, m.withState(ScheduleState.missed));
        continue;
      }
      await _replace(m, null);
      try {
        final sent = await send(m.conversation, m.text);
        if (!sent) await _put(m);
      } on Object catch (e) {
        debugPrint('scheduled send: $e');
        await _put(m.withState(ScheduleState.failed));
      }
    }
  });

  Future<void> _replace(ScheduledMessage m, ScheduledMessage? next) async {
    await _write([
      for (final x in await _read())
        if (x.id != m.id) x else ?next,
    ]);
  }

  Future<void> _put(ScheduledMessage m) async => _write([...await _read(), m]);

  /// Starts checking the clock.
  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(tick()),
    );
  }

  /// Stops checking the clock.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
