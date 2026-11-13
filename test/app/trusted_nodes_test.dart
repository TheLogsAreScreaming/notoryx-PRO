import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/trusted_nodes.dart';
import 'package:notoryx_pro/mesh/identity.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final mt = RadioId.meshtastic(0xa1b2c3d4);
Node node(int n, {bool favorite = false}) => Node(
  key: NodeKey.meshtastic(n),
  radioId: mt,
  name: 'N$n',
  isFavorite: favorite,
);

void main() {
  test('decode ignores junk', () {
    expect(TrustedNodes.decode(null), isEmpty);
    expect(TrustedNodes.decode('not json'), isEmpty);
    expect(TrustedNodes.decode('{"a":1}'), isEmpty);
    expect(TrustedNodes.decode('["a", 2, "b"]'), {'a', 'b'});
  });

  test('marked, favourite or verified counts as trusted', () {
    final state = TrustState(
      marked: {NodeKey.meshtastic(1).toString()},
      verifications: {
        NodeKey.meshtastic(3): Verification(
          node: NodeKey.meshtastic(3),
          publicKey: Uint8List(0),
          at: DateTime(2026),
          method: VerificationMethod.values.first,
        ),
      },
    );
    expect(state.trusts(node(1)), isTrue);
    expect(state.trusts(node(2, favorite: true)), isTrue);
    expect(state.trusts(node(3)), isTrue);
    expect(state.trusts(node(4)), isFalse);
    // Starred on another radio.
    expect(state.trusts(node(4), favorites: {NodeKey.meshtastic(4)}), isTrue);
    expect(favoriteKeys([node(5, favorite: true), node(6)]), {
      NodeKey.meshtastic(5),
    });
  });

  test('marks and the switch are saved and watched', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    final states = <TrustState>[];
    final sub = TrustedNodes.watch(store).listen(states.add);
    await TrustedNodes.setMarked(store, NodeKey.meshtastic(7), trusted: true);
    await TrustedNodes.setOnlyTrusted(store, true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states.last.isMarked(NodeKey.meshtastic(7)), isTrue);
    expect(states.last.onlyTrusted, isTrue);
    await TrustedNodes.setMarked(store, NodeKey.meshtastic(7), trusted: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states.last.marked, isEmpty);
    await sub.cancel();
  });
}
