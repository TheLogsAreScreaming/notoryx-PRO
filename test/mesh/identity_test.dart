import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/radio/radio_link.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshcore.dart';

final mc = RadioId.meshcore('aa' * 32);
final mt = RadioId.meshtastic(1);
final keyA = Uint8List.fromList(List.generate(32, (i) => i));
final keyB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

void main() {
  test('fingerprints are stable, short and differ per key', () {
    final f = keyFingerprint(keyA);
    expect(f, matches(RegExp(r'^([0-9a-f]{4} ){5}[0-9a-f]{4}$')));
    expect(keyFingerprint(keyA), f);
    expect(keyFingerprint(keyB), isNot(f));
  });

  group('contact links', () {
    test('MeshCore docs example parses', () {
      final c = ContactCard.parse(
        'meshcore://contact/add?name=Example+Contact&public_key=9cd8fcf22a47333b591d96a2b848b73f457b1bb1a3ea2453a885f9e5787765b1&type=1',
      )!;
      expect(c.protocol, RadioProtocol.meshcore);
      expect(c.name, 'Example Contact');
      expect(hexOf(c.publicKey), startsWith('9cd8fcf2'));
      expect(c.key, NodeKey.meshcore(hexOf(c.publicKey)));
    });

    test('MeshCore round trip', () {
      final card = ContactCard(
        protocol: RadioProtocol.meshcore,
        name: 'Ridge Base & Co',
        publicKey: keyA,
        meshCoreType: 2,
      );
      final back = ContactCard.parse(card.toLink())!;
      expect(back.name, 'Ridge Base & Co');
      expect(back.publicKey, keyA);
      expect(back.meshCoreType, 2);
    });

    test('Meshtastic round trip', () {
      final card = ContactCard(
        protocol: RadioProtocol.meshtastic,
        name: 'Base Camp',
        shortName: 'BC',
        publicKey: keyB,
        nodeNum: 0xa1b2c3d4,
      );
      final link = card.toLink();
      expect(link, startsWith('https://meshtastic.org/v/#'));
      expect(link, isNot(contains('=')));
      final back = ContactCard.parse('Scan me: $link')!;
      expect(back.nodeNum, 0xa1b2c3d4);
      expect(back.name, 'Base Camp');
      expect(back.shortName, 'BC');
      expect(back.publicKey, keyB);
      expect(back.key, NodeKey.meshtastic(0xa1b2c3d4));
    });

    test('anything else is not a contact', () {
      expect(ContactCard.parse('https://example.com'), isNull);
      expect(
        ContactCard.parse('meshcore://contact/add?public_key=abcd'),
        isNull,
      );
      expect(ContactCard.parse('https://meshtastic.org/v/#!!!'), isNull);
    });
  });

  group('trust', () {
    Node mcNode(Uint8List key) => Node(
      key: NodeKey.meshcore(hexOf(key)),
      radioId: mc,
      name: 'Sam',
      publicKey: key,
    );

    test('a scanned card must match node and key', () {
      final n = mcNode(keyA);
      final good = ContactCard(
        protocol: RadioProtocol.meshcore,
        name: 'x',
        publicKey: keyA,
      );
      final other = ContactCard(
        protocol: RadioProtocol.meshcore,
        name: 'x',
        publicKey: keyB,
      );
      expect(cardMatches(good, n), isTrue);
      expect(cardMatches(other, n), isFalse);

      final mtNode = Node(
        key: NodeKey.meshtastic(7),
        radioId: mt,
        name: 'R',
        publicKey: keyA,
      );
      final mtCard = ContactCard(
        protocol: RadioProtocol.meshtastic,
        name: 'R',
        publicKey: keyB,
        nodeNum: 7,
      );
      expect(
        cardMatches(mtCard, mtNode),
        isFalse,
        reason: 'same number, other key',
      );
      final noKey = ContactCard(
        protocol: RadioProtocol.meshtastic,
        name: 'R',
        publicKey: Uint8List(0),
        nodeNum: 7,
      );
      expect(
        cardMatches(noKey, mtNode),
        isFalse,
        reason: 'a number alone proves nothing',
      );
    });

    test('verified, unverified, key changed', () {
      final n = Node(
        key: NodeKey.meshtastic(7),
        radioId: mt,
        name: 'R',
        publicKey: keyA,
      );
      final v = Verification(
        node: n.key,
        publicKey: keyA,
        at: DateTime(2026),
        method: VerificationMethod.qr,
      );
      expect(trustOf(n, null), TrustStatus.unverified);
      expect(trustOf(n, v), TrustStatus.verified);
      expect(trustOf(n.copyWith(publicKey: keyB), v), TrustStatus.keyChanged);
    });

    test('name clashes are per radio and ignore case', () {
      final clashes = nameClashes([
        Node(key: NodeKey.meshtastic(1), radioId: mt, name: 'Sam'),
        Node(key: NodeKey.meshtastic(2), radioId: mt, name: 'sam '),
        Node(key: NodeKey.meshtastic(3), radioId: mt, name: 'Ann'),
        Node(key: NodeKey.meshcore(hexOf(keyA)), radioId: mc, name: 'Ann'),
      ]);
      expect(clashes[mt], {'sam'});
      expect(clashes[mc], isEmpty);
    });
  });

  group('store', () {
    late MeshStore store;
    setUp(() => store = MeshStore.memory());
    tearDown(() => store.close());

    test('verifications save, stream and can be removed', () async {
      final key = NodeKey.meshcore(hexOf(keyA));
      final seen = <int>[];
      final sub = store.watchVerifications().listen((m) => seen.add(m.length));
      await store.verify(key, keyA, VerificationMethod.compared);
      final v = (await store.verifications())[key]!;
      expect(v.publicKey, keyA);
      expect(v.method, VerificationMethod.compared);
      await store.unverify(key);
      expect(await store.verifications(), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen, containsAllInOrder([1, 0]));
    });

    test('a partial update never wipes a known key', () async {
      final n = Node(
        key: NodeKey.meshtastic(7),
        radioId: mt,
        name: 'R',
        publicKey: keyA,
      );
      await store.upsertNode(n);
      await store.upsertNode(Node(key: n.key, radioId: mt, name: 'R2'));
      final back = (await store.node(mt, n.key))!;
      expect(back.name, 'R2');
      expect(back.publicKey, keyA);
    });

    test('authenticated flag is stored', () async {
      final now = DateTime.now();
      final c = DirectConversation(mt, NodeKey.meshtastic(7));
      final id = await store.addMessage(
        Message(
          conversation: c,
          text: 'hi',
          outgoing: false,
          sentAt: now,
          receivedAt: now,
          delivery: const Received(),
          from: NodeKey.meshtastic(7),
          nativeId: 1,
          authenticated: true,
        ),
      );
      expect((await store.message(id!))!.message.authenticated, isTrue);
    });
  });

  test(
    'MeshCore direct messages are authenticated once the sender is known',
    () {
      final m = MeshCoreMapper(mc);
      final frame =
          decodeFrame(RadioFrames.contactMessageV3()) as ContactMessageFrame;
      final full = NodeKey.meshcore(hexOf(RadioFrames.key(0x40)));
      expect(
        m.received(frame, findContact: (_) => full)!.authenticated,
        isTrue,
      );
      expect(
        m.received(frame)!.authenticated,
        isFalse,
        reason: 'only a prefix',
      );
      final channel = m.received(decodeFrame(RadioFrames.channelMessageV3()))!;
      expect(channel.authenticated, isFalse);
      expect(
        m.node(decodeFrame(RadioFrames.contact()) as ContactFrame).publicKey,
        RadioFrames.key(0x40),
      );
    },
  );
}
