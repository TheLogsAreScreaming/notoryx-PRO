import 'package:latlong2/latlong.dart';

import 'model.dart';

/// Farther than this from the previous point on a route, a repeater can't
/// have been the next hop.
const hopRangeMetres = 150000.0;

/// How short repeater IDs in MeshCore routes get names: a remembered pick
/// for IDs several known repeaters share, and names found online for IDs
/// no radio knows.
class HopNaming {
  HopNaming({
    this.online = false,
    this.server = defaultServer,
    this.tieDays = defaultTieDays,
    this.tieMargin = defaultTieMargin,
    Map<String, ({String key, int at})>? ties,
    Map<String, String>? found,
  }) : ties = ties ?? {},
       found = found ?? {};

  static const prefName = 'hop_naming';
  static const defaultServer = 'https://analyzer.on8ar.eu';
  static const defaultTieDays = 30;
  static const maxTieDays = 180;
  static const defaultTieMargin = 5;
  static const maxTieMargin = 20;

  /// Whether unknown IDs are looked up online.
  final bool online;

  /// The lookup server (https).
  final String server;

  /// How long a remembered pick lasts without being used again.
  final int tieDays;

  /// How close (in %) two repeaters' distances must be for the remembered
  /// pick to decide; 0 means only exact ties.
  final int tieMargin;

  /// Remembered picks: ID (lower-case hex) → full key and when last used
  /// (ms since epoch). Changed in place while resolving routes.
  final Map<String, ({String key, int at})> ties;

  /// Names found online by ID (lower-case hex).
  final Map<String, String> found;

  HopNaming copyWith({
    bool? online,
    String? server,
    int? tieDays,
    int? tieMargin,
    bool forgetPicks = false,
    bool forgetFound = false,
  }) => HopNaming(
    online: online ?? this.online,
    server: server ?? this.server,
    tieDays: (tieDays ?? this.tieDays).clamp(1, maxTieDays),
    tieMargin: (tieMargin ?? this.tieMargin).clamp(0, maxTieMargin),
    ties: forgetPicks ? {} : ties,
    found: forgetFound ? {} : found,
  );

  /// Whether [other] metres is close enough to [nearest] to count as a tie.
  bool isTie(double nearest, double other) =>
      other - nearest <= nearest * tieMargin / 100;

  /// The key remembered for [id] at [now], or null.
  String? pickFor(String id, DateTime now) {
    final t = ties[id.toLowerCase()];
    if (t == null) return null;
    final age = now.millisecondsSinceEpoch - t.at;
    return age > Duration(days: tieDays).inMilliseconds ? null : t.key;
  }

  /// Whether a pick was made or refreshed since this was last saved.
  bool unsaved = false;

  void remember(String id, String key, DateTime now) {
    final old = ties[id.toLowerCase()];
    if (old != null &&
        old.key == key &&
        now.millisecondsSinceEpoch - old.at < Duration.millisecondsPerHour) {
      return;
    }
    ties[id.toLowerCase()] = (key: key, at: now.millisecondsSinceEpoch);
    unsaved = true;
  }

  int pickCount(DateTime now) =>
      ties.keys.where((id) => pickFor(id, now) != null).length;

  Map<String, Object?> toJson(DateTime now) => {
    'online': online,
    'server': server,
    'tieDays': tieDays,
    'tieMargin': tieMargin,
    'ties': {
      for (final MapEntry(:key, :value) in ties.entries)
        if (pickFor(key, now) != null) key: [value.key, value.at],
    },
  };

  static HopNaming fromJson(Object? json) {
    if (json is! Map<String, Object?>) return HopNaming();
    final ties = <String, ({String key, int at})>{};
    if (json['ties'] case final Map<String, Object?> raw) {
      for (final MapEntry(:key, :value) in raw.entries) {
        if (value case [final String k, final int at]) {
          ties[key] = (key: k, at: at);
        }
      }
    }
    final server = json['server'];
    return HopNaming(
      online: json['online'] == true,
      server: server is String && server.startsWith('https://')
          ? server
          : defaultServer,
      tieDays: ((json['tieDays'] as num?)?.toInt() ?? defaultTieDays).clamp(
        1,
        maxTieDays,
      ),
      tieMargin: ((json['tieMargin'] as num?)?.toInt() ?? defaultTieMargin)
          .clamp(0, maxTieMargin),
      ties: ties,
    );
  }

  /// Picks among [matches] for [id] seen right after [from]: the nearest
  /// one in range (remembered), the remembered one when they're about
  /// equally close or nothing is located, else null.
  Node? choose(String id, List<Node> matches, GeoPoint? from, DateTime now) {
    final remembered = pickFor(id, now);
    Node? byKey(String? key) =>
        matches.where((n) => n.key.native == key).firstOrNull;
    final measured = <(Node, double)>[
      if (from != null)
        for (final n in matches)
          if (n.position case final p?) (n, metresBetween(from, p)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final inRange = [
      for (final m in measured)
        if (m.$2 <= hopRangeMetres) m,
    ];
    Node? picked;
    if (inRange.isNotEmpty) {
      final close = [
        for (final m in inRange)
          if (isTie(inRange.first.$2, m.$2)) m.$1,
      ];
      final mine = byKey(remembered);
      picked = close.length > 1 && mine != null && close.contains(mine)
          ? mine
          : inRange.first.$1;
    } else if (measured.isEmpty) {
      picked = byKey(remembered);
    }
    if (picked != null) remember(id, picked.key.native, now);
    return picked;
  }
}

double metresBetween(GeoPoint a, GeoPoint b) => const Distance()(
  LatLng(a.latitude, a.longitude),
  LatLng(b.latitude, b.longitude),
);

/// The name a lookup [reply] gives for [id]: the nearest candidate within
/// range of [you], or, without a position, only an unambiguous answer.
String? onlineHopName(Object? reply, String id, {GeoPoint? you}) {
  if (reply case {'resolved': final Map<String, Object?> resolved}) {
    final entry = resolved[id.toUpperCase()];
    if (entry is! Map<String, Object?>) return null;
    if (you != null) {
      String? best;
      var bestMetres = double.infinity;
      for (final c in entry['candidates'] as List<Object?>? ?? const []) {
        if (c case {
          'name': final String name,
          'lat': final num lat,
          'lon': final num lon,
        } when name.trim().isNotEmpty) {
          final m = metresBetween(
            you,
            GeoPoint(lat.toDouble(), lon.toDouble()),
          );
          if (m <= hopRangeMetres && m < bestMetres) {
            best = name.trim();
            bestMetres = m;
          }
        }
      }
      return best;
    }
    if (entry['ambiguous'] == true) return null;
    if (entry['name'] case final String name when name.trim().isNotEmpty) {
      return name.trim();
    }
  }
  return null;
}
