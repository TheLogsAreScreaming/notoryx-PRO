import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/route_planner.dart';

void main() {
  final radio = RadioId.meshcore('ab' * 32);
  Node relay(String keyHex, String name) => Node(
    key: NodeKey.meshcore(keyHex),
    radioId: radio,
    name: name,
    kind: NodeKind.relay,
    publicKey: List.filled(32, int.parse(keyHex.substring(0, 2), radix: 16)),
    lastHeard: DateTime(2026, 11, 13),
  );
  final peak = relay('a1' * 32, 'Peak');
  final mill = relay('b2' * 32, 'Mill');
  final tower = relay('c3' * 32, 'Tower');
  final target = Node(
    key: NodeKey.meshcore('d4' * 32),
    radioId: radio,
    name: 'Ann',
    route: const [0xa1, 0xb2],
    path: const PathFacts(hops: 2, route: RouteKind.direct),
  );
  final now = DateTime(2026, 11, 13, 12);

  SavedTrace trace(
    int id,
    List<(String, double)> out,
    List<double> back,
    DateTime at,
  ) => SavedTrace(
    id: id,
    targetName: 'Ann',
    result: TraceResult(
      target: target.key,
      towards: [for (final (h, s) in out) TraceHop(h, s, hash: h)],
      back: [for (final s in back) TraceHop('x', s)],
      time: at,
    ),
  );

  test('a trace becomes a route with SNR both ways per link', () {
    // Out: us→a1 heard 5.0 by a1, a1→b2 heard -3.0 by b2.
    // Back: b2→a1 heard -6.0 by a1, then a1→us heard 4.0 by us.
    final c = RoutePlan.fromTrace(
      trace(1, [('a1', 5), ('b2', -3)], [-6, 4], now).result,
      (h) => {'a1': peak, 'b2': mill}[h],
    )!;
    expect(c.hashes, ['a1', 'b2']);
    expect(c.hops.first.label, 'Peak');
    expect(c.hops[0].snr, 5);
    expect(c.hops[0].backSnr, 4);
    expect(c.hops[1].snr, -3);
    expect(c.hops[1].backSnr, -6);
    expect(c.weakestSnr, -6);
    expect(c.unmeasured, 0);
  });

  test('traces saved without hop hashes are not routes', () {
    final old = TraceResult(
      target: target.key,
      towards: const [TraceHop('Peak', 3)],
      time: now,
    );
    expect(RoutePlan.fromTrace(old, (_) => null), isNull);
  });

  test('the plan suggests a clearly better measured route', () {
    final plan = RoutePlan.build(
      target,
      [
        // Newest first: the current route, measured weak.
        trace(3, [('a1', -9), ('b2', -11)], [-10, -8], now),
        // A one-hop route through Tower, measured strong.
        trace(2, [('c3', 6)], [5], now.subtract(const Duration(hours: 2))),
        // An older copy of the current route is not listed twice.
        trace(1, [('a1', 2), ('b2', 2)], [2, 2], DateTime(2026, 11, 1)),
      ],
      [peak, mill, tower, target],
      now: now,
    );
    expect(plan.current!.hashes, ['a1', 'b2']);
    expect(plan.current!.measured, now, reason: 'newest measurement');
    expect(plan.current!.weakestSnr, -11);
    expect(plan.others.map((c) => c.hashes), [
      ['c3'],
    ]);
    expect(plan.better!.hashes, ['c3']);
    expect(plan.better!.hops.single.label, 'Tower');
  });

  test('no suggestion when the alternative is not clearly better', () {
    final plan = RoutePlan.build(
      target,
      [
        trace(2, [('a1', 4), ('b2', 4)], [4, 4], now),
        trace(1, [('c3', 3)], [3], now),
      ],
      [peak, mill, tower],
      now: now,
    );
    // Current scores 4 - 3 = 1; Tower 3 - 1.5 = 1.5: within the margin.
    expect(plan.others, hasLength(1));
    expect(plan.better, isNull);
  });

  test('a flooding node gets any measured route suggested', () {
    final flooding = Node(key: target.key, radioId: radio, name: 'Ann');
    final plan = RoutePlan.build(
      flooding,
      [
        trace(1, [('c3', -2)], [-1], now),
      ],
      [tower],
      now: now,
    );
    expect(plan.current, isNull);
    expect(plan.better!.hashes, ['c3']);
  });

  test('unmeasured and stale routes score lower', () {
    const hop = PlannedHop(hash: 'a1', label: 'a1', snr: 3, backSnr: 3);
    final fresh = RouteChoice(
      hops: const [hop],
      source: RouteSource.trace,
      measured: now,
    );
    final stale = RouteChoice(
      hops: const [hop],
      source: RouteSource.trace,
      measured: now.subtract(const Duration(days: 30)),
    );
    const blind = RouteChoice(
      hops: [PlannedHop(hash: 'a1', label: 'a1')],
      source: RouteSource.manual,
    );
    expect(fresh.score(now), greaterThan(stale.score(now)));
    expect(stale.score(now), greaterThan(blind.score(now)));
  });

  test('route candidates are keyed repeaters and rooms, newest first', () {
    final person = Node(
      key: NodeKey.meshcore('e5' * 32),
      radioId: radio,
      name: 'Bo',
      publicKey: List.filled(32, 0xe5),
    );
    final older = Node(
      key: NodeKey.meshcore('f6' * 32),
      radioId: radio,
      name: 'Old',
      kind: NodeKind.room,
      publicKey: List.filled(32, 0xf6),
      lastHeard: DateTime(2026, 1, 1),
    );
    final keyless = Node(
      key: NodeKey.meshcore('07' * 32),
      radioId: radio,
      name: 'NoKey',
      kind: NodeKind.relay,
    );
    expect(routeCandidates(target, [older, person, keyless, peak, target]), [
      peak,
      older,
    ]);
    expect(hopHash(peak, 2), 'a1a1');
  });
}
