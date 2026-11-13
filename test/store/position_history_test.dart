import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/replay.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final radio = RadioId.meshtastic(0xa1);
final ann = NodeKey.meshtastic(0x22);
final t0 = DateTime(2026, 11, 13, 9);

Node at(double lat, DateTime heard, {bool mqtt = false}) => Node(
  key: ann,
  radioId: radio,
  name: 'Ann',
  position: GeoPoint(lat, -122.6),
  lastHeard: heard,
  path: PathFacts(viaMqtt: mqtt),
);

void main() {
  test('positions are recorded when they are new', () async {
    final store = MeshStore.memory();
    await store.upsertNode(at(45.50, t0));
    // Same place a minute later: nothing new.
    await store.upsertNode(at(45.50, t0.add(const Duration(minutes: 1))));
    // Moved.
    await store.upsertNode(at(45.51, t0.add(const Duration(minutes: 2))));
    // Same report again (not newer): ignored.
    await store.upsertNode(at(45.52, t0.add(const Duration(minutes: 2))));
    // Still there after the repeat interval: noted again.
    await store.upsertNode(at(45.51, t0.add(const Duration(minutes: 15))));
    // Heard over the internet: not a radio position.
    await store.upsertNode(
      at(46.0, t0.add(const Duration(minutes: 20)), mqtt: true),
    );
    // Batch sync records too.
    await store.upsertNodes([at(45.53, t0.add(const Duration(minutes: 30)))]);

    final (from, to) = dayBounds(t0);
    final tracks = await store.tracks(from, to);
    final t = tracks.single;
    expect(t.radio, radio);
    expect(t.node, ann);
    expect(t.points.map((p) => p.position.latitude), [
      45.50,
      45.51,
      45.51,
      45.53,
    ]);
    expect(await store.tracks(to, to.add(const Duration(days: 1))), isEmpty);
    expect(await store.daysWithPositions(), [DateTime(2026, 11, 13)]);

    expect(
      await store.prunePositions(t0.add(const Duration(days: 31))),
      4,
      reason: 'older than 30 days',
    );
    await store.close();
  });

  test('a track finds where a node was at any time', () {
    final track = Track(
      radio: radio,
      node: ann,
      points: [
        for (var i = 0; i < 5; i++)
          TrackPoint(
            t0.add(Duration(minutes: 10 * i)),
            GeoPoint(45.0 + i / 100, -122),
          ),
      ],
    );
    expect(track.at(t0.subtract(const Duration(seconds: 1))), isNull);
    expect(track.at(t0)!.position.latitude, 45.0);
    expect(
      track.at(t0.add(const Duration(minutes: 25)))!.position.latitude,
      45.02,
    );
    expect(
      track.at(t0.add(const Duration(hours: 5)))!.position.latitude,
      45.04,
    );
    expect(track.trailUntil(t0.add(const Duration(minutes: 10))), hasLength(2));
    expect(timeSpan([track]), (t0, t0.add(const Duration(minutes: 40))));
    expect(timeSpan(const []), isNull);
    expect(dayBounds(DateTime(2026, 11, 13, 18)), (
      DateTime(2026, 11, 13),
      DateTime(2026, 11, 14),
    ));
  });
}
