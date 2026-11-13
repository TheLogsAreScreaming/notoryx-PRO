import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/topology.dart';
import 'package:notoryx_pro/ui/topology_screen.dart';

final mc = RadioId.meshcore('aa' * 32);
final mt = RadioId.meshtastic(0xa1b2c3d4);

Node core(String hex, String name, {int? hops, List<int> route = const []}) =>
    Node(
      key: NodeKey.meshcore(hex.padRight(64, '0')),
      radioId: mc,
      name: name,
      kind: NodeKind.person,
      path: PathFacts(hops: hops),
      route: route,
    );

void main() {
  // Relay 11… heard directly; Alex two hops out via 11 then an unknown 7f.
  final relay = core('11', 'Ridge relay', hops: 0);
  final alex = core('22', 'Alex', hops: 2, route: [0x11, 0x7f]);
  final sam = core('33', 'Sam', hops: 1, route: [0x11]);
  final far = Node(
    key: NodeKey.meshtastic(9),
    radioId: mt,
    name: 'Far',
    path: const PathFacts(hops: 3),
  );
  final unknown = core('44', 'No hops');

  test('nodes sit on the ring for their hops, linked along routes', () {
    final t = Topology.build([relay, alex, sam, far, unknown]);
    String id(Node n) => n.key.toString();
    expect(t.nodes[id(relay)]!.ring, 1);
    expect(t.nodes[id(sam)]!.ring, 2);
    expect(t.nodes[id(alex)]!.ring, 3);
    expect(t.nodes[id(far)]!.ring, 4);
    expect(t.nodes.containsKey(id(unknown)), isFalse);
    // The unknown repeater shows by its prefix, on ring 2.
    expect(t.nodes['?7f']!.ring, 2);
    expect(t.nodes['?7f']!.unknown, isTrue);
    // The relay carries both routes.
    expect(t.nodes[id(relay)]!.routes, 2);

    Set<String> linked(String a) => {
      for (final l in t.links)
        if (l.a == a) l.b else if (l.b == a) l.a,
    };
    expect(linked(topologyYou), {id(relay)});
    expect(linked(id(relay)), {topologyYou, '?7f', id(sam)});
    expect(linked(id(alex)), {'?7f'});
    expect(linked(id(far)), isEmpty);
    final youRelay = t.links.firstWhere(
      (l) => {l.a, l.b}.containsAll([topologyYou, id(relay)]),
    );
    expect(youRelay.count, 3); // heard directly + two routes
  });

  test('layout puts you in the middle and rings at even steps', () {
    final t = Topology.build([relay, alex, sam, far]);
    final layout = layoutTopology(t, const Size(400, 400));
    expect(layout.centers[topologyYou], const Offset(200, 200));
    expect(layout.rings, 4);
    for (final n in t.nodes.values) {
      final d = (layout.centers[n.id]! - layout.center).distance;
      expect(d, closeTo(layout.ringGap * n.ring, .001));
    }
    final relayAt = layout.centers[relay.key.toString()]!;
    expect(layout.hit(relayAt), relay.key.toString());
    expect(layout.hit(const Offset(-50, -50)), isNull);
  });

  test('empty and capped', () {
    expect(Topology.build(const []).nodes.keys, [topologyYou]);
    final many = [
      for (var i = 0; i < 80; i++)
        Node(
          key: NodeKey.meshtastic(i + 1),
          radioId: mt,
          name: 'n$i',
          path: const PathFacts(hops: 0),
        ),
    ];
    expect(Topology.build(many, maxNodes: 20).nodes, hasLength(21));
  });
}
