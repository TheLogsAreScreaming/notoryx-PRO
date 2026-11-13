import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mesh/diagnostics.dart' show haversineKm;
import '../mesh/mecp.dart';
import '../mesh/model.dart';
import '../mesh/places.dart';
import '../store/mesh_store.dart';
import 'auto_responder.dart' show AutoResponder, TimeOfDayText;

// ---------------------------------------------------------------- triggers

/// What starts an automation.
sealed class AutoTrigger {
  const AutoTrigger();

  Map<String, Object?> toJson();

  static AutoTrigger? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    NodeKey? node(Object? v) => v is String ? NodeKey.tryParse(v) : null;
    RadioId? radio(Object? v) => v is String ? RadioId.tryParse(v) : null;
    final n = node(j['node']);
    final r = radio(j['radio']);
    switch (j['t']) {
      case 'battery':
        final below = j['below'];
        if (below is! int || n == null || r == null) return null;
        return BatteryTrigger(radio: r, node: n, below: below.clamp(1, 99));
      case 'time':
        final (h, m, days) = (j['h'], j['m'], j['days']);
        if (h is! int || m is! int || days is! List<Object?>) return null;
        return TimeTrigger(
          hour: h.clamp(0, 23),
          minute: m.clamp(0, 59),
          weekdays: {
            for (final d in days)
              if (d is int && d >= 1 && d <= 7) d,
          },
        );
      case 'fence':
        final (place, enter) = (j['place'], j['enter']);
        if (place is! int || enter is! bool) return null;
        return GeofenceTrigger(place: place, enter: enter, radio: r, node: n);
      case 'message':
        final c = j['conv'];
        return MessageTrigger(
          contains: j['has'] is String ? j['has'] as String : '',
          conversation: c is String ? Conversation.tryParse(c) : null,
          directOnly: j['dm'] == true,
        );
      case 'online':
        final mins = j['after'];
        if (n == null || r == null || mins is! int) return null;
        return PresenceTrigger(
          radio: r,
          node: n,
          online: j['on'] == true,
          after: Duration(minutes: mins.clamp(5, 24 * 60)),
        );
    }
    return null;
  }
}

/// A node's battery falls below [below] percent.
final class BatteryTrigger extends AutoTrigger {
  const BatteryTrigger({
    required this.radio,
    required this.node,
    required this.below,
  });

  final RadioId radio;
  final NodeKey node;
  final int below;

  @override
  Map<String, Object?> toJson() => {
    't': 'battery',
    'radio': radio.toString(),
    'node': node.toString(),
    'below': below,
  };
}

/// A time of day, on some days of the week (1 = Monday … 7 = Sunday; none
/// means every day).
final class TimeTrigger extends AutoTrigger {
  const TimeTrigger({
    required this.hour,
    required this.minute,
    this.weekdays = const {},
  });

  final int hour;
  final int minute;
  final Set<int> weekdays;

  bool matches(DateTime t) =>
      t.hour == hour &&
      t.minute == minute &&
      (weekdays.isEmpty || weekdays.contains(t.weekday));

  @override
  Map<String, Object?> toJson() => {
    't': 'time',
    'h': hour,
    'm': minute,
    'days': weekdays.toList()..sort(),
  };
}

/// A node enters or leaves geofence [place]; any node when [node] is null.
final class GeofenceTrigger extends AutoTrigger {
  const GeofenceTrigger({
    required this.place,
    required this.enter,
    this.radio,
    this.node,
  });

  final int place;
  final bool enter;
  final RadioId? radio;
  final NodeKey? node;

  bool watches(Node n) =>
      node == null || (n.key == node && (radio == null || n.radioId == radio));

  @override
  Map<String, Object?> toJson() => {
    't': 'fence',
    'place': place,
    'enter': enter,
    if (radio != null) 'radio': radio.toString(),
    if (node != null) 'node': node.toString(),
  };
}

/// A message arrives, optionally containing [contains] (ignoring case),
/// in one [conversation], or only direct messages.
final class MessageTrigger extends AutoTrigger {
  const MessageTrigger({
    this.contains = '',
    this.conversation,
    this.directOnly = false,
  });

