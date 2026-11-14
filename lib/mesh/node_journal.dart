/// The node journal: every node ever heard, what it seems to be from how
/// it behaves, and the notes you keep on it.
///
/// The store keeps one [JournalEntry] per node and one [JournalDay] per
/// node per local day heard. [describeNode] turns those into
/// [JournalLabel]s, each with a confidence and the evidence behind it, so
/// the app never states a guess without saying why.
library;

import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'diagnostics.dart' show haversineKm;
import 'model.dart';

/// One node in the journal, across all your radios.
@immutable
class JournalEntry {
  const JournalEntry({
    required this.key,
    required this.name,
    required this.firstHeard,
    required this.lastHeard,
    this.kind = NodeKind.unknown,
    this.heardCount = 1,
    this.tags = const [],
    this.note = '',
    this.position,
  });

  final NodeKey key;

  /// The newest name heard, or empty.
  final String name;
  final NodeKind kind;
  final DateTime firstHeard;
  final DateTime lastHeard;

  /// How many separate times it was heard (each newer report counts once).
  final int heardCount;

  /// Your tags, sorted, without duplicates.
  final List<String> tags;

  /// Your note.
  final String note;

  /// The last position heard, if any.
  final GeoPoint? position;

  String get displayName => name.isNotEmpty ? name : key.short;
}

/// What the journal saw of one node on one local day.
@immutable
class JournalDay {
  const JournalDay({
    required this.key,
    required this.day,
    this.hoursMask = 0,
    this.reports = 0,
    this.direct = 0,
    this.hopsKnown = 0,
    this.minLat,
    this.maxLat,
    this.minLon,
    this.maxLon,
  });

  final NodeKey key;

  /// Local midnight of the day.
  final DateTime day;

  /// Bit n set when the node was heard during hour n (0–23).
  final int hoursMask;

  /// Reports that day.
  final int reports;

  /// Reports heard with no hops in between.
  final int direct;

  /// Reports whose hop count was known.
  final int hopsKnown;

  /// Bounding box of the positions heard that day, if any.
  final double? minLat;
  final double? maxLat;
  final double? minLon;
  final double? maxLon;

  bool get hasPosition => minLat != null;

  /// This day with one more report at [time] folded in.
  JournalDay add(DateTime time, {int? hops, GeoPoint? position}) {
    final p = position;
    return JournalDay(
      key: key,
      day: day,
      hoursMask: hoursMask | (1 << time.hour),
      reports: reports + 1,
      direct: direct + (hops == 0 ? 1 : 0),
      hopsKnown: hopsKnown + (hops == null ? 0 : 1),
      minLat: _min(minLat, p?.latitude),
      maxLat: _max(maxLat, p?.latitude),
      minLon: _min(minLon, p?.longitude),
      maxLon: _max(maxLon, p?.longitude),
    );
  }
}

double? _min(double? a, double? b) =>
    a == null ? b : (b == null ? a : math.min(a, b));
double? _max(double? a, double? b) =>
    a == null ? b : (b == null ? a : math.max(a, b));

/// Local midnight of [t].
DateTime journalDayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// What a node seems to be.
enum JournalLabel {
  /// Heard around the clock, day after day: a repeater or router left on.
  alwaysOnRelay,

  /// Heard in places kilometres apart.
  roamer,

  /// Always reports the same spot.
  fixedSite,

  /// Heard on most days.
  regular,

  /// Heard on few of the days since it first appeared.
  rarelyHeard,

  /// First heard in the last two days. Never more than 60% sure, since
  /// it says nothing about how the node behaves.
  newArrival,

  /// Usually heard directly, with no repeater in between.
  nearby,
}

/// One fact behind a label.
enum EvidenceKind {
  /// [JournalEvidence.value] distinct hours of the day out of 24.
  hoursCovered,

  /// Heard on [JournalEvidence.value] of the last [JournalEvidence.of] days.
  daysHeard,

  /// The node says it is a repeater or router.
  relayRole,

  /// Positions spread over [JournalEvidence.value] km.
  areaKm,

