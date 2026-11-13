import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/trace_card.dart';
import 'package:notoryx_pro/radio/radio.dart';

void main() {
  final radio = RadioId.meshcore('ab' * 32);
  Node node(String hex, String name, [GeoPoint? at]) => Node(
    key: NodeKey.meshcore(hex * 32),
    radioId: radio,
    name: name,
    position: at,
  );
  const base = GeoPoint(45.50, -122.60);
  const peak = GeoPoint(45.55, -122.50);

  test('a MeshCore trace becomes out and back stops with positions', () {
    final r = TraceResult(
      target: NodeKey.meshcore('cd' * 32),
      // Saved traces keep names only: Peak is found by name, b2 isn't.
      towards: const [TraceHop('Peak', 3), TraceHop('b2', 1)],
      back: const [TraceHop('Peak', -1), TraceHop('Base', 2.5)],
      time: DateTime(2026, 11, 13, 9, 30),
      roundTrip: const Duration(milliseconds: 3400),
    );
    final card = TraceCardData.from(
      result: r,
      protocol: RadioProtocol.meshcore,
      senderName: 'Base',
      senderPosition: base,
      targetName: 'Ann',
      known: [node('a1', 'Peak', peak), node('a2', 'Mill')],
    );
    expect(card.out.map((s) => s.label), ['Base', 'Peak', 'b2']);
    expect(card.out.first.snr, isNull);
    expect(card.out[1].position, peak);
    expect(card.out[2].position, isNull);
    expect(card.back.map((s) => s.label), ['b2', 'Peak', 'Base']);
    expect(card.back.last.position, base, reason: 'back home');
    expect(card.hopsOut, 2);
    expect(card.outLine, [base, peak]);
    expect(card.backLine, [peak, base]);
    expect(card.placedCount, (2, 3));
    expect(card.roundTrip, const Duration(milliseconds: 3400));
  });

  test('a hop with its node uses the node position; twins are not guessed', () {
    final live = node('a1', 'Peak', peak);
    final card = TraceCardData.from(
      result: TraceResult(
        target: live.key,
        towards: [
          TraceHop('Peak', 5, node: live),
          const TraceHop('Twin', 1),
        ],
        time: DateTime(2026),
      ),
      protocol: RadioProtocol.meshtastic,
      senderName: 'Base',
      targetName: 'Peak',
      known: [node('b1', 'Twin', base), node('b2', 'Twin', peak)],
    );
    expect(card.out[1].position, peak);
    expect(card.out[2].position, isNull);
    expect(card.back, isEmpty, reason: 'no way back reported');
    expect(card.placedCount, (1, 3));
  });
}