  final String contains;
  final Conversation? conversation;
  final bool directOnly;

  bool matches(Message m) {
    if (conversation != null && m.conversation.key != conversation!.key) {
      return false;
    }
    if (directOnly && m.conversation is! DirectConversation) return false;
    final want = contains.trim().toLowerCase();
    return want.isEmpty || m.text.toLowerCase().contains(want);
  }

  @override
  Map<String, Object?> toJson() => {
    't': 'message',
    if (contains.isNotEmpty) 'has': contains,
    if (conversation != null) 'conv': conversation!.key,
    if (directOnly) 'dm': true,
  };
}

/// A node comes back ([online]) after not being heard for [after], or
/// goes quiet for [after].
final class PresenceTrigger extends AutoTrigger {
  const PresenceTrigger({
    required this.radio,
    required this.node,
    required this.online,
    this.after = const Duration(minutes: 30),
  });

  final RadioId radio;
  final NodeKey node;
  final bool online;
  final Duration after;

  @override
  Map<String, Object?> toJson() => {
    't': 'online',
    'radio': radio.toString(),
    'node': node.toString(),
    'on': online,
    'after': after.inMinutes,
  };
}

// ----------------------------------------------------------------- actions

/// What an automation does.
sealed class AutoAction {
  const AutoAction();

  Map<String, Object?> toJson();

  /// Whether it reaches the internet.
  bool get needsInternet => false;

  static AutoAction? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    switch (j['a']) {
      case 'send':
        final (c, text) = (j['conv'], j['text']);
        final conv = c is String ? Conversation.tryParse(c) : null;
        if (conv == null || text is! String || text.trim().isEmpty) {
          return null;
        }
        return SendAction(conversation: conv, text: text);
      case 'alert':
        final text = j['text'];
        return text is String && text.trim().isNotEmpty
            ? AlertAction(text)
            : null;
      case 'channel':
        final (r, link) = (j['radio'], j['link']);
        final radio = r is String ? RadioId.tryParse(r) : null;
        if (radio == null || link is! String) return null;
        return JoinChannelAction(radio: radio, link: link);
      case 'sound':
        return const SoundAction();
      case 'webhook':
        final url = j['url'];
        if (url is! String || !WebhookAction.validUrl(url)) return null;
        return WebhookAction(url);
    }
    return null;
  }
}

/// Sends [text] (with `{node}`, `{battery}`, `{place}`, `{time}`, `{text}`
/// and `{rule}` filled in) to [conversation].
final class SendAction extends AutoAction {
  const SendAction({required this.conversation, required this.text});

  final Conversation conversation;
  final String text;

  @override
  Map<String, Object?> toJson() => {
    'a': 'send',
    'conv': conversation.key,
    'text': text,
  };
}

/// Shows a notification on this device.
final class AlertAction extends AutoAction {
  const AlertAction(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'a': 'alert', 'text': text};
}

/// Changes channel: joins the channel in [link] on [radio] (a channel
/// already on the radio is left as it is).
final class JoinChannelAction extends AutoAction {
  const JoinChannelAction({required this.radio, required this.link});

  final RadioId radio;
  final String link;

  @override
  Map<String, Object?> toJson() => {
    'a': 'channel',
    'radio': radio.toString(),
    'link': link,
  };
}

/// Plays the system alert sound.
final class SoundAction extends AutoAction {
  const SoundAction();

  @override
  Map<String, Object?> toJson() => {'a': 'sound'};
}

/// Posts what happened, as JSON, to [url]. Needs internet, and only runs
/// while web requests are allowed in [AutomationSettings].
final class WebhookAction extends AutoAction {
  const WebhookAction(this.url);

  final String url;

  @override
  bool get needsInternet => true;

  /// An absolute http(s) address with a host.
  static bool validUrl(String text) {
    final u = Uri.tryParse(text.trim());
    return u != null &&
        (u.scheme == 'https' || u.scheme == 'http') &&
        u.host.isNotEmpty;
  }

