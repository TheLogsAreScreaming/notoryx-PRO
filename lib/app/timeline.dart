import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mesh/mesh.dart';
import '../mesh/places.dart';
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';

/// What happened, on the timeline.
enum TimelineKind {
  /// A message, sent or received.
  message,

  /// A node was heard for the first time.
  nodeJoined,

  /// A node's signal moved by at least one bar.
  signalChanged,

  /// A waypoint, route or geofence was added.
  waypoint,
}

/// One entry on the timeline.
@immutable
class TimelineEvent {
  const TimelineEvent({
    required this.kind,
    required this.time,
    required this.title,
    this.protocol,
    this.radio,
    this.node,
    this.barsBefore,
    this.barsAfter,
    this.snr,
    this.placeKind,
    this.message,
  });

  final TimelineKind kind;
  final DateTime time;

  /// Node name, place name or message sender.
  final String title;
  final RadioProtocol? protocol;
  final RadioId? radio;
  final NodeKey? node;

  /// Signal bars before and after a change (0–4).
  final int? barsBefore;
  final int? barsAfter;

  /// SNR in dB after a signal change.
  final double? snr;
  final PlaceKind? placeKind;

  /// The message, for [TimelineKind.message].
  final StoredMessage? message;

  Map<String, Object?> toJson() => {
    'k': kind.name,
    't': time.millisecondsSinceEpoch,
    'n': title,
    if (protocol != null) 'p': protocol!.name,
    if (radio != null) 'r': radio.toString(),
    if (node != null) 'node': node.toString(),
    if (barsBefore != null) 'b0': barsBefore,
    if (barsAfter != null) 'b1': barsAfter,
    if (snr != null) 'snr': snr,
    if (placeKind != null) 'pk': placeKind!.name,
  };

  static TimelineEvent? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final kind = TimelineKind.values.asNameMap()[j['k']];
    final t = j['t'];
    final title = j['n'];
    if (kind == null || kind == TimelineKind.message) return null;
    if (t is! int || title is! String) return null;
    return TimelineEvent(
      kind: kind,
      time: DateTime.fromMillisecondsSinceEpoch(t),
      title: title,
      protocol: RadioProtocol.values.asNameMap()[j['p']],
      radio: switch (j['r']) {
        final String r => RadioId.tryParse(r),
        _ => null,
      },
      node: switch (j['node']) {
        final String n => NodeKey.tryParse(n),
        _ => null,
      },
      barsBefore: j['b0'] as int?,
      barsAfter: j['b1'] as int?,
      snr: (j['snr'] as num?)?.toDouble(),
      placeKind: PlaceKind.values.asNameMap()[j['pk']],
    );
  }
}

/// The events [after] brings compared with [before] (nodes by radio and
/// key): nodes never stored before, and signal moving by a bar or more.
///
/// A node's signal change is skipped when [lastSignal] says one was
/// recorded less than [signalGap] ago, so a flapping link doesn't flood
/// the timeline; [lastSignal] is updated.
List<TimelineEvent> nodeEvents(
  Map<String, Node> before,
  Iterable<Node> after, {
  required DateTime now,
  required Map<String, DateTime> lastSignal,
  Duration signalGap = const Duration(minutes: 15),
}) {
  final out = <TimelineEvent>[];
  for (final n in after) {
    final id = '${n.radioId}/${n.key}';
    final old = before[id];
    if (old == null) {
      out.add(
        TimelineEvent(
          kind: TimelineKind.nodeJoined,
          time: n.lastHeard ?? now,
          title: n.displayName,
          protocol: n.protocol,
          radio: n.radioId,
          node: n.key,
          snr: n.path.snr,
        ),
      );
      continue;
    }
    final b0 = signalBars(old.path);
    final b1 = signalBars(n.path);
    if (b0 == null || b1 == null || b0 == b1) continue;
    final last = lastSignal[id];
    if (last != null && now.difference(last) < signalGap) continue;
    lastSignal[id] = now;
    out.add(
      TimelineEvent(
        kind: TimelineKind.signalChanged,
        time: n.lastHeard ?? now,
        title: n.displayName,
        protocol: n.protocol,
        radio: n.radioId,
        node: n.key,
        barsBefore: b0,
        barsAfter: b1,
        snr: n.path.snr,
      ),
    );
  }
  return out;
}

