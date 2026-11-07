import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

import '../support/scripted_meshcore.dart';

/// Answers like a v1.18 companion with a small queue of messages.
List<Uint8List> Function(Uint8List) companion({
  List<Uint8List>? queued,
  bool clockAhead = false,
}) {
  final inbox = [...?queued];
  return (cmd) => switch (cmd.first) {
    Cmd.appStart => [RadioFrames.selfInfo()],
    Cmd.deviceQuery => [RadioFrames.deviceInfo()],
    Cmd.setDeviceTime => [clockAhead ? RadioFrames.err(6) : RadioFrames.ok()],
    Cmd.getContacts => [
      RadioFrames.contactsStart(2),
      RadioFrames.contact(seed: 1, name: 'A', lastModified: 10),
      RadioFrames.contact(code: 0x8a, seed: 9, name: 'Stranger'),
      RadioFrames.contact(seed: 2, name: 'B', lastModified: 20),
      RadioFrames.endOfContacts(20),
    ],
    Cmd.getChannel => [
      if (cmd[1] < 2)
        Uint8List.fromList([18, cmd[1], ...List.filled(48, cmd[1] + 1)])
      else
        RadioFrames.err(2),
    ],
    Cmd.sendText => [RadioFrames.sent(ack: 77)],
    Cmd.sendChannelText => [RadioFrames.ok()],
    Cmd.syncNextMessage => [
      inbox.isEmpty ? RadioFrames.noMore() : inbox.removeAt(0),
    ],
    _ => [RadioFrames.err(1)],
  };
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final framed in [true, false]) {
    group(framed ? 'over Bluetooth' : 'over USB/TCP', () {
      late ScriptedMeshCoreLink link;
      late MeshCoreSession session;

      setUp(() async {
        link = ScriptedMeshCoreLink(framed: framed, responder: companion());
        await link.open();
        session = MeshCoreSession(
          link,
          timeout: const Duration(milliseconds: 200),
          clock: () => DateTime.utc(2026, 11, 7),
        );
      });

      tearDown(() => session.dispose());

      test('handshake reads identity, device and sets the clock', () async {
        final h = await session.handshake();
        expect(h.self.name, 'Ridge Base');
        expect(h.device.maxChannels, 40);
        expect(h.clockSet, isTrue);
        expect(link.commands.map((c) => c.first), [
          Cmd.appStart,
          Cmd.deviceQuery,
          Cmd.setDeviceTime,
        ]);
        final secs = DateTime.utc(2026, 11, 7).millisecondsSinceEpoch ~/ 1000;
        expect(link.commands.last, MeshCoreCommands.setDeviceTime(secs));
        if (!framed) {
          for (final r in link.raw) {
            ScriptedMeshCoreLink.expectWrapped(r);
          }
        }
      });

      test('contact sync collects contacts and passes pushes on', () async {
        final pushes = <MeshCoreFrame>[];
        session.pushes.listen(pushes.add);
        final sync = await session.getContacts();
        expect(sync.contacts.map((c) => c.name), ['A', 'B']);
        expect(sync.total, 2);
        expect(sync.lastModified, 20);
        await settle();
        expect(pushes.whereType<ContactFrame>().single.name, 'Stranger');
      });
    });
  }

  group('session behaviour', () {
    late ScriptedMeshCoreLink link;
    late MeshCoreSession session;

    Future<void> start({
      List<Uint8List>? queued,
      Responder? responder,
      bool clockAhead = false,
    }) async {
      link = ScriptedMeshCoreLink(
        responder:
            responder ?? companion(queued: queued, clockAhead: clockAhead),
      );
      await link.open();
      session = MeshCoreSession(
        link,
        timeout: const Duration(milliseconds: 100),
      );
    }

    tearDown(() => session.dispose());

    test(
      'firmware older than protocol 3 is refused before any write',
      () async {
        await start(
          responder: (cmd) => switch (cmd.first) {
            Cmd.appStart => [RadioFrames.selfInfo()],
            Cmd.deviceQuery => [
              Uint8List.fromList([13, 2]),
            ],
            _ => [RadioFrames.ok()],
          },
        );
        await expectLater(
          session.handshake(),
          throwsA(
            isA<UnsupportedFirmware>()
                .having((e) => e.found, 'found', 2)
                .having((e) => e.message, 'message', contains('too old')),
          ),
        );
        expect(link.commands.map((c) => c.first), [
          Cmd.appStart,
          Cmd.deviceQuery,
        ]);
      },
    );

    test('features are gated by protocol code', () async {
      await start();
      expect(
        () => session.requireFeature(MeshCoreFeature.stats),
        throwsA(isA<UnsupportedFirmware>()),
        reason: 'unknown before the handshake',
      );
      await session.handshake();
      expect(session.firmwareCode, 14);
      session.requireFeature(MeshCoreFeature.companionCli);
      expect(
        MeshCoreFirmware.supports(8, MeshCoreFeature.companionCli),
        isFalse,
      );
      expect(
        const UnsupportedFirmware(
          found: 8,
          needed: 14,
          version: 'v1.11.0',
          feature: MeshCoreFeature.companionCli,
        ).message,
        'Radio command line needs newer MeshCore firmware than v1.11.0.',
      );
    });

    test('a radio clock ahead of the phone is not an error', () async {
      await start(clockAhead: true);
      final h = await session.handshake();
      expect(h.clockSet, isFalse);
    });

    test('commands go out one at a time', () async {
      final held = <Uint8List>[];
      await start(
        responder: (cmd) {
          held.add(cmd);
          return const [];
        },
      );
      final first = session.battery();
      final second = session.getTime();
      await settle();
      expect(held.length, 1, reason: 'second waits for the first reply');

      link.push(Uint8List.fromList([12, 0x10, 0x0e]));
      expect((await first).millivolts, 3600);
      await settle();
      expect(held.length, 2);

      link.push(Uint8List.fromList([9, 0, 0, 0, 0x69]));
      expect((await second).year, greaterThan(2020));
    });

    test('a timeout fails that command and the queue moves on', () async {
      var calls = 0;
      await start(
        responder: (cmd) {
          calls++;
          if (cmd.first == Cmd.getBattAndStorage) return const [];
          return [RadioFrames.selfInfo()];
        },
      );
      final slow = session.battery();
      final next = session.appStart();
      await expectLater(slow, throwsA(isA<MeshCoreTimeout>()));
      expect((await next).name, 'Ridge Base');
      expect(calls, 2);
    });

    test('ERR becomes MeshCoreException', () async {
      await start(responder: (_) => [RadioFrames.err(3)]);
      await expectLater(
        session.sendText(publicKey: RadioFrames.key(1), text: 'x'),
        throwsA(
          isA<MeshCoreException>().having(
            (e) => e.code,
            'code',
            MeshCoreErrorCode.tableFull,
          ),
        ),
      );
    });

    test('direct send returns the ack code to watch for', () async {
      await start();
      final confirmations = <SendConfirmedPush>[];
      session.pushes
          .where((f) => f is SendConfirmedPush)
          .cast<SendConfirmedPush>()
          .listen(confirmations.add);
      final sent = await session.sendText(
        publicKey: RadioFrames.key(1),
        text: 'hello',
      );
      expect(sent.ackCode, 77);
      link.push(RadioFrames.sendConfirmed(77));
      await settle();
      expect(confirmations.single.ackCode, 77);
    });

    test('channel send accepts OK', () async {
      await start();
      await session.sendChannelText(channel: 0, text: 'hello');
      expect(link.commands.single.first, Cmd.sendChannelText);
    });

    test('channels stop at the first missing slot', () async {
      await start();
      final channels = await session.getChannels(8);
      expect(channels.map((c) => c.index), [0, 1]);
    });

    test('MSG_WAITING fetches every queued message', () async {
      await start(
        queued: [
          RadioFrames.channelMessageV3(text: 'Bob: one'),
          RadioFrames.contactMessageV3(text: 'two'),
        ],
      );
      final got = <MeshCoreFrame>[];
      session.messages.listen(got.add);
      session.attach();
      link.push(RadioFrames.waiting());
      await settle();
      expect(got, hasLength(2));
      expect((got[0] as ChannelMessageFrame).body, 'one');
      expect((got[1] as ContactMessageFrame).text, 'two');
      expect(
        link.commands.where((c) => c.first == Cmd.syncNextMessage),
        hasLength(3),
      );
    });

    test('a disconnect fails waiting commands', () async {
      await start(responder: (_) => const []);
      final pending = session.battery();
      final queued = session.getTime();
      await settle();
      await link.close();
      await expectLater(pending, throwsA(isA<LinkException>()));
      await expectLater(queued, throwsA(isA<LinkException>()));
    });

    test('a reply with nothing waiting goes to pushes', () async {
      await start();
      session.attach();
      final pushes = <MeshCoreFrame>[];
      session.pushes.listen(pushes.add);
      link.push(RadioFrames.ok());
      await settle();
      expect(pushes.single, isA<OkFrame>());
    });
  });
}
