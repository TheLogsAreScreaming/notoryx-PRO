import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshcore.dart';

class _Links extends LinkFactory {
  _Links(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

void main() {
  test('choosing a route writes it to the radio and the store', () async {
    final sent = <Uint8List>[];
    final link = ScriptedMeshCoreLink(
      responder: (cmd) {
        sent.add(cmd);
        return switch (cmd.first) {
          Cmd.appStart => [RadioFrames.selfInfo()],
          Cmd.deviceQuery => [RadioFrames.deviceInfo()],
          Cmd.setDeviceTime => [RadioFrames.ok()],
          Cmd.getContacts => [
            RadioFrames.contactsStart(1),
            RadioFrames.contact(seed: 0x40, name: 'Ann'),
            RadioFrames.endOfContacts(1),
          ],
          Cmd.getChannel => [RadioFrames.err(2)],
          Cmd.syncNextMessage => [RadioFrames.noMore()],
          Cmd.addUpdateContact || Cmd.resetPath => [RadioFrames.ok()],
          _ => [RadioFrames.err(1)],
        };
      },
    );
    final store = MeshStore.memory();
    final app = AppController(store: store, links: _Links(link));
    final c =
        await app.connect(
              const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
            )
            as MeshCoreConnection;
    final id = c.radio!.id;
    final ann = (await store.node(
      id,
      NodeKey.meshcore(toHex(RadioFrames.key(0x40))),
    ))!;
    expect(ann.route, [0xaa, 0xbb]);

    final updated = await c.setRoute(ann, ['c3', 'd4', 'e5']);
    final add = sent.lastWhere((f) => f.first == Cmd.addUpdateContact);
    expect(add.sublist(1, 33), RadioFrames.key(0x40));
    expect(add[35], 3, reason: 'three one-byte hops');
    expect(add.sublist(36, 39), [0xc3, 0xd4, 0xe5]);
    expect(add.sublist(39, 100).every((b) => b == 0), isTrue);
    expect(updated.route, [0xc3, 0xd4, 0xe5]);
    expect((await store.node(id, ann.key))!.route, [0xc3, 0xd4, 0xe5]);
    expect((await store.node(id, ann.key))!.path.hops, 3);

    // Two-byte hops carry their size in the top bits of the length.
    await c.setRoute(updated, ['c3c3', 'd4d4']);
    final two = sent.lastWhere((f) => f.first == Cmd.addUpdateContact);
    expect(two[35], (1 << 6) | 2);
    expect(two.sublist(36, 40), [0xc3, 0xc3, 0xd4, 0xd4]);

    // No hops: forget the route and flood.
    final flood = await c.setRoute(updated, const []);
    expect(sent.last.first, Cmd.resetPath);
    expect(flood.route, isEmpty);
    expect(flood.path.route, RouteKind.flood);

    expect(() => c.setRoute(ann, ['c3', 'd4d4']), throwsArgumentError);
    expect(() => c.setRoute(ann, ['xyz']), throwsArgumentError);

    await app.shutdown();
    await store.close();
  });

  test('route checks', () {
    expect(MeshCoreConnection.validRoute(['A1', 'b2']), [
      [0xa1],
      [0xb2],
    ]);
    expect(
      () => MeshCoreConnection.validRoute(List.filled(64, 'aa')),
      throwsArgumentError,
    );
    expect(
      () => MeshCoreConnection.validRoute(List.filled(22, 'aabbcc')),
      throwsArgumentError,
      reason: '66 bytes is more than the path holds',
    );
  });

  test('saved MeshCore traces keep each hop hash', () async {
    final store = MeshStore.memory();
    final radio = RadioId.meshcore('ab' * 32);
    final target = NodeKey.meshcore('cd' * 32);
    await store.addTrace(
      radio,
      'Ann',
      TraceResult(
        target: target,
        towards: const [TraceHop('Peak', 2.5, hash: 'a1')],
        back: const [TraceHop('Me', 1)],
        time: DateTime(2026, 11, 13),
      ),
    );
    final t = (await store.traces(radio, target)).single.result;
    expect(t.towards.single.hash, 'a1');
    expect(t.back.single.hash, isNull);
    await store.close();
  });
}