  @override
  Map<String, Object?> toJson() => {'a': 'webhook', 'url': url};
}

// ------------------------------------------------------------------- rules

/// One automation: when its triggers fire (any of them, or all at once),
/// run its actions.
@immutable
class Automation {
  const Automation({
    required this.id,
    required this.name,
    this.enabled = true,
    this.matchAll = false,
    this.triggers = const [],
    this.actions = const [],
    this.cooldown = const Duration(minutes: 5),
  });

  final int id;
  final String name;
  final bool enabled;

  /// AND: every trigger must hold when one fires. OR (false): any fires.
  final bool matchAll;
  final List<AutoTrigger> triggers;
  final List<AutoAction> actions;

  /// The shortest time between two runs of this rule.
  final Duration cooldown;

  Automation copyWith({
    String? name,
    bool? enabled,
    bool? matchAll,
    List<AutoTrigger>? triggers,
    List<AutoAction>? actions,
    Duration? cooldown,
  }) => Automation(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    matchAll: matchAll ?? this.matchAll,
    triggers: triggers ?? this.triggers,
    actions: actions ?? this.actions,
    cooldown: cooldown ?? this.cooldown,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'on': enabled,
    'all': matchAll,
    'cool': cooldown.inMinutes,
    'when': [for (final t in triggers) t.toJson()],
    'do': [for (final a in actions) a.toJson()],
  };

  static Automation? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final (id, name, ts, act) = (j['id'], j['name'], j['when'], j['do']);
    if (id is! int || name is! String) return null;
    if (ts is! List<Object?> || act is! List<Object?>) return null;
    final cool = j['cool'];
    return Automation(
      id: id,
      name: name,
      enabled: j['on'] != false,
      matchAll: j['all'] == true,
      cooldown: Duration(minutes: cool is int ? cool.clamp(1, 1440) : 5),
      triggers: [for (final t in ts) ?AutoTrigger.fromJson(t)],
      actions: [for (final a in act) ?AutoAction.fromJson(a)],
    );
  }
}

/// Every automation, and whether web requests may be made at all.
@immutable
class AutomationSettings {
  const AutomationSettings({this.rules = const [], this.webhooks = false});

  final List<Automation> rules;

  /// Web requests (webhooks) are off until the person allows them.
  final bool webhooks;

  int get nextId => rules.fold(0, (m, r) => r.id > m ? r.id : m) + 1;

  AutomationSettings copyWith({List<Automation>? rules, bool? webhooks}) =>
      AutomationSettings(
        rules: rules ?? this.rules,
        webhooks: webhooks ?? this.webhooks,
      );

  String encode() => jsonEncode({
    'webhooks': webhooks,
    'rules': [for (final r in rules) r.toJson()],
  });

  static AutomationSettings decode(String? saved) {
    if (saved == null) return const AutomationSettings();
    try {
      final j = jsonDecode(saved);
      if (j is! Map<String, Object?>) return const AutomationSettings();
      final rules = j['rules'];
      return AutomationSettings(
        webhooks: j['webhooks'] == true,
        rules: rules is List<Object?>
            ? [for (final r in rules) ?Automation.fromJson(r)]
            : const [],
      );
    } on FormatException {
      return const AutomationSettings();
    }
  }
}

// ------------------------------------------------------------------ engine

/// What a run of a rule is about, for filling in message text.
class AutoContext {
  const AutoContext({
    this.node,
    this.battery,
    this.place,
    this.text,
    required this.time,
  });

  final String? node;
  final int? battery;
  final String? place;
  final String? text;
  final DateTime time;

  AutoContext merge(AutoContext o) => AutoContext(
    node: node ?? o.node,
    battery: battery ?? o.battery,
    place: place ?? o.place,
    text: text ?? o.text,
    time: time,
  );

  String fill(String template, String rule) => template
      .replaceAll('{rule}', rule)
      .replaceAll('{node}', node ?? '')
      .replaceAll('{battery}', battery?.toString() ?? '')
      .replaceAll('{place}', place ?? '')
      .replaceAll('{text}', text ?? '')
      .replaceAll('{time}', TimeOfDayText.of(time));