  /// Positions on [JournalEvidence.value] days, all within 200 m.
  samePlace,

  /// [JournalEvidence.value]% of [JournalEvidence.of] reports were direct.
  directShare,

  /// First heard [JournalEvidence.value] hours ago.
  firstHeardHours,
}

@immutable
class JournalEvidence {
  const JournalEvidence(this.kind, [this.value = 0, this.of = 0]);

  final EvidenceKind kind;
  final num value;
  final num of;

  @override
  bool operator ==(Object other) =>
      other is JournalEvidence &&
      other.kind == kind &&
      other.value == value &&
      other.of == of;

  @override
  int get hashCode => Object.hash(kind, value, of);

  @override
  String toString() => '$kind($value/$of)';
}

/// A label with how sure the journal is (0–1) and why.
@immutable
class LabelGuess {
  const LabelGuess(this.label, this.confidence, this.evidence);

  final JournalLabel label;
  final double confidence;
  final List<JournalEvidence> evidence;

  /// Confidence as a whole percentage.
  int get percent => (confidence * 100).round();

  @override
  String toString() => '$label $percent% $evidence';
}

/// How many days of history the labels look at.
const journalWindowDays = 30;

/// Labels for a node from its [entry] and the [days] it was heard, most
/// confident first. Only labels at least 50% sure are returned.
///
/// Pure and deterministic: the same history and [now] always give the same
/// labels.
List<LabelGuess> describeNode(
  JournalEntry entry,
  List<JournalDay> days, {
  required DateTime now,
}) {
  final today = journalDayOf(now);
  final firstDay = journalDayOf(entry.firstHeard);
  final span = today.difference(firstDay).inDays + 1;
  final window = math.max(1, math.min(span, journalWindowDays));
  final since = today.subtract(Duration(days: window - 1));
  final recent = [
    for (final d in days)
      if (!d.day.isBefore(since) && !d.day.isAfter(today)) d,
  ];
  final daysHeard = recent.length;
  final dayShare = daysHeard / window;
  var mask = 0;
  var direct = 0;
  var hopsKnown = 0;
  double? minLat, maxLat, minLon, maxLon;
  var positionDays = 0;
  for (final d in recent) {
    mask |= d.hoursMask;
    direct += d.direct;
    hopsKnown += d.hopsKnown;
    if (d.hasPosition) {
      positionDays++;
      minLat = _min(minLat, d.minLat);
      maxLat = _max(maxLat, d.maxLat);
      minLon = _min(minLon, d.minLon);
      maxLon = _max(maxLon, d.maxLon);
    }
  }
  final hours = _bits(mask);
  final areaKm = minLat == null
      ? 0.0
      : haversineKm(GeoPoint(minLat, minLon!), GeoPoint(maxLat!, maxLon!));
  final daysEvidence = JournalEvidence(
    EvidenceKind.daysHeard,
    daysHeard,
    window,
  );
  final out = <LabelGuess>[];

  // Always-on relay: heard at most hours, on most days.
  final relay = entry.kind == NodeKind.relay;
  if (window >= 2 && daysHeard >= 2 && (hours >= 16 || relay)) {
    var c = 0.5 * math.min(1, hours / 20) + 0.45 * dayShare;
    if (relay) c += 0.15;
    if (window < 7) c *= 0.8;
    out.add(
      LabelGuess(JournalLabel.alwaysOnRelay, _clamp(c), [
        JournalEvidence(EvidenceKind.hoursCovered, hours, 24),
        daysEvidence,
        if (relay) const JournalEvidence(EvidenceKind.relayRole),
      ]),
    );
  }

  final areaRounded = (areaKm * 10).round() / 10;
  if (positionDays >= 1 && areaKm >= 2) {
    out.add(
      LabelGuess(
        JournalLabel.roamer,
        _clamp(0.5 + math.min(0.45, areaKm / 40)),
        [JournalEvidence(EvidenceKind.areaKm, areaRounded)],
      ),
    );
  } else if (positionDays >= 3 && areaKm < 0.2) {
    out.add(
      LabelGuess(
        JournalLabel.fixedSite,
        _clamp(0.5 + math.min(0.4, positionDays / 25)),
        [JournalEvidence(EvidenceKind.samePlace, positionDays)],
      ),
    );
  }

  // Regular, unless already an always-on relay (which says more).
  final alwaysOn = out.any(
    (g) => g.label == JournalLabel.alwaysOnRelay && g.confidence >= 0.5,
  );
  if (!alwaysOn && window >= 7 && dayShare >= 0.5) {
    out.add(
      LabelGuess(JournalLabel.regular, _clamp(0.3 + 0.6 * dayShare), [
        daysEvidence,
      ]),
    );
  }

  if (span >= 7 && dayShare <= 0.2) {
    out.add(
      LabelGuess(
        JournalLabel.rarelyHeard,
        _clamp(0.95 - 2 * dayShare - (span < 14 ? 0.15 : 0)),
        [daysEvidence],
      ),
    );
  }

  final ageHours = now.difference(entry.firstHeard).inHours;
  if (ageHours >= 0 && ageHours < 48) {
    out.add(
      LabelGuess(JournalLabel.newArrival, 0.6, [
        JournalEvidence(EvidenceKind.firstHeardHours, ageHours),
      ]),
    );
  }

  if (hopsKnown >= 3 && direct / hopsKnown >= 0.7) {
    final share = direct / hopsKnown;
    out.add(
      LabelGuess(
        JournalLabel.nearby,
        _clamp(share * (hopsKnown >= 10 ? 0.95 : 0.8)),
        [
          JournalEvidence(
            EvidenceKind.directShare,
            (share * 100).round(),
            hopsKnown,
          ),
        ],
      ),
    );
  }

  out
    ..removeWhere((g) => g.confidence < 0.5)
    ..sort((a, b) {
      final c = b.confidence.compareTo(a.confidence);
      return c != 0 ? c : a.label.index.compareTo(b.label.index);
    });
  return out;
}

