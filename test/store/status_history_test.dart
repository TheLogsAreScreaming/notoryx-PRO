import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/status_history.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final radio = RadioId.meshcore('aa' * 32);
final repeater = NodeKey.meshcore('bb' * 32);

StatusCheck check(DateTime t, int mv) => StatusCheck(
  time: t,
  batteryMv: mv,
  rssi: -90,
  snr: 6.25,
  noiseFloor: -112,
  errors: 1,
  uptimeSeconds: 7200,
);

void main() {
  late MeshStore store;
  setUp(() => store = MeshStore.memory());
  tearDown(() => store.close());

  test('keeps checks in time order and reads every value', () async {
    final h = StatusHistory(store);
    final t = DateTime(2026, 11, 22, 12);
    await h.add(radio, repeater, check(t, 4100), now: t);
    await h.add(
      radio,
      repeater,
      check(t.subtract(const Duration(hours: 1)), 4150),
      now: t,
    );
    final list = await h.load(radio, repeater);
    expect(list.map((c) => c.batteryMv), [4150, 4100]);
    final c = list.last;
    expect(c.value(StatusMetric.battery), 4.1);
    expect(c.value(StatusMetric.snr), 6.25);
    expect(c.value(StatusMetric.noiseFloor), -112);
    expect(c.value(StatusMetric.uptime), 2);
    expect(await h.load(radio, NodeKey.meshcore('cc' * 32)), isEmpty);
  });

  test('drops checks older than a month and clears', () async {
    final h = StatusHistory(store);
    final t = DateTime(2026, 11, 22);
    await h.add(
      radio,
      repeater,
      check(t.subtract(const Duration(days: 40)), 4000),
      now: t,
    );
    await h.add(radio, repeater, check(t, 3900), now: t);
    expect((await h.load(radio, repeater)).single.batteryMv, 3900);
    await h.clear(radio, repeater);
    expect(await h.load(radio, repeater), isEmpty);
  });
}
