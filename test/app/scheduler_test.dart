import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/message_scheduler.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final ch = ChannelConversation(RadioId.meshtastic(0xa1b2c3d4), 0);

void main() {
  late MeshStore store;
  late DateTime now;
  late List<String> sent;
  late Future<bool> Function(String) radio;
  late MessageScheduler s;

  setUp(() {
    store = MeshStore.memory();
    now = DateTime(2026, 11, 9, 12);
    sent = [];
    radio = (t) async {
      sent.add(t);
      return true;
    };
    s = MessageScheduler(
      store: store,
      send: (_, t) => radio(t),
      now: () => now,
    );
  });
  tearDown(() => store.close());

  Future<List<ScheduledMessage>> items() => s.watch().first;

  test('sends when due, once', () async {
    await s.add(ch, 'hi', now.add(const Duration(minutes: 5)));
    await s.tick();
    expect(sent, isEmpty);
    now = now.add(const Duration(minutes: 6));
    await s.tick();
    await s.tick();
    expect(sent, ['hi']);
    expect(await items(), isEmpty);
  });

  test('waits for the radio, then gives up as missed', () async {
    radio = (_) async => false;
    await s.add(ch, 'hi', now);
    await s.tick();
    expect((await items()).single.state, ScheduleState.waiting);
    now = now.add(const Duration(hours: 2));
    await s.tick();
    expect((await items()).single.state, ScheduleState.missed);
    radio = (t) async {
      sent.add(t);
      return true;
    };
    await s.tick();
    expect(sent, isEmpty, reason: 'a missed message never goes out');
  });

  test('a failed send is kept, marked, and not retried', () async {
    radio = (_) async => throw StateError('nope');
    await s.add(ch, 'hi', now);
    await s.tick();
    expect((await items()).single.state, ScheduleState.failed);
    var calls = 0;
    radio = (_) async {
      calls++;
      return true;
    };
    await s.tick();
    expect(calls, 0);
  });

  test('cancelling removes it, and the list survives a restart', () async {
    await s.add(ch, 'a', now.add(const Duration(hours: 1)));
    now = now.add(const Duration(seconds: 1));
    await s.add(ch, 'b', now.add(const Duration(hours: 2)));
    final again = MessageScheduler(store: store, send: (_, _) async => true);
    final list = await again.watch().first;
    expect(list.map((m) => m.text), ['a', 'b']);
    await s.remove(list.first.id);
    expect((await items()).single.text, 'b');
  });

  test('a corrupt list reads as empty', () {
    expect(MessageScheduler.decode('not json'), isEmpty);
    expect(MessageScheduler.decode('[1,{"id":"x"}]'), isEmpty);
  });
}