double _clamp(double c) => (c.clamp(0.0, 0.99) * 100).round() / 100;

int _bits(int v) {
  var n = 0;
  for (var x = v; x != 0; x &= x - 1) {
    n++;
  }
  return n;
}

/// Cleans up tags typed by the user: trimmed, lower case, no empties or
/// duplicates, at most 24 characters each, sorted.
List<String> normalizeTags(Iterable<String> tags) {
  final out = <String>{
    for (final t in tags)
      if (t.trim().isNotEmpty)
        t.trim().toLowerCase().substring(0, math.min(24, t.trim().length)),
  };
  return out.toList()..sort();
}

/// A small picture made from a node's ID, so the same node always looks
/// the same and look-alike names are easy to tell apart.
///
/// 5×5 cells, mirrored left to right, in one colour. Made from the SHA-256
/// of the node key, so it is the same on every device and app version.
@immutable
class NodeMark {
  const NodeMark._(this.cells, this.hue);

  factory NodeMark.of(NodeKey key) {
    final h = sha256.convert(key.toString().codeUnits).bytes;
    final hue = ((h[0] << 8) | h[1]) % 360;
    final cells = List<bool>.filled(25, false);
    var bit = 0;
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 3; col++) {
        final on = (h[2 + bit ~/ 8] >> (bit % 8)) & 1 == 1;
        bit++;
        cells[row * 5 + col] = on;
        cells[row * 5 + 4 - col] = on;
      }
    }
    // Never blank: light the centre when nothing else is.
    if (!cells.contains(true)) cells[12] = true;
    return NodeMark._(List.unmodifiable(cells), hue);
  }

  /// Row by row, 25 cells.
  final List<bool> cells;

  /// 0–359.
  final int hue;

  /// The cells as text, `#` for on and `.` for off, one row per line.
  String get pattern => [
    for (var r = 0; r < 5; r++)
      [for (var c = 0; c < 5; c++) cells[r * 5 + c] ? '#' : '.'].join(),
  ].join('\n');
}
