import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/node_journal.dart';

final key = NodeKey.meshtastic(0x1234abcd);
final now = DateTime(2026, 11, 13, 12);

JournalEntry entry({required int ageDays, NodeKind kind = NodeKind.unknown}) =>
    JournalEntry(
      key: key,
      name: 'Ridge',
      kind: kind,
      firstHeard: now.subtract(Duration(days: ageDays)),
      lastHeard: now,
    );

/// A day [daysAgo] before today with the given hours heard.
JournalDay day(
  int daysAgo, {
  Iterable<int> hours = const [9],
  int? hops,
  GeoPoint? at,
}) {
  final d = journalDayOf(now).subtract(Duration(days: daysAgo));
  var out = JournalDay(key: key, day: d);
  for (final h in hours) {
    out = out.add(
      d.add(Duration(hours: h)),
      hops: hops,
      position: at,
    );
  }
  return out;
}

Set<JournalLabel> labels(List<LabelGuess> g) => {for (final x in g) x.label};

void main() {
  test('a day folds reports into hours, hops and a position box', () {
    final d = JournalDay(key: key, day: DateTime(2026, 11, 13))
        .add(DateTime(2026, 11, 13, 3), hops: 0, position: const GeoPoint(1, 2))
        .add(
          DateTime(2026, 11, 13, 23),
          hops: 2,
          position: const GeoPoint(3, 0),
        )
        .add(DateTime(2026, 11, 13, 23, 30));
    expect(d.hoursMask, (1 << 3) | (1 << 23));
    expect(d.reports, 3);
    expect(d.direct, 1);
    expect(d.hopsKnown, 2);
    expect([d.minLat, d.maxLat, d.minLon, d.maxLon], [1, 3, 0, 2]);
  });

  test('heard around the clock for two weeks: always-on relay', () {
    final g = describeNode(entry(ageDays: 14), [
      for (var i = 0; i < 14; i++) day(i, hours: List.generate(24, (h) => h)),
    ], now: now);
    expect(g.first.label, JournalLabel.alwaysOnRelay);
    expect(g.first.percent, 92);
    expect(g.first.evidence, [
      const JournalEvidence(EvidenceKind.hoursCovered, 24, 24),
      const JournalEvidence(EvidenceKind.daysHeard, 14, 15),
    ]);
    // Regular says less than always-on, so it isn't shown as well.
    expect(labels(g), isNot(contains(JournalLabel.regular)));
  });

  test('a relay role adds evidence and confidence', () {
    final halfDay = List.generate(12, (h) => h);
    final g = describeNode(entry(ageDays: 3, kind: NodeKind.relay), [
      for (var i = 0; i < 3; i++) day(i, hours: halfDay),
    ], now: now);
    final relay = g.firstWhere((x) => x.label == JournalLabel.alwaysOnRelay);
    expect(
      relay.evidence,
      contains(const JournalEvidence(EvidenceKind.relayRole)),
    );
    expect(relay.percent, 63);
    // The same hours without the role are not enough.
    final plain = describeNode(entry(ageDays: 3), [
      for (var i = 0; i < 3; i++) day(i, hours: halfDay),
    ], now: now);
    expect(labels(plain), isNot(contains(JournalLabel.alwaysOnRelay)));
  });

  test('positions kilometres apart: roamer; the same spot: fixed site', () {
    final roam = describeNode(entry(ageDays: 3), [
      day(0, at: const GeoPoint(45.50, -122.60)),
      day(1, at: const GeoPoint(45.60, -122.60)),
    ], now: now);
    final r = roam.firstWhere((x) => x.label == JournalLabel.roamer);
    expect(r.evidence.single.kind, EvidenceKind.areaKm);
    expect(r.evidence.single.value, closeTo(11.1, 0.1));

    final fixed = describeNode(entry(ageDays: 5), [
      for (var i = 0; i < 4; i++) day(i, at: const GeoPoint(45.5, -122.6)),
    ], now: now);
    expect(labels(fixed), contains(JournalLabel.fixedSite));
    expect(labels(fixed), isNot(contains(JournalLabel.roamer)));
  });

  test('heard once in three weeks: rarely heard', () {
    final g = describeNode(entry(ageDays: 21), [day(21)], now: now);
    expect(g.single.label, JournalLabel.rarelyHeard);
    expect(
      g.single.evidence.single,
      const JournalEvidence(EvidenceKind.daysHeard, 1, 22),
    );
  });

  test('a new arrival is never more than 60% sure', () {
    final e = JournalEntry(
      key: key,
      name: '',
      firstHeard: now.subtract(const Duration(hours: 5)),
      lastHeard: now,
    );
    final g = describeNode(e, [day(0)], now: now);
    expect(g.single.label, JournalLabel.newArrival);
    expect(g.single.confidence, 0.6);
    expect(
      g.single.evidence.single,
      const JournalEvidence(EvidenceKind.firstHeardHours, 5),
    );
  });

  test('mostly heard with no hops: nearby', () {
    final g = describeNode(entry(ageDays: 3), [
      day(0, hours: [1, 2, 3, 4], hops: 0),
      day(1, hours: [5], hops: 1),
    ], now: now);
    final n = g.firstWhere((x) => x.label == JournalLabel.nearby);
    expect(
      n.evidence.single,
      const JournalEvidence(EvidenceKind.directShare, 80, 5),
    );
  });

  test('little history: no labels; output is ordered and repeatable', () {
    expect(describeNode(entry(ageDays: 3), [day(0)], now: now), isEmpty);
    final days = [
      for (var i = 0; i < 10; i++)
        day(i, hours: [8, 20], hops: 0, at: const GeoPoint(45.5, -122.6)),
    ];
    final a = describeNode(entry(ageDays: 10), days, now: now);
    final b = describeNode(entry(ageDays: 10), days, now: now);
    expect(a.map((x) => x.toString()), b.map((x) => x.toString()));
    for (var i = 1; i < a.length; i++) {
      expect(a[i - 1].confidence, greaterThanOrEqualTo(a[i].confidence));
    }
  });

  test('history older than 30 days is not counted', () {
    final g = describeNode(entry(ageDays: 60), [
      for (var i = 31; i < 60; i++) day(i),
    ], now: now);
    expect(g.single.label, JournalLabel.rarelyHeard);
    expect(g.single.evidence.single.value, 0);
  });

  test('marks are fixed per node ID (golden vectors)', () {
    final a = NodeMark.of(NodeKey.meshtastic(0x1234abcd));
    expect(NodeMark.of(NodeKey.meshtastic(0x1234abcd)).pattern, a.pattern);
    expect(a.cells, hasLength(25));
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 2; c++) {
        expect(a.cells[r * 5 + c], a.cells[r * 5 + 4 - c], reason: 'mirrored');
      }
    }
    expect((a.hue, a.pattern), _goldenA);
    final b = NodeMark.of(NodeKey.meshcore('ab' * 32));
    expect((b.hue, b.pattern), _goldenB);
    expect(a.pattern, isNot(b.pattern));
  });

  test('tags are trimmed, lower case, unique and sorted', () {
    expect(normalizeTags([' Ridge ', 'club', 'ridge', '', 'x' * 30]), [
      'club',
      'ridge',
      'x' * 24,
    ]);
  });
}

// Checked against an independent SHA-256 of the key text.
const _goldenA = (23, '#...#\n.....\n#####\n..#..\n#...#');
const _goldenB = (15, '#...#\n##.##\n.....\n.###.\n.###.');
