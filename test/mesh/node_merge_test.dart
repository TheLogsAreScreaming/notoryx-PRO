import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/node_merge.dart';

final a = RadioId.meshtastic(1);
final b = RadioId.meshtastic(2);
final key = NodeKey.meshtastic(9);

Node heard(RadioId r, int minute, {GeoPoint? at, NodeKey? k}) => Node(
  key: k ?? key,
  radioId: r,
  name: 'Ann',
  lastHeard: DateTime(2026, 1, 1, 0, minute),
  position: at,
);

void main() {
  test('one entry per node, using the most recent radio', () {
    final m = mergeAcrossRadios([heard(a, 1), heard(b, 5)]);
    expect(m, hasLength(1));
    expect(m.single.node.radioId, b);
    expect(m.single.radios, 2);
  });

  test('keeps a position the newer copy lacks', () {
    final m = mergeAcrossRadios([
      heard(b, 5),
      heard(a, 1, at: const GeoPoint(1, 2)),
    ]);
    expect(m.single.node.radioId, b);
    expect(m.single.node.position?.latitude, 1);
  });

  test('different nodes and order are kept', () {
    final other = NodeKey.meshtastic(10);
    final m = mergeAcrossRadios([
      heard(a, 9, k: other),
      heard(a, 5),
      heard(b, 1),
    ]);
    expect(m.map((x) => x.node.key), [other, key]);
    expect(m.map((x) => x.radios), [1, 2]);
  });
}
