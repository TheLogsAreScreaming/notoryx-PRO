import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/timeline.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/places.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final radio = RadioId.meshtastic(0xa1);
final t0 = DateTime(2026, 11, 13, 9);

Node node(int n, {double? snr, DateTime? heard}) => Node(
  key: NodeKey.meshtastic(n),
  radioId: radio,
  name: 'N$n',
  lastHeard: heard ?? t0,
  path: PathFacts(snr: snr, hops: 0),
);

Map<String, Node> byId(List<Node> l) => {
  for (final n in l) '${n.radioId}/${n.key}': n,
};

Future<void> until(bool Function() ok) async {
  for (var i = 0; i < 100 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('new nodes join; a bar of signal change is noted, not every flap', () {
    final last = <String, DateTime>{};
    final before = byId([node(1, snr: 6)]);
    final first = nodeEvents(
      before,
      [node(1, snr: -2), node(2, snr: 3)],
      now: t0,
      lastSignal: last,
    );
    expect(first.map((e) => (e.kind, e.title)), [
      (TimelineKind.signalChanged, 'N1'),
      (TimelineKind.nodeJoined, 'N2'),
    ]);
    expect(first.first.barsBefore, 4);
    expect(first.first.barsAfter, 2);
    // Back up five minutes later: too soon to note again.
    expect(
      nodeEvents(
        byId([node(1, snr: -2)]),
        [node(1, snr: 6)],
        now: t0.add(const Duration(minutes: 5)),
        lastSignal: last,
      ),
      isEmpty,
    );
    // Within the same bar: nothing.
    expect(
      nodeEvents(
        byId([node(1, snr: 6)]),
        [node(1, snr: 9)],
        now: t0.add(const Duration(hours: 1)),
        lastSignal: last,
      ),
      isEmpty,
    );
  });

  test('new places become waypoint entries', () {
    final e = placeEvents(
      {1},
      const [
        Place(id: 1, kind: PlaceKind.waypoint, name: 'Old', points: []),
        Place(id: 2, kind: PlaceKind.geofence, name: 'Camp', points: []),
      ],
      now: t0,
    );
    expect(e.single.title, 'Camp');
    expect(e.single.placeKind, PlaceKind.geofence);
  });

  test('events survive a save and load as JSON', () {
    final e = TimelineEvent(
      kind: TimelineKind.signalChanged,
      time: t0,
      title: 'Peak',
      protocol: radio.protocol,
      radio: radio,
      node: NodeKey.meshtastic(1),
      barsBefore: 1,
      barsAfter: 3,
      snr: 2.5,
    );
    final back = TimelineEvent.fromJson(e.toJson())!;
    expect(back.kind, e.kind);
    expect(back.time, t0);
    expect(back.radio, radio);
    expect(back.node, e.node);
    expect((back.barsBefore, back.barsAfter, back.snr), (1, 3, 2.5));
    expect(TimelineEvent.fromJson({'k': 'nope'}), isNull);
  });

  test('messages and recorded events merge, newest first, by kind', () {
    final c = ChannelConversation(radio, 0);
    final m = StoredMessage(
      7,
      Message(
        conversation: c,
        text: 'hello',
        outgoing: false,
        sentAt: t0,
        receivedAt: t0.add(const Duration(minutes: 1)),
        delivery: const Received(),
        senderName: 'Ann',
      ),
    );
    final joined = TimelineEvent(
      kind: TimelineKind.nodeJoined,
      time: t0.add(const Duration(minutes: 2)),
      title: 'N2',
    );
    final all = mergeTimeline([joined], [m], {...TimelineKind.values});
    expect(all.map((e) => e.title), ['N2', 'Ann']);
    expect(all.last.message, m);
    expect(
      mergeTimeline([joined], [m], {TimelineKind.message}).single.kind,
      TimelineKind.message,
    );
  });

  test('the recorder starts from a baseline and keeps its log', () async {
    final store = MeshStore.memory();
    await store.upsertNode(node(1, snr: 6));
    final rec = TimelineRecorder(store, clock: () => t0);
    await rec.start();
    await until(() => false); // let the first snapshot arrive
    expect(rec.events, isEmpty, reason: 'what was there is the baseline');

    await store.upsertNode(node(2, snr: 1));
    await store.addPlaces(const [
      Place(kind: PlaceKind.waypoint, name: 'Spring', points: [GeoPoint(1, 2)]),
    ]);
    await until(() => rec.events.length >= 2);
    expect(rec.events.map((e) => e.kind).toSet(), {
      TimelineKind.nodeJoined,
      TimelineKind.waypoint,
    });
    await rec.stop();

    final again = TimelineRecorder(store);
    await again.start();
    expect(again.events, hasLength(2), reason: 'saved and read back');
    await again.clear();
    expect(again.events, isEmpty);
    await again.stop();
    await store.close();
  });
}
