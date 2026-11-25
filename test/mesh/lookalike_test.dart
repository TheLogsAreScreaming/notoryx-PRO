import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/lookalike.dart';
import 'package:notoryx_pro/mesh/mesh.dart';

final mt = RadioId.meshtastic(1);

Node node(int n, String name) =>
    Node(key: NodeKey.meshtastic(n), radioId: mt, name: name);

void main() {
  group('looksLike', () {
    test('Cyrillic and Greek letters fold to Latin', () {
      // "Base Camp" with Cyrillic а and Greek ο mixed in.
      expect(Lookalike.looksLike('Bаse Cаmp', 'Base Camp'), isTrue);
      expect(Lookalike.looksLike('Rοver North', 'Rover North'), isTrue);
    });

    test('digits and symbols used as letters', () {
      expect(Lookalike.looksLike('R0ver N0rth', 'Rover North'), isTrue);
      expect(Lookalike.looksLike(r'Ba$e Camp', 'Base Camp'), isTrue);
      expect(Lookalike.looksLike('Camp Wi11ow', 'Camp Willow'), isTrue);
    });

    test('rn for m and vv for w', () {
      expect(Lookalike.looksLike('Base Carnp', 'Base Camp'), isTrue);
      expect(Lookalike.looksLike('Vvillow Ridge', 'Willow Ridge'), isTrue);
    });

    test('one changed letter in a longer name', () {
      expect(Lookalike.looksLike('Ranger Trucx', 'Ranger Truck'), isTrue);
      expect(Lookalike.looksLike('Ranger Trck', 'Ranger Truck'), isTrue);
    });

    test('exact copies are left to nameClashes', () {
      expect(Lookalike.looksLike('Base Camp', 'base camp '), isFalse);
    });

    test('numbered units of one group are normal', () {
      expect(Lookalike.looksLike('Relay 2', 'Relay 1'), isFalse);
      expect(Lookalike.looksLike('Hilltop 12', 'Hilltop 13'), isFalse);
    });

    test('short or different names are not flagged', () {
      expect(Lookalike.looksLike('Bob', 'Rob'), isFalse);
      expect(Lookalike.looksLike('Lake Camp', 'Camp North'), isFalse);
      expect(Lookalike.looksLike('', 'Base Camp'), isFalse);
      expect(Lookalike.looksLike('🙂🙂', 'Base Camp'), isFalse);
    });
  });

  group('imitated', () {
    final trusted = node(1, 'Base Camp');
    final fake = node(2, 'Bаse Cаmp');
    final other = node(3, 'Lake Camp');
    final nodes = [trusted, fake, other];
    bool isTrusted(Node n) => n.key == trusted.key;

    test('names the trusted node an untrusted sender imitates', () {
      expect(Lookalike.imitated(fake, nodes, isTrusted), trusted);
    });

    test('a trusted sender never imitates', () {
      expect(Lookalike.imitated(trusted, nodes, isTrusted), isNull);
      expect(Lookalike.imitated(fake, nodes, (_) => true), isNull);
    });

    test('only trusted nodes can be imitated', () {
      expect(Lookalike.imitated(fake, nodes, (_) => false), isNull);
    });

    test('unrelated names are fine', () {
      expect(Lookalike.imitated(other, nodes, isTrusted), isNull);
    });

    test('nameless nodes are ignored', () {
      expect(Lookalike.imitated(node(4, ' '), nodes, isTrusted), isNull);
    });
  });
}
