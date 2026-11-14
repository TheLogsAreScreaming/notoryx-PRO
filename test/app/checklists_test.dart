import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/checklists.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

const trip = ChecklistTemplate(
  id: 't1',
  name: 'Pre-trip',
  items: ['Charge radio', 'Pack map', 'Tell someone'],
);

void main() {
  test('a run is ticked, finished and saved as a timestamped record', () async {
    final store = MeshStore.memory();
    var now = DateTime(2026, 11, 13, 8);
    final book = ChecklistBook(store, clock: () => now);
    await book.load();
    expect(book.templates, isNull, reason: 'never saved: starters go in');
    await book.seed([trip]);
    await book.seed(const []);
    expect(book.templates!.single.name, 'Pre-trip');

    await book.start(trip);
    now = now.add(const Duration(minutes: 5));
    await book.toggle(0);
    now = now.add(const Duration(minutes: 5));
    await book.toggle(2);
    await book.toggle(2);
    await book.toggle(1);
    await book.setNote('  Spare cable too ');
    expect(book.active!.doneCount, 2);

    // The run in progress survives a restart.
    final again = ChecklistBook(store, clock: () => now);
    await again.load();
    expect(again.active!.items.map((i) => i.done), [true, true, false]);
    expect(again.active!.items.first.checkedAt, DateTime(2026, 11, 13, 8, 5));

    now = now.add(const Duration(minutes: 1));
    final record = (await again.finish())!;
    expect(again.active, isNull);
    expect(record.finishedAt, DateTime(2026, 11, 13, 8, 11));
    expect(record.note, 'Spare cable too');
    expect(record.complete, isFalse);

    final third = ChecklistBook(store);
    await third.load();
    expect(third.active, isNull);
    expect(third.records.single.id, record.id);
    expect(
      third.records.single.items[1].checkedAt,
      DateTime(2026, 11, 13, 8, 10),
    );

    await third.deleteRecord(record.id);
    expect(third.records, isEmpty);
    await store.close();
  });

  test('checklists can be added, changed and deleted', () async {
    final store = MeshStore.memory();
    final book = ChecklistBook(store);
    await book.load();
    await book.saveTemplate(trip);
    await book.saveTemplate(trip.copyWith(items: ['Only this']));
    await book.saveTemplate(
      const ChecklistTemplate(id: 't2', name: 'Deploy', items: ['Mount']),
    );
    expect(book.templates!.map((t) => t.name), ['Pre-trip', 'Deploy']);
    expect(book.templates!.first.items, ['Only this']);
    await book.deleteTemplate('t1');
    final again = ChecklistBook(store);
    await again.load();
    expect(again.templates!.single.id, 't2');
    // An empty saved list is not replaced by starters.
    await again.deleteTemplate('t2');
    await again.seed([trip]);
    expect(again.templates, isEmpty);
    await store.close();
  });

  test('discarding keeps no record; a damaged preference is ignored', () async {
    final store = MeshStore.memory();
    final book = ChecklistBook(store);
    await book.load();
    await book.start(trip);
    await book.discard();
    expect(book.active, isNull);
    expect(book.records, isEmpty);

    await store.setPreference(ChecklistBook.recordsPref, '{not json');
    await store.setPreference(ChecklistBook.templatesPref, '[1, {"id": 2}]');
    final again = ChecklistBook(store);
    await again.load();
    expect(again.records, isEmpty);
    expect(again.templates, isEmpty);
    await store.close();
  });

  test('records export as text and as versioned JSON', () {
    final started = DateTime.utc(2026, 11, 13, 8);
    final r = ChecklistRun.start(trip, started)
        .toggle(0, started.add(const Duration(minutes: 3)))
        .withNote('All good')
        .finish(started.add(const Duration(minutes: 9)));

    final text = checklistRecordsText(
      [r],
      ChecklistTextLabels(
        started: (w) => 'Started $w',
        finished: (w) => 'Finished $w',
        note: (n) => 'Note: $n',
        done: (d, t) => '$d of $t done',
      ),
      (t) => '${t.toUtc().hour}:${t.toUtc().minute.toString().padLeft(2, '0')}',
    );
    expect(text, '''
Pre-trip
Started 8:00
Finished 8:09
1 of 3 done
[x] Charge radio (8:03)
[ ] Pack map
[ ] Tell someone
Note: All good
''');

    final json =
        jsonDecode(
              checklistRecordsJson([r], exportedAt: DateTime.utc(2026, 11, 14)),
            )
            as Map<String, Object?>;
    expect(json['format'], 'notoryx-pro-checklists');
    expect(json['formatVersion'], 1);
    expect(json['exportedAt'], '2026-11-14T00:00:00.000Z');
    final rec = (json['records']! as List).single as Map<String, Object?>;
    expect(rec['startedAt'], '2026-11-13T08:00:00.000Z');
    expect(rec['finishedAt'], '2026-11-13T08:09:00.000Z');
    expect((rec['items']! as List).first, {
      'text': 'Charge radio',
      'done': true,
      'checkedAt': '2026-11-13T08:03:00.000Z',
    });
    // Round trip.
    final back = ChecklistRun.fromJson(rec)!;
    expect(
      back.items.first.checkedAt!.isAtSameMomentAs(r.items.first.checkedAt!),
      isTrue,
    );
    expect(back.note, 'All good');
  });
}
