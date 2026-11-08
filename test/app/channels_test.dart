import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/channels_screen.dart';

import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

/// A MeshCore companion with four channel slots.
class ChannelCompanion {
  final slots = List<(String, Uint8List)>.generate(
    4,
    (_) => ('', Uint8List(16)),
  );

  ChannelCompanion() {
    slots[0] = ('Public', bytesOfHex(meshCorePublicKeyHex));
  }

  Uint8List info(int i) =>
      (ByteWriter()
            ..u8(18)
            ..u8(i)
            ..fixedString(slots[i].$1, 32)
            ..bytes(slots[i].$2))
          .toBytes();

  List<Uint8List> call(Uint8List cmd) => switch (cmd.first) {
    Cmd.appStart => [RadioFrames.selfInfo()],
    Cmd.deviceQuery => [
      () {
        final d = RadioFrames.deviceInfo();
        d[3] = 4; // channel slots
        return d;
      }(),
    ],
    Cmd.setDeviceTime => [RadioFrames.ok()],
    Cmd.getContacts => [
      RadioFrames.contactsStart(0),
      RadioFrames.endOfContacts(0),
    ],
    Cmd.getChannel => [cmd[1] < 4 ? info(cmd[1]) : RadioFrames.err(2)],
    Cmd.setChannel => () {
      final name = utf8.decode(
        cmd.sublist(2, 34).takeWhile((b) => b != 0).toList(),
      );
      slots[cmd[1]] = (name, Uint8List.fromList(cmd.sublist(34, 50)));
      return [RadioFrames.ok()];
    }(),
    Cmd.syncNextMessage => [RadioFrames.noMore()],
    _ => [RadioFrames.err(1)],
  };
}

