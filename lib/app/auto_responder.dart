import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mesh/mecp.dart';
import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// One automatic reply.
@immutable
class AutoRule {
  const AutoRule({
    required this.id,
    required this.keyword,
    required this.reply,
    this.channels = false,
  });

  /// Matches when the whole message is this, ignoring case and spaces at
  /// the ends. [away] matches every direct message.
  static const away = '*';

  final int id;
  final String keyword;

  /// May use `{name}`, `{time}`, `{hops}` and `{snr}`.
  final String reply;

  /// Also answers on channels. Never allowed for [away].
  final bool channels;

  bool get isAway => keyword == away;

  Map<String, Object> toJson() => {
    'id': id,
    'k': keyword,
    'r': reply,
    'c': channels,
  };

  static AutoRule? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final (id, k, r) = (j['id'], j['k'], j['r']);
    if (id is! int || k is! String || r is! String) return null;
    if (k.trim().isEmpty || r.trim().isEmpty) return null;
    return AutoRule(
      id: id,
      keyword: k.trim(),
      reply: r,
      channels: j['c'] == true && k.trim() != away,
    );
  }
}

/// Whether auto-replies are on, and the rules.
@immutable
class AutoSettings {
  const AutoSettings({this.on = false, this.rules = const []});

  final bool on;
  final List<AutoRule> rules;

  String encode() => jsonEncode({
    'on': on,
    'rules': [for (final r in rules) r.toJson()],
  });

  static AutoSettings decode(String? saved) {
    if (saved == null) return const AutoSettings();
    try {
      final j = jsonDecode(saved);
      if (j is! Map<String, Object?>) return const AutoSettings();
      final rules = j['rules'];
      return AutoSettings(
        on: j['on'] == true,
        rules: rules is List<Object?>
            ? [for (final r in rules) ?AutoRule.fromJson(r)]
            : const [],
      );
    } on FormatException {
      return const AutoSettings();
    }
  }
}

/// Answers messages automatically, within firm limits.
///
/// Off until switched on. It never answers an emergency message, a reaction
/// or another automatic reply, and every reply is marked `[auto]`, so two
/// bots can't talk to each other forever. Old messages arriving after a
/// reconnect are ignored.
class AutoResponder {
  AutoResponder({
    required this.store,
    required this.send,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Preference the settings are saved under.
  static const prefName = 'autoreply';

  static const marker = '[auto] ';

  /// Shortest gap between replies to one sender for a keyword.
  static const perSender = Duration(minutes: 5);

  /// Shortest gap between away replies to one sender.
  static const perSenderAway = Duration(hours: 1);

  /// The most replies in any hour, across all rules.
  static const maxPerHour = 10;

  /// Older messages are backlog, not someone waiting on an answer.
  static const maxAge = Duration(minutes: 10);

  final MeshStore store;

  /// Sends a reply; false if the radio isn't connected.
  final Future<bool> Function(Conversation, String) send;
  final DateTime Function() _now;

  StreamSubscription<StoredMessage>? _incoming;
  StreamSubscription<String?>? _prefs;
  AutoSettings _settings = const AutoSettings();
  final Map<String, DateTime> _last = {};
  final List<DateTime> _recent = [];

  /// Applies new settings; the saved ones arrive here too.
  set settings(AutoSettings s) => _settings = s;

  /// Starts answering, if switched on.
  void start() {
    _prefs ??= store
        .watchPreference(prefName)
        .listen((v) => _settings = AutoSettings.decode(v));
    _incoming ??= store.incoming.listen((s) => unawaited(handle(s.message)));
  }

  /// Stops answering.
  void stop() {
    unawaited(_prefs?.cancel());
    unawaited(_incoming?.cancel());
    _prefs = null;
    _incoming = null;
  }

  /// The rule that answers [m], if any.
  AutoRule? _match(Message m) {
    final dm = m.conversation is DirectConversation;
    final text = m.text.trim().toLowerCase();
    AutoRule? fallback;
    for (final r in _settings.rules) {
      if (r.isAway) {
        if (dm) fallback ??= r;
      } else if (r.keyword.toLowerCase() == text && (dm || r.channels)) {
        return r;
      }
    }
    return fallback;
  }

  String _fill(AutoRule r, Message m) {
    final t = TimeOfDayText.of(_now());
    return r.reply
        .replaceAll('{name}', m.senderName ?? m.from?.short ?? '')
        .replaceAll('{time}', t)
        .replaceAll('{hops}', m.path.hops?.toString() ?? '?')
        .replaceAll('{snr}', m.path.snr?.toString() ?? '?');
  }

  /// Answers [m] if a rule and the limits allow it.
  Future<void> handle(Message m) async {
    if (!_settings.on || m.outgoing || m.isReaction) return;
    if (m.text.trimLeft().startsWith(marker.trim())) return;
    if (MecpMessage.tryParse(m.text) != null) return;
    final now = _now();
    if (now.difference(m.sentAt).abs() > maxAge) return;
    final rule = _match(m);
    if (rule == null) return;
    final who = m.from?.toString() ?? m.senderName ?? m.conversation.key;
    final key = '${rule.id}|${m.conversation.key}|$who';
    final last = _last[key];
    final gap = rule.isAway ? perSenderAway : perSender;
    if (last != null && now.difference(last) < gap) return;
    _recent.removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
    if (_recent.length >= maxPerHour) return;
    _last[key] = now;
    _recent.add(now);
    try {
      await send(m.conversation, '$marker${_fill(rule, m)}');
    } on Object catch (e) {
      debugPrint('auto reply: $e');
    }
  }
}

/// `HH:MM` for a reply.
abstract final class TimeOfDayText {
  static String of(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