/// Places in [after] whose ID isn't in [before].
List<TimelineEvent> placeEvents(
  Set<int> before,
  Iterable<Place> after, {
  required DateTime now,
}) => [
  for (final p in after)
    if (!before.contains(p.id))
      TimelineEvent(
        kind: TimelineKind.waypoint,
        time: now,
        title: p.name,
        placeKind: p.kind,
      ),
];

/// Watches the store and keeps a log of new nodes, signal changes and new
/// places for the timeline; messages are read straight from the store.
///
/// What is in the store when it starts is the baseline: only changes after
/// that are recorded. The log keeps the newest [capacity] events.
class TimelineRecorder extends ChangeNotifier {
  TimelineRecorder(
    this.store, {
    this.capacity = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Preference the log is saved under.
  static const prefName = 'timeline.events';

  final MeshStore store;
  final int capacity;
  final DateTime Function() _clock;

  final List<TimelineEvent> _events = [];
  Map<String, Node>? _nodes;
  Set<int>? _places;
  final Map<String, DateTime> _lastSignal = {};
  StreamSubscription<List<Node>>? _nodeSub;
  StreamSubscription<List<Place>>? _placeSub;
  Timer? _save;
  bool _started = false;
  int _run = 0;

  /// Recorded events, newest first.
  List<TimelineEvent> get events => List.unmodifiable(_events);

  /// Loads the saved log and starts watching. Safe to call twice.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final run = ++_run;
    try {
      final saved = await store.preference(prefName);
      if (saved != null) {
        final list = jsonDecode(saved);
        if (list is List<Object?>) {
          _events
            ..clear()
            ..addAll([for (final e in list) ?TimelineEvent.fromJson(e)]);
        }
      }
    } on Object catch (e) {
      debugPrint('Timeline log unreadable, starting a new one: $e');
    }
    // Stopped while loading: don't start watching a store that may be
    // closing.
    if (run != _run || !_started) return;
    notifyListeners();
    _nodeSub = store.watchAllNodes().listen(_onNodes);
    _placeSub = store.watchPlaces().listen(_onPlaces);
  }

  void _onNodes(List<Node> nodes) {
    final now = _clock();
    final map = {for (final n in nodes) '${n.radioId}/${n.key}': n};
    final before = _nodes;
    _nodes = map;
    if (before == null) return;
    _add(nodeEvents(before, nodes, now: now, lastSignal: _lastSignal));
  }

  void _onPlaces(List<Place> places) {
    final ids = {for (final p in places) p.id};
    final before = _places;
    _places = ids;
    if (before == null) return;
    _add(placeEvents(before, places, now: _clock()));
  }

  void _add(List<TimelineEvent> fresh) {
    if (fresh.isEmpty) return;
    _events
      ..insertAll(0, fresh)
      ..sort((a, b) => b.time.compareTo(a.time));
    if (_events.length > capacity) {
      _events.removeRange(capacity, _events.length);
    }
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  /// Writes the log now.
  Future<void> flush() async {
    _save?.cancel();
    _save = null;
    try {
      await store.setPreference(
        prefName,
        jsonEncode([for (final e in _events) e.toJson()]),
      );
    } on Object catch (e) {
      debugPrint('Could not save the timeline: $e');
    }
  }

  /// Forgets every recorded event (messages stay).
  Future<void> clear() async {
    _events.clear();
    notifyListeners();
    await flush();
  }

  /// Stops watching and saves what is pending.
  Future<void> stop() async {
    final pending = _save != null;
    // Not awaited, like the other watchers: drift finishes a cancel on its
    // own timer, which nothing needs to wait for.
    unawaited(_nodeSub?.cancel());
    unawaited(_placeSub?.cancel());
    _nodeSub = _placeSub = null;
    _started = false;
    _run++;
    if (pending) await flush();
  }
}

/// Recorded events and [messages] in one list, newest first, keeping only
/// the [kinds] asked for.
List<TimelineEvent> mergeTimeline(
  List<TimelineEvent> recorded,
  List<StoredMessage> messages,
  Set<TimelineKind> kinds,
) {
  final all = [
    if (kinds.contains(TimelineKind.message))
      for (final m in messages)
        TimelineEvent(
          kind: TimelineKind.message,
          time: m.message.receivedAt,
          title: m.message.senderName ?? m.message.from?.short ?? '',
          protocol: m.message.protocol,
          radio: m.message.conversation.radioId,
          message: m,
        ),
    for (final e in recorded)
      if (kinds.contains(e.kind)) e,
  ];
  all.sort((a, b) => b.time.compareTo(a.time));
  return all;
}
