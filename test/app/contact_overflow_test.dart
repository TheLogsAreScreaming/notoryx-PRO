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

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

/// A companion that holds two contacts.
class FullCompanion {
  final commands = <int>[];
  final removed = <String>[];
  final added = <String>[];

  List<Uint8List> call(Uint8List cmd) {
    commands.add(cmd.first);
    return switch (cmd.first) {
      Cmd.appStart => [RadioFrames.selfInfo()],
      Cmd.deviceQuery => [RadioFrames.deviceInfo(maxContacts: 2)],
      Cmd.setDeviceTime => [RadioFrames.ok()],
      Cmd.getContacts => [
        RadioFrames.contactsStart(2),
        RadioFrames.contact(
          seed: 0xa1,
          name: 'Peak',
          type: 2,
          flags: 0,
          lastAdvert: 1762000000, // oldest, but a repeater
        ),
        RadioFrames.contact(
          seed: 0xb2,
          name: 'Ann',
          flags: 0,
          lastAdvert: 1762400000,
        ),
        RadioFrames.endOfContacts(2),
      ],
      Cmd.getChannel => [RadioFrames.err(2)],
      Cmd.syncNextMessage => [RadioFrames.noMore()],
      Cmd.removeContact => () {
        removed.add(toHex(cmd.sublist(1, 33)));
        return [RadioFrames.ok()];
      }(),
      Cmd.addUpdateContact => () {
        added.add(toHex(cmd.sublist(1, 33)));
        return [RadioFrames.ok()];
      }(),
      Cmd.sendText => [RadioFrames.sent(ack: 7)],
      _ => [RadioFrames.err(1)],
    };
  }
}

void main() {
  test('add-contact command layout', () {
    final f = MeshCoreCommands.addUpdateContact(
      publicKey: RadioFrames.key(0x10),
      type: 1,
      name: 'Cara',
      lastAdvert: 0x01020304,
      latitude: 1.5,
      longitude: -2.25,
    );
    expect(f.length, 1 + 32 + 1 + 1 + 1 + 64 + 32 + 4 + 4 + 4);
    expect(f[0], Cmd.addUpdateContact);
    expect(f.sublist(1, 33), RadioFrames.key(0x10));
    expect(f[33], 1, reason: 'type');
    expect(f[35], 0xff, reason: 'no known path: flood');
    expect(String.fromCharCodes(f.sublist(100, 104)), 'Cara');
    final d = ByteData.sublistView(f);
    expect(d.getUint32(132, Endian.little), 0x01020304);
    expect(d.getInt32(136, Endian.little), 1500000);
    expect(d.getInt32(140, Endian.little), -2250000);
    // Long names are cut to fit, on a character boundary.
    final long = MeshCoreCommands.addUpdateContact(
      publicKey: RadioFrames.key(1),
      type: 1,
      name: 'é' * 20,
    );
    expect(long.sublist(100, 132).where((b) => b != 0).length, 30);
  });

  test('a node not on a full radio swaps in for the least needed', () async {
    final store = MeshStore.memory();
    final radio = FullCompanion();
    final link = ScriptedMeshCoreLink(responder: radio.call);
    final app = AppController(store: store, links: FakeLinks(link));
    final c =
        await app.connect(
              const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
            )
            as MeshCoreConnection;
    final id = c.radio!.id;
    expect(c.maxContacts, 2);
    final peak = NodeKey.meshcore(toHex(RadioFrames.key(0xa1)));
    final ann = NodeKey.meshcore(toHex(RadioFrames.key(0xb2)));
    final cara = NodeKey.meshcore(toHex(RadioFrames.key(0xc3)));
    expect(await store.radioContacts(id), {peak, ann});

    // Heard advertising, but the radio is full: the app keeps her.
    link.push(
      RadioFrames.contact(code: 0x8a, seed: 0xc3, name: 'Cara', flags: 0),
    );
    Node? n;
    for (var i = 0; i < 50 && n == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      n = await store.node(id, cara);
    }
    expect(n!.name, 'Cara');
    expect((await store.radioContacts(id)).contains(cara), isFalse);

    await c.sendText(DirectConversation(id, cara), 'hi Cara');
    // Ann (a person, heard less recently than nobody else but Peak, who is
    // a repeater) makes room.
    expect(radio.removed, [ann.native]);
    expect(radio.added, [cara.native]);
    final order = radio.commands.skipWhile((x) => x != Cmd.removeContact);
    expect(order.take(3), [
      Cmd.removeContact,
      Cmd.addUpdateContact,
      Cmd.sendText,
    ]);
    expect(await store.radioContacts(id), {peak, cara});
    expect(await store.node(id, ann), isNotNull, reason: 'the app keeps Ann');

    // Messaging someone already on the radio adds nothing.
    await c.sendText(DirectConversation(id, peak), 'ping');
    expect(radio.added, hasLength(1));

    // The radio deleting a contact is noticed.
    link.push(Uint8List.fromList([0x8f, ...RadioFrames.key(0xa1)]));
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!(await store.radioContacts(id)).contains(peak)) break;
    }
    expect(await store.radioContacts(id), {cara});

    await app.shutdown();
    await store.close();
  });
}
