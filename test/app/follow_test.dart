import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/follow.dart';
import 'package:notoryx_pro/mesh/lpp.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final radio = RadioId.meshcore('aa' * 32);
final hiker = NodeKey.meshcore('bb' * 32);

List<int> int24(int v) => [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

/// Battery voltage on channel 1, then GPS on channel 2.
Uint8List lpp(double lat, double lon) => Uint8List.fromList([
  1, 116, 0x01, 0x9a, //
  2, 136, ...int24((lat * 10000).round()), ...int24((lon * 10000).round()),
  ...int24(12000),
]);

void main() {
  test('reads the position after other readings, negatives included', () {
    final p = lppPosition(lpp(45.5123, -122.6789))!;
    expect(p.latitude, closeTo(45.5123, 1e-4));
    expect(p.longitude, closeTo(-122.6789, 1e-4));
    expect(p.altitude, 120);
    expect(lppPosition(Uint8List.fromList([1, 116, 1, 2])), isNull);
    expect(lppPosition(Uint8List.fromList([1, 250, 0])), isNull);
  });

  test('decodes a telemetry push and builds the request', () {
    final push = decodeFrame(
      Uint8List.fromList([0x8b, 0, ...List.filled(6, 0xbb), ...lpp(1, 2)]),
    );
    expect(push, isA<TelemetryResponsePush>());
    expect((push as TelemetryResponsePush).keyPrefix, List.filled(6, 0xbb));
    expect(lppPosition(push.lpp)!.latitude, closeTo(1, 1e-4));
    final cmd = MeshCoreCommands.sendTelemetryRequest(List.filled(32, 7));
    expect(cmd.sublist(0, 4), [39, 0, 0, 0]);
    expect(cmd.length, 36);
  });

  test('follows: asks, takes broadcasts, merges small moves, stops', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    final node = Node(
      key: hiker,
      radioId: radio,
      name: 'Hiker',
      position: const GeoPoint(45.5, -122.6),
    );
    await store.upsertNode(node);
    var answer = const GeoPoint(45.51, -122.6);
    final tracker = FollowTracker(store: store, ask: (_) async => answer);
    addTearDown(tracker.dispose);

    tracker.start(node);
    expect(tracker.isFollowing(node), isTrue);
    await pumpEventQueue();
    expect(tracker.asked, 1);
    expect(tracker.answered, 1);
    expect(tracker.trail.length, 2);
    expect(tracker.trail.last.asked, isTrue);

    answer = const GeoPoint(45.51001, -122.6);
    await tracker.askNow();
    await pumpEventQueue();
    expect(tracker.trail.length, 2);

    await store.upsertNode(
      Node(
        key: hiker,
        radioId: radio,
        name: 'Hiker',
        position: const GeoPoint(45.53, -122.6),
      ),
    );
    await pumpEventQueue();
    expect(tracker.trail.length, 3);
    expect(tracker.trail.last.asked, isFalse);
    expect(tracker.remaining, greaterThan(const Duration(minutes: 14)));

    tracker.stop();
    expect(tracker.active, isFalse);
    expect(tracker.trail, isEmpty);
  });

  test('nodes whose radio cannot ask are only watched', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    final node = Node(key: hiker, radioId: radio, name: 'Hiker');
    final tracker = FollowTracker(store: store, ask: (_) => null);
    addTearDown(tracker.dispose);
    tracker.start(node);
    await tracker.askNow();
    expect(tracker.asked, 0);
  });
}