  Map<String, Object?> toJson(String rule) => {
    'rule': rule,
    'time': time.toUtc().toIso8601String(),
    if (node != null) 'node': node,
    if (battery != null) 'battery': battery,
    if (place != null) 'place': place,
    if (text != null) 'text': text,
  };
}

/// The side effects an automation can have, supplied by the app.
class AutomationHooks {
  const AutomationHooks({
    required this.send,
    required this.alert,
    required this.playSound,
    required this.joinChannel,
    required this.post,
  });

  /// Sends a message; false when the radio isn't connected.
  final Future<bool> Function(Conversation, String) send;
  final Future<void> Function(String title, String body) alert;
  final Future<void> Function() playSound;
  final Future<bool> Function(RadioId radio, String link) joinChannel;

  /// Posts JSON to a web address and returns the HTTP status.
  final Future<int> Function(Uri url, String json) post;
}

/// One action that ran (or was skipped), for the activity log.
class AutoRun {
  const AutoRun(this.time, this.rule, this.action, this.ok, [this.note]);

  final DateTime time;
  final String rule;
  final AutoAction action;
  final bool ok;
  final String? note;
}

/// Runs automations: watches messages, nodes, places and the clock, and
/// runs a rule's actions when its triggers fire.
///
/// Limits keep it from running away: a rule runs at most once per its
/// cooldown, all rules together at most [maxPerHour] times an hour,
/// messages from other bots (`[auto]`), emergency messages and backlog
/// older than [maxAge] never trigger anything, and the first reading of
/// a battery, position or presence is only a baseline.
class AutomationEngine extends ChangeNotifier {
  AutomationEngine({
    required this.store,
    required this.hooks,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Preference the settings are saved under.
  static const prefName = 'automations';
  static const maxPerHour = 30;
  static const maxAge = Duration(minutes: 10);

  final MeshStore store;
  final AutomationHooks hooks;
  final DateTime Function() _now;

  AutomationSettings settings = const AutomationSettings();
  final List<AutoRun> log = [];

  final Map<String, Node> _nodes = {};
  Map<int, Place> _places = {};
  final Map<String, int> _battery = {};
  final Map<String, bool> _inside = {};
  final Map<String, bool> _present = {};
  final Map<int, DateTime> _lastRun = {};
  final Map<String, DateTime> _timeFired = {};
  final List<DateTime> _recent = [];

  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _tick;

  static String _id(RadioId r, NodeKey k) => '$r/$k';

  StreamSubscription<List<Place>>? _placeSub;
  StreamSubscription<List<Node>>? _nodeSub;

  /// Starts watching. Safe to call twice.
  ///
  /// Nodes and places are only watched while a rule needs them. Settings
  /// are read once here; the automations screen changes them through
  /// [save].
  void start() {
    if (_subs.isNotEmpty) return;
    _subs.add(store.incoming.listen((s) => unawaited(onMessage(s.message))));
    // Read once: every change goes through [save].
    unawaited(
      store.preference(prefName).then((v) {
        if (_subs.isEmpty) return;
        settings = AutomationSettings.decode(v);
        _watchWhatRulesNeed();
        notifyListeners();
      }, onError: (Object e) => debugPrint('Automations unreadable: $e')),
    );
    _tick = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(onTick()),
    );
  }

  void _watchWhatRulesNeed() {
    if (_subs.isEmpty) return;
    final triggers = [
      for (final r in settings.rules)
        if (r.enabled) ...r.triggers,
    ];
    final nodes = triggers.any(
      (t) =>
          t is BatteryTrigger || t is GeofenceTrigger || t is PresenceTrigger,
    );
    final places = triggers.any((t) => t is GeofenceTrigger);
    if (nodes) {
      _nodeSub ??= store.watchAllNodes().listen((n) => unawaited(onNodes(n)));
    } else {
      unawaited(_nodeSub?.cancel());
      _nodeSub = null;
    }
    if (places) {
      _placeSub ??= store.watchPlaces().listen(onPlaces);
    } else {
      unawaited(_placeSub?.cancel());
      _placeSub = null;
    }
  }

  /// Stops watching.
  void stop() {
    for (final s in [..._subs, ?_nodeSub, ?_placeSub]) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _nodeSub = _placeSub = null;
    _tick?.cancel();
    _tick = null;
  }

  /// Saves new settings (rules and the web-request switch).
  Future<void> save(AutomationSettings s) async {
    settings = s;
    _watchWhatRulesNeed();
    notifyListeners();
    await store.setPreference(prefName, s.encode());
  }

  void onPlaces(List<Place> places) {
    _places = {
      for (final p in places)
        if (p.kind == PlaceKind.geofence && p.radiusM != null) p.id: p,
    };
  }

  /// A message arrived.
  Future<void> onMessage(Message m) async {
    if (m.outgoing || m.isReaction) return;
    final t = m.text.trimLeft();
    if (t.startsWith(AutoResponder.marker.trim())) return;
    if (MecpMessage.tryParse(m.text) != null) return;
    final now = _now();
    if (now.difference(m.sentAt).abs() > maxAge) return;
    final ctx = AutoContext(
      node: m.senderName ?? m.from?.short,
      text: m.text,
      time: now,
    );
    await _evaluate(
      (t) => t is MessageTrigger && t.matches(m) ? ctx : null,
      now,
    );
  }

  /// Nodes changed: battery, positions and presence.
  Future<void> onNodes(List<Node> nodes) async {
    final now = _now();
    final fired = <AutoTrigger, AutoContext>{};
    for (final n in nodes) {
      _nodes[_id(n.radioId, n.key)] = n;
    }
    for (final r in settings.rules) {
      if (!r.enabled) continue;
      for (final t in r.triggers) {
        switch (t) {
          case BatteryTrigger(:final radio, :final node, :final below):
            final id = _id(radio, node);
            final n = _nodes[id];
            final b = n?.batteryPercent;
            if (b == null) continue;
            final key = '${r.id}|$id';
            final was = _battery[key];
            _battery[key] = b;
            if (was != null && was >= below && b < below) {
              fired[t] = AutoContext(
                node: n!.displayName,
                battery: b,
                time: now,
              );
            }
          case GeofenceTrigger(:final place, :final enter):
            final fence = _places[place];
            if (fence == null) continue;
            for (final n in nodes) {
              if (!t.watches(n) || n.position == null) continue;
              final key = '${r.id}|$place|${_id(n.radioId, n.key)}';
              final was = _inside[key];
              final metres =
                  haversineKm(fence.points.first, n.position!) * 1000;
              final radius = fence.radiusM!;
              final inside = was == true
                  ? metres <= radius * 1.1
                  : metres <= radius;
              _inside[key] = inside;
              if (was != null && was != inside && inside == enter) {
                fired[t] = AutoContext(
                  node: n.displayName,
                  place: fence.name,
                  time: now,
                );
              }
            }
          case PresenceTrigger(:final online):
            if (!online) continue; // going quiet is noticed by the clock
            final ctx = _presence(r, t, now);
            if (ctx != null) fired[t] = ctx;
          default:
            break;
        }
      }
    }
    await _evaluate((t) => fired[t], now);
  }

  /// Checks the clock: times of day and nodes going quiet.
  Future<void> onTick() async {
    final now = _now();
    final fired = <AutoTrigger, AutoContext>{};
    for (final r in settings.rules) {
      if (!r.enabled) continue;
      for (final t in r.triggers) {
        switch (t) {
          case TimeTrigger():
            if (!t.matches(now)) continue;
            final key = '${r.id}|${t.hour}:${t.minute}';
            final last = _timeFired[key];
            if (last != null &&
                now.difference(last) < const Duration(minutes: 2)) {
              continue;
            }
            _timeFired[key] = now;
            fired[t] = AutoContext(time: now);
          case PresenceTrigger():
            // Coming back is usually seen when the node updates; the clock
            // notices nodes going quiet (and keeps both up to date).
            final ctx = _presence(r, t, now);
            if (ctx != null) fired[t] = ctx;
          default:
            break;
        }
      }
    }
    await _evaluate((t) => fired[t], now);
  }

  /// Notes whether [t]'s node is present and returns a context when that
  /// changed the way [t] waits for.
  AutoContext? _presence(Automation r, PresenceTrigger t, DateTime now) {
    final id = _id(t.radio, t.node);
    final n = _nodes[id];
    final heard = n?.lastHeard;
    if (heard == null) return null;
    final present = now.difference(heard) < t.after;
    final key = '${r.id}|${t.online}|$id';
    final was = _present[key];
    _present[key] = present;
    if (was == null || was == present || present != t.online) return null;
    return AutoContext(node: n!.displayName, time: now);
  }

  /// Whether [t] holds right now (for rules that need every trigger).
  bool _holds(AutoTrigger t, DateTime now) {
    switch (t) {
      case BatteryTrigger(:final radio, :final node, :final below):
        final b = _nodes[_id(radio, node)]?.batteryPercent;
        return b != null && b < below;
      case TimeTrigger():
        return t.matches(now);
      case GeofenceTrigger(:final place, :final enter):
        final fence = _places[place];
        if (fence == null) return false;
        return _nodes.values.any((n) {
          if (!t.watches(n) || n.position == null) return false;
          final metres = haversineKm(fence.points.first, n.position!) * 1000;
          return (metres <= fence.radiusM!) == enter;
        });
      case MessageTrigger():
        return false;
      case PresenceTrigger(
        :final radio,
        :final node,
        :final online,
        :final after,
      ):
        final heard = _nodes[_id(radio, node)]?.lastHeard;
        if (heard == null) return false;
        return (now.difference(heard) < after) == online;
    }
  }

  Future<void> _evaluate(
    AutoContext? Function(AutoTrigger) firedBy,
    DateTime now,
  ) async {
    for (final r in settings.rules) {
      if (!r.enabled || r.triggers.isEmpty || r.actions.isEmpty) continue;
      AutoContext? ctx;
      for (final t in r.triggers) {
        final c = firedBy(t);
        if (c != null) ctx = ctx == null ? c : ctx.merge(c);
      }
      if (ctx == null) continue;
      if (r.matchAll &&
          !r.triggers.every((t) => firedBy(t) != null || _holds(t, now))) {
        continue;
      }
      final last = _lastRun[r.id];
      if (last != null && now.difference(last) < r.cooldown) continue;
      _recent.removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
      if (_recent.length >= maxPerHour) continue;
      _lastRun[r.id] = now;
      _recent.add(now);
      await run(r, ctx);
    }
  }

  /// Runs [rule]'s actions with [ctx]; each one's failure is logged and
  /// doesn't stop the rest.
  Future<void> run(Automation rule, AutoContext ctx) async {
    for (final a in rule.actions) {
      var ok = true;
      String? note;
      try {
        switch (a) {
          case SendAction(:final conversation, :final text):
            ok = await hooks.send(conversation, ctx.fill(text, rule.name));
            if (!ok) note = 'radio not connected';
          case AlertAction(:final text):
            await hooks.alert(rule.name, ctx.fill(text, rule.name));
          case SoundAction():
            await hooks.playSound();
          case JoinChannelAction(:final radio, :final link):
            ok = await hooks.joinChannel(radio, link);
            if (!ok) note = 'radio not connected';
          case WebhookAction(:final url):
            if (!settings.webhooks) {
              ok = false;
              note = 'web requests are off';
            } else {
              final status = await hooks.post(
                Uri.parse(url.trim()),
                jsonEncode(ctx.toJson(rule.name)),
              );
              ok = status >= 200 && status < 300;
              if (!ok) note = 'HTTP $status';
            }
        }
      } on Object catch (e) {
        ok = false;
        note = '$e';
      }
      log.insert(0, AutoRun(ctx.time, rule.name, a, ok, note));
      if (log.length > 100) log.removeLast();
    }
    notifyListeners();
  }
}
