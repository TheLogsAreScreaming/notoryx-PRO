import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mesh/model.dart';
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';

/// Why a message was not forwarded.
enum BridgeHold {
  /// It was too old: a backlog arriving after a reconnect, or a sender
  /// whose clock is wrong.
  tooOld,

  /// The same text just went across.
  repeated,

  /// The link had used up its share of airtime.
  tooFast,

  /// The radio on the other side isn't connected.
  offline,
}

/// One opt-in link between a MeshCore and a Meshtastic conversation.
@immutable
class BridgeLink {
  const BridgeLink({
    required this.a,
    required this.b,
    required this.aLabel,
    required this.bLabel,
    this.enabled = false,
  });

  final Conversation a;
  final Conversation b;

  /// Names to show for each side; saved so a radio that isn't connected
  /// can still be listed.
  final String aLabel;
  final String bLabel;
  final bool enabled;

  String get id => '${a.key}<>${b.key}';

  /// Whether this links two people rather than two channels.
  bool get isDirect => a is DirectConversation;

  /// The side opposite [from]; null if this link doesn't include it.
  Conversation? other(Conversation from) => from == a
      ? b
      : from == b
      ? a
      : null;

  BridgeLink withEnabled(bool on) =>
      BridgeLink(a: a, b: b, aLabel: aLabel, bLabel: bLabel, enabled: on);

  Map<String, Object?> toJson() => {
    'a': a.key,
    'b': b.key,
    'aLabel': aLabel,
    'bLabel': bLabel,
    'enabled': enabled,
  };

  /// Null if [j] doesn't describe a valid link.
  static BridgeLink? tryParse(Map<String, dynamic> j) {
    final a = Conversation.tryParse(j['a'] as String? ?? '');
    final b = Conversation.tryParse(j['b'] as String? ?? '');
    if (a == null || b == null || !isAllowed(a, b)) return null;
    return BridgeLink(
      a: a,
      b: b,
      aLabel: j['aLabel'] as String? ?? '',
      bLabel: j['bLabel'] as String? ?? '',
      enabled: j['enabled'] as bool? ?? false,
    );
  }

  /// A link must cross between the meshes and pair like with like, so a
  /// direct message can never end up on a channel.
  static bool isAllowed(Conversation a, Conversation b) =>
      a.radioId.protocol != b.radioId.protocol &&
      (a is DirectConversation) == (b is DirectConversation);
}

/// What a link has done since the app started.
class BridgeStats {
  int forwarded = 0;
  int held = 0;
  BridgeHold? lastHold;
}

/// Sends [text] to [to]; false if its radio isn't connected.
typedef BridgeSend = Future<bool> Function(Conversation to, String text);