void main() {
  group('links', () {
    test('hashtag channels take their key from the name', () {
      final c = ChannelInvite.hashtag('hiking');
      expect(c.name, '#hiking');
      expect(hexOf(c.secret), '2370a013053e384e5f18918bc2b26baf');
      expect(c.isHashtag, isTrue);
      expect(
        ChannelInvite.private(RadioProtocol.meshcore, 'x').isHashtag,
        isFalse,
      );
    });

    test('MeshCore: the docs example and a round trip', () {
      final docs = ChannelInvite.parse(
        'meshcore://channel/add?name=Public&secret=8b3387e9c5cdea6ac9e5edbaa115cd72',
      ).single;
      expect(docs.protocol, RadioProtocol.meshcore);
      expect(hexOf(docs.secret), meshCorePublicKeyHex);
      final mine = ChannelInvite.private(RadioProtocol.meshcore, 'Base & Co');
      expect(mine.secret, hasLength(16));
      final back = ChannelInvite.parse(mine.toLink()).single;
      expect(back.name, 'Base & Co');
      expect(back.secret, mine.secret);
    });

    test('Meshtastic: a round trip and several channels in one link', () {
      final mine = ChannelInvite.private(RadioProtocol.meshtastic, 'Trail');
      expect(mine.secret, hasLength(32));
      final link = mine.toLink();
      expect(link, startsWith('https://meshtastic.org/e/?add=true#'));
      final back = ChannelInvite.parse('Join us: $link').single;
      expect(back.name, mine.name);
      expect(back.secret, mine.secret);

      final set = ProtoWriter()
        ..bytes(
          1,
          (ProtoWriter()
                ..bytes(2, [1])
                ..string(3, 'A'))
              .toBytes(),
        )
        ..bytes(1, (ProtoWriter()..string(3, 'B')).toBytes())
        ..bytes(2, [8, 1]); // LoRa settings, ignored
      final two = ChannelInvite.parse(
        'https://meshtastic.org/e/#${base64Url.encode(set.toBytes()).replaceAll('=', '')}',
      );
      expect(two.map((c) => c.name), ['A', 'B']);
      expect(two.first.secret, [1]);
    });

    test('anything else is not a channel', () {
      expect(ChannelInvite.parse('https://example.com'), isEmpty);
      expect(
        ChannelInvite.parse('meshcore://channel/add?name=x&secret=ab'),
        isEmpty,
      );
      expect(ChannelInvite.parse('https://meshtastic.org/e/#!!!'), isEmpty);
    });
  });

  test('MeshCore: join in the first free slot, once; leave', () async {
    final store = MeshStore.memory();
    final radio = ChannelCompanion();
    final app = AppController(
      store: store,
      links: FakeLinks(ScriptedMeshCoreLink(responder: radio.call)),
    );
    final c = await app.connect(
      const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
    );
    final hike = ChannelInvite.hashtag('hiking');
    expect(await c.addChannel(hike), 1);
    expect(await c.addChannel(hike), 1, reason: 'already joined');
    expect(radio.slots[1].$1, '#hiking');
    expect((await store.channels(c.radio!.id)).map((ch) => ch.name), [
      'Public',
      '#hiking',
    ]);
    expect((await c.channelSlots()).map((s) => s.invite.isHashtag), [
      false,
      true,
    ]);
    await c.addChannel(ChannelInvite.private(RadioProtocol.meshcore, 'a'));
    await c.addChannel(ChannelInvite.private(RadioProtocol.meshcore, 'b'));
    await expectLater(
      c.addChannel(ChannelInvite.private(RadioProtocol.meshcore, 'c')),
      throwsA(isA<ChannelsFull>()),
    );
    await c.removeChannel(1);
    expect(radio.slots[1].$2, Uint8List(16));
    expect(
      (await store.channels(c.radio!.id)).map((ch) => ch.name),
      isNot(contains('#hiking')),
    );
    await app.shutdown();
    await store.close();
  });

  test(
    'Meshtastic: join as a secondary channel, leave, keep primary',
    () async {
      final store = MeshStore.memory();
      final link = ScriptedMeshtasticLink();
      final node = FakeAdminNode(link.myNode);
      link.onPacket = (p) => node(p, myNode: link.myNode);
      final app = AppController(store: store, links: FakeLinks(link));
      final c = await app.connect(
        const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
      );
      final invite = ChannelInvite.private(RadioProtocol.meshtastic, 'Camp');
      expect(await c.addChannel(invite), 2, reason: '0 and 1 in use');
      await pumpEventQueue();
      final sent = node.received.where((r) => r.$1 == AdminField.setChannel);
      final ch = MeshChannel.decode(sent.single.$2);
      expect(ch.index, 2);
      expect(ch.role, ChannelRole.secondary);
      expect(ch.name, 'Camp');
      expect(ch.psk, invite.secret);
      expect(sent.single.$3, node.passkey);
      expect(
        (await store.channels(c.radio!.id)).map((x) => x.name),
        containsAll(['Primary', 'Trail', 'Camp']),
      );
      expect(await c.addChannel(invite), 2, reason: 'already joined');

      await c.removeChannel(2);
      await pumpEventQueue();
      final off = MeshChannel.decode(
        node.received.lastWhere((r) => r.$1 == AdminField.setChannel).$2,
      );
      expect((off.index, off.role), (2, ChannelRole.disabled));
      expect(() => c.removeChannel(0), throwsArgumentError);
      await app.shutdown();
      await store.close();
    },
  );

  testWidgets('screen: list, join from a pasted link, leave', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MeshStore.memory();
    final radio = ChannelCompanion();
    final app = AppController(
      store: store,
      links: FakeLinks(ScriptedMeshCoreLink(responder: radio.call)),
    );
    final c = (await tester.runAsync(
      () => app.connect(
        const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
      ),
    ))!;
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChannelsScreen(connection: c),
      ),
    );
    await settle();
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Open to everyone'), findsOneWidget);

    await tester.tap(find.text('Join from a link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('channel-link')),
      ChannelInvite.hashtag('ridge').toLink(),
    );
    await tester.tap(find.text('Add'));
    await settle();
    expect(find.text('#ridge'), findsOneWidget);
    expect(radio.slots[1].$1, '#ridge');

    await tester.tap(find.byTooltip('Leave').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave').last);
    await settle();
    expect(find.text('#ridge'), findsNothing);
    expect(radio.slots[1].$1, '');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(app.shutdown);
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });
}
