import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/node_journal.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final mtRadio = RadioId.meshtastic(0xa1);
final mtRadio2 = RadioId.meshtastic(0xa2);
final mcRadio = RadioId.meshcore('cd' * 32);
final ann = NodeKey.meshtastic(0x22);
final rpt = NodeKey.meshcore('ef' * 32);
final t0 = DateTime(2026, 11, 13, 9);

Node node(
  NodeKey key,
  RadioId radio,
  DateTime heard, {
  String name = 'Ann',
  NodeKind kind = NodeKind.unknown,
  GeoPoint? at,
  int? hops,
  bool mqtt = false,
}) => Node(
  key: key,
  radioId: radio,
  name: name,
  kind: kind,
  position: at,
  lastHeard: heard,
  path: PathFacts(hops: hops, viaMqtt: mqtt),
);

void main() {
  test('every node heard on either mesh is logged once per report', () async {
    final store = MeshStore.memory();
    await store.upsertNode(node(ann, mtRadio, t0, hops: 0));
    // The same report synced again, and heard by a second radio.
    await store.upsertNode(node(ann, mtRadio, t0, hops: 0));
    await store.upsertNode(node(ann, mtRadio2, t0, hops: 0));
    // A newer report with a new name and a position.
    await store.upsertNode(
      node(
        ann,
        mtRadio,
        t0.add(const Duration(hours: 3)),
        name: 'Ann L',
        hops: 2,
        at: const GeoPoint(45.5, -122.6),
      ),
    );
    // A MeshCore repeater, from the start-up sync.
    await store.upsertNodes([
      node(rpt, mcRadio, t0, name: 'Hilltop', kind: NodeKind.relay),
    ]);

    final all = await store.watchJournal().first;
    expect(all.map((e) => e.displayName), ['Ann L', 'Hilltop']);
    final a = all.first;
    expect(a.heardCount, 2);
    expect(a.firstHeard, t0);
    expect(a.lastHeard, t0.add(const Duration(hours: 3)));
    expect(a.position, const GeoPoint(45.5, -122.6));
    expect(all.last.kind, NodeKind.relay);

    final days = await store.journalDays(t0, only: ann);
    final d = days[ann]!.single;
    expect(d.reports, 2);
    expect(d.hoursMask, (1 << 9) | (1 << 12));
    expect(d.direct, 1);
    expect(d.hopsKnown, 2);
    expect(d.minLat, 45.5);
    await store.close();
  });

  test('an older report moves first heard back without counting', () async {
    final store = MeshStore.memory();
    await store.upsertNode(node(ann, mtRadio, t0));
    await store.upsertNode(
      node(ann, mtRadio2, t0.subtract(const Duration(days: 2))),
    );
    final e = (await store.journalEntry(ann))!;
    expect(e.firstHeard, t0.subtract(const Duration(days: 2)));
    expect(e.lastHeard, t0);
    expect(e.heardCount, 1);
    await store.close();
  });

  test(
    'reports over the internet are logged but not as radio history',
    () async {
      final store = MeshStore.memory();
      await store.upsertNode(
        node(ann, mtRadio, t0, mqtt: true, at: const GeoPoint(1, 1)),
      );
      final e = (await store.journalEntry(ann))!;
      expect(e.position, isNull);
      expect(await store.journalDays(t0), isEmpty);
      await store.close();
    },
  );

  test('tags, notes, forgetting and pruning', () async {
    final store = MeshStore.memory();
    await store.upsertNode(node(ann, mtRadio, t0));
    await store.setJournalTags(ann, ['Club', ' ridge', 'club']);
    await store.setJournalNote(ann, '  Lives up the hill. ');
    var e = (await store.journalEntry(ann))!;
    expect(e.tags, ['club', 'ridge']);
    expect(e.note, 'Lives up the hill.');

    // Tags and notes survive new reports.
    await store.upsertNode(node(ann, mtRadio, t0.add(const Duration(days: 1))));
    e = (await store.journalEntry(ann))!;
    expect(e.tags, ['club', 'ridge']);
    expect(e.heardCount, 2);

    expect(
      await store.pruneJournalDays(t0.add(const Duration(days: 91))),
      1,
      reason: 'only the first day is past 90 days',
    );
    expect((await store.journalEntry(ann))!.note, 'Lives up the hill.');

    await store.forgetJournalNode(ann);
    expect(await store.journalEntry(ann), isNull);
    expect(await store.journalDays(t0), isEmpty);
    await store.close();
  });

  test('labels come from stored history', () async {
    final store = MeshStore.memory();
    // Every two hours for ten days, in time order.
    for (var d = 9; d >= 0; d--) {
      for (var h = 0; h < 24; h += 2) {
        await store.upsertNode(
          node(
            rpt,
            mcRadio,
            DateTime(2026, 11, 13 - d, h),
            kind: NodeKind.relay,
          ),
        );
      }
    }
    final e = (await store.journalEntry(rpt))!;
    final days = await store.journalDays(DateTime(2026, 10, 1), only: rpt);
    final g = describeNode(e, days[rpt]!, now: DateTime(2026, 11, 13, 23));
    expect(g.first.label, JournalLabel.alwaysOnRelay);
    await store.close();
  });
}
