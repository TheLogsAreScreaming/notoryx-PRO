import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/distress_beacon.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final radio = RadioId.meshtastic(0xa1b2c3d4);
final ch = ChannelConversation(radio, 0);

StoredMessage incoming(String text) => StoredMessage(
  1,
  Message(
    conversation: ch,
    text: text,
    outgoing: false,
    sentAt: DateTime(2026),
    receivedAt: DateTime(2026),
    delivery: const Received(),
  ),
);

void main() {
  late List<String> sent;
  late StreamController<StoredMessage> rx;

  DistressBeacon beacon({
    Duration every = const Duration(minutes: 5),
    Duration lasts = const Duration(minutes: 20),
    bool drill = false,
    String note = '',
    int maxBytes = 160,
  }) => DistressBeacon(
    conversation: ch,
    send: (t) async => sent.add(t),
    position: () async => (45.12346, -122.5),
    incoming: rx.stream,
    every: every,
    lasts: lasts,
    drill: drill,
    note: note,
    maxBytes: maxBytes,
  );

  setUp(() {
    sent = [];
    rx = StreamController.broadcast();
  });

  testWidgets('sends now, repeats, then ends by itself', (t) async {
    final b = beacon();
    await b.start();
    expect(sent, hasLength(1));
    final m = MecpMessage.tryParse(sent.single)!;
    expect(m.severity, MecpSeverity.mayday);
    expect(m.codes, ['B01', 'P05']);
    expect(m.position, (45.1235, -122.5));
    expect(m.isDrill, isFalse);
    await t.pump(const Duration(minutes: 5));
    expect(sent, hasLength(2));
    await t.pump(const Duration(minutes: 15));
    expect(b.active, isFalse);
    final total = sent.length;
    await t.pump(const Duration(minutes: 30));
    expect(sent, hasLength(total));
  });

  testWidgets('limits cannot be set past the safe range', (t) async {
    final b = beacon(
      every: const Duration(seconds: 5),
      lasts: const Duration(days: 3),
    );
    expect(b.every, DistressBeacon.minEvery);
    expect(b.lasts, DistressBeacon.maxLasts);
  });

  testWidgets('stops at once; "I am OK" also cancels on the mesh', (t) async {
    final a = beacon();
    await a.start();
    await a.stop();
    await t.pump(const Duration(hours: 1));
    expect(sent, hasLength(1));

    final b = beacon();
    await b.start();
    await b.stop(imOk: true);
    expect(MecpMessage.tryParse(sent.last)!.codes, ['B03']);
  });

  testWidgets('an acknowledgement halves the rate, once', (t) async {
    final b = beacon(lasts: const Duration(hours: 1));
    await b.start();
    rx.add(incoming('MECP/3/B02'));
    await t.pump();
    expect((b.acknowledged, b.every), (true, const Duration(minutes: 10)));
    rx.add(incoming('MECP/3/B02'));
    await t.pump();
    expect(b.every, const Duration(minutes: 10));
    await t.pump(const Duration(minutes: 5));
    expect(sent, hasLength(1));
    await t.pump(const Duration(minutes: 5));
    expect(sent, hasLength(2));
    await b.stop();
  });

  testWidgets('a failed send is counted and it keeps trying', (t) async {
    var fail = true;
    final b = DistressBeacon(
      conversation: ch,
      send: (x) async {
        if (fail) throw StateError('no radio');
        sent.add(x);
      },
      position: () async => null,
      incoming: rx.stream,
      maxBytes: 160,
    );
    await b.start();
    expect(b.failed, 1);
    fail = false;
    await t.pump(const Duration(minutes: 5));
    expect(sent, hasLength(1));
    await b.stop();
  });

  test('drills are marked, and a long note is cut to fit', () {
    final d = beacon(drill: true).textFor(null);
    expect(MecpMessage.tryParse(d)!.isDrill, isTrue);
    final long = beacon(note: 'x' * 300, maxBytes: 40).textFor((1, 2));
    expect(long.length, lessThanOrEqualTo(40));
    expect(MecpMessage.tryParse(long)!.position, (1.0, 2.0));
  });
}