/// Forwards messages across [BridgeLink]s.
///
/// Three things stop loops and floods: only messages received from the air
/// are considered, so what the bridge itself sends can't come back around;
/// anything already carrying a bridge label is never forwarded, which
/// covers a second bridge on the same channels; and each direction of a
/// link is limited to [maxPerWindow] messages per [window].
class ChannelBridge extends ChangeNotifier {
  ChannelBridge(this.store, {required this.send, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  static const _preference = 'bridge.links';

  /// Most messages one direction of a link may send per [window].
  static const maxPerWindow = 5;
  static const window = Duration(minutes: 1);

  /// How long the same text is treated as a repeat.
  static const repeatWindow = Duration(seconds: 30);

  /// Older messages are a backlog, not a conversation.
  static const maxAge = Duration(minutes: 10);

  /// Bytes a forwarded message may take on each mesh. MeshCore's is lower
  /// because the radio adds its own name to channel posts.
  static int maxBytes(RadioProtocol to) =>
      to == RadioProtocol.meshcore ? 130 : 200;

  static final _label = RegExp(r'^(?:[^:\n]{1,32}: )?\[(?:MC|MT) ');

  /// Whether [text] was already forwarded by a bridge.
  static bool isBridged(String text) => _label.hasMatch(text);

  /// The text sent across: `[MC Ann] hello`, cut to fit [maxLength] bytes.
  static String compose(
    RadioProtocol source,
    String sender,
    String text,
    int maxLength,
  ) {
    final tag = source == RadioProtocol.meshcore ? 'MC' : 'MT';
    final clean = sender.replaceAll(RegExp(r'[\[\]\n\r]'), '').trim();
    final name = clean.first16;
    final whole = '[$tag ${name.isEmpty ? '?' : name}] ${text.trim()}';
    if (utf8.encode(whole).length <= maxLength) return whole;
    const more = '…';
    final room = maxLength - utf8.encode(more).length;
    final out = StringBuffer();
    var used = 0;
    for (final r in whole.runes) {
      final c = String.fromCharCode(r);
      used += utf8.encode(c).length;
      if (used > room) break;
      out.write(c);
    }
    return '${out.toString().trimRight()}$more';
  }

  final MeshStore store;
  final BridgeSend send;
  final DateTime Function() _now;

  List<BridgeLink> _links = const [];
  final Map<String, BridgeStats> _stats = {};
  final Map<String, List<DateTime>> _sent = {};
  final Map<String, DateTime> _recent = {};
  StreamSubscription<StoredMessage>? _sub;
  Future<void>? _loading;
  Future<void> _tail = Future<void>.value();

  /// Completes when every message heard so far has been dealt with.
  @visibleForTesting
  Future<void> get idle => _tail;

  List<BridgeLink> get links => List.unmodifiable(_links);

  BridgeStats statsFor(BridgeLink link) =>
      _stats.putIfAbsent(link.id, BridgeStats.new);

  /// Reads the saved links and starts listening.
  Future<void> load() {
    _sub ??= store.incoming.listen((m) {
      _tail = _tail.then((_) => _handle(m)).catchError((Object _) {});
    });
    return _loading ??= _read();
  }

  Future<void> _read() async {
    final text = await store.preference(_preference);
    if (text == null) return;
    try {
      _links = [
        for (final j in jsonDecode(text) as List<dynamic>)
          ?BridgeLink.tryParse(j as Map<String, dynamic>),
      ];
    } on FormatException {
      _links = const [];
    } on TypeError {
      _links = const [];
    }
    notifyListeners();
  }

  /// Stops forwarding and waits for anything under way.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _tail;
  }

  Future<void> _save() => store.setPreference(
    _preference,
    jsonEncode([for (final l in _links) l.toJson()]),
  );

  /// Adds [link], switched off. False if those two are already linked.
  Future<bool> add(BridgeLink link) async {
    if (!BridgeLink.isAllowed(link.a, link.b)) {
      throw ArgumentError('A bridge must join the two meshes, like with like');
    }
    if (_links.any((l) => l.other(link.a) == link.b)) return false;
    _links = [..._links, link.withEnabled(false)];
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> setEnabled(BridgeLink link, bool on) async {
    _links = [
      for (final l in _links)
        if (l.id == link.id) l.withEnabled(on) else l,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> remove(BridgeLink link) async {
    _links = [
      for (final l in _links)
        if (l.id != link.id) l,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> _handle(StoredMessage stored) async {
    final m = stored.message;
    if (m.outgoing || m.isReaction || m.text.trim().isEmpty) return;
    if (isBridged(m.text)) return;
    for (final link in _links) {
      if (!link.enabled) continue;
      final to = link.other(m.conversation);
      if (to != null) await _forward(link, m, to);
    }
  }

  Future<void> _forward(BridgeLink link, Message m, Conversation to) async {
    final hold = _holdFor(link, m, to);
    final stats = statsFor(link);
    if (hold != null) return _held(stats, hold);
    final text = compose(
      m.protocol,
      await _senderOf(m),
      m.text,
      maxBytes(to.radioId.protocol),
    );
    final bool ok;
    try {
      ok = await send(to, text);
    } on StateError {
      return _held(stats, BridgeHold.offline);
    }
    if (!ok) return _held(stats, BridgeHold.offline);
    stats.forwarded++;
    notifyListeners();
  }

  void _held(BridgeStats stats, BridgeHold why) {
    stats.held++;
    stats.lastHold = why;
    notifyListeners();
  }

  BridgeHold? _holdFor(BridgeLink link, Message m, Conversation to) {
    final now = _now();
    if (now.difference(m.sentAt) > maxAge) return BridgeHold.tooOld;

    _recent.removeWhere((_, at) => now.difference(at) >= repeatWindow);
    final repeatKey = '${link.id}|${m.conversation.key}|${m.text.trim()}';
    if (_recent.containsKey(repeatKey)) return BridgeHold.repeated;
    _recent[repeatKey] = now;

    final times = _sent.putIfAbsent('${link.id}>${to.key}', () => [])
      ..removeWhere((at) => now.difference(at) >= window);
    if (times.length >= maxPerWindow) return BridgeHold.tooFast;
    times.add(now);
    return null;
  }

  Future<String> _senderOf(Message m) async {
    final name = m.senderName;
    if (name != null && name.isNotEmpty) return name;
    final from = m.from;
    if (from == null) return '';
    final node = await store.node(m.radioId, from);
    return node?.displayName ?? from.short;
  }
}

extension on String {
  /// At most 16 UTF-16 units, never splitting a character pair.
  String get first16 {
    final out = StringBuffer();
    for (final r in runes) {
      final c = String.fromCharCode(r);
      if (out.length + c.length > 16) break;
      out.write(c);
    }
    return out.toString();
  }
}
