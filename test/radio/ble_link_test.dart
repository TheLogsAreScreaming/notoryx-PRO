import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/radio/radio.dart';

import '../support/fake_ble.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeBleBackend backend;
  late ConnectionLog log;

  setUp(() {
    backend = FakeBleBackend();
    log = ConnectionLog();
  });

  BleRadioLink link(BleProfile profile) => BleRadioLink(
    deviceId: 'dev-1',
    name: 'Test radio',
    profile: profile,
    backend: backend,
    log: log,
  );

  group('MeshCore over Bluetooth', () {
    test(
      'connects, subscribes and delivers each notification as a frame',
      () async {
        final l = link(BleProfile.meshcore);
        final received = <Uint8List>[];
        l.incoming.listen(received.add);

        await l.open();
        expect(l.state, LinkState.connected);
        expect(l.deliversFrames, isTrue);
        expect(
          backend.calls,
          contains('subscribe ${BleProfile.meshcore.notify}'),
        );

        backend.notify([0x05, 1, 2]);
        backend.notify([0x06]);
        await settle();
        expect(received, [
          bytes([0x05, 1, 2]),
          bytes([0x06]),
        ]);
        expect(backend.reads, 0);
      },
    );

    test('writes frames to the write characteristic', () async {
      final l = link(BleProfile.meshcore);
      await l.open();
      await l.send(bytes([0x16, 0x03]));
      expect(backend.writes, [
        bytes([0x16, 0x03]),
      ]);
      expect(backend.calls, contains('write ${BleProfile.meshcore.write}'));
    });

    test('a failed MTU request does not stop the connection', () async {
      backend.mtuError = Exception('not supported');
      final l = link(BleProfile.meshcore);
      await l.open();
      expect(l.state, LinkState.connected);
    });
  });

  group('Meshtastic over Bluetooth', () {
    test('drains queued packets after connecting', () async {
      backend.readQueue.addAll([
        bytes([1]),
        bytes([2]),
      ]);
      final l = link(BleProfile.meshtastic);
      final received = <Uint8List>[];
      l.incoming.listen(received.add);

      await l.open();
      await l.drain();
      expect(received, [
        bytes([1]),
        bytes([2]),
      ]);
    });

    test('a FromNum notification triggers reads, not a delivery', () async {
      final l = link(BleProfile.meshtastic);
      final received = <Uint8List>[];
      l.incoming.listen(received.add);
      await l.open();
      await l.drain();

      backend.readQueue.add(bytes([9, 9]));
      backend.notify([0x2a, 0, 0, 0]);
      await settle();
      await l.drain();
      expect(received, [
        bytes([9, 9]),
      ]);
    });

    test('drains after a write so replies are picked up', () async {
      final l = link(BleProfile.meshtastic);
      final received = <Uint8List>[];
      l.incoming.listen(received.add);
      await l.open();
      await l.drain();

      backend.readQueue.add(bytes([7]));
      await l.send(bytes([0x18, 0x01]));
      await l.drain();
      expect(received, [
        bytes([7]),
      ]);
    });

    test('pairs first when the system has no bond', () async {
      backend.paired = false;
      final l = link(BleProfile.meshtastic);
      await l.open();
      expect(backend.pairCalls, 1);
      expect(log.export(), contains('paired'));
      await l.close();
    });

    test('already paired, or MeshCore: no pairing request', () async {
      final l = link(BleProfile.meshtastic);
      await l.open();
      await l.close();
      backend.paired = false;
      final mc = link(BleProfile.meshcore);
      await mc.open();
      expect(backend.pairCalls, 0);
      await mc.close();
    });

    test('looks for packets on its own if no notification comes', () async {
      final l = BleRadioLink(
        deviceId: 'dev-1',
        name: 'Test radio',
        profile: BleProfile.meshtastic,
        backend: backend,
        log: log,
        pollEvery: const Duration(milliseconds: 20),
      );
      final received = <Uint8List>[];
      l.incoming.listen(received.add);
      await l.open();
      await l.drain();
      backend.readQueue.add(bytes([5]));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(received, [
        bytes([5]),
      ]);
      await l.close();
      final before = backend.reads;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(backend.reads, before, reason: 'polling stops on close');
    });

    test('stops after maxDrainReads packets', () async {
      final l = BleRadioLink(
        deviceId: 'dev-1',
        name: 'Busy',
        profile: BleProfile.meshtastic,
        backend: backend,
        maxDrainReads: 3,
        log: log,
      );
      for (var i = 0; i < 10; i++) {
        backend.readQueue.add(bytes([i]));
      }
      await l.open();
      await l.drain();
      expect(backend.reads, 3);
      expect(log.export(), contains('stopped reading after 3 packets'));
    });
  });

  test('fails clearly when the radio lacks the service', () async {
    backend.services = [BleProfile.meshcore.service];
    final l = link(BleProfile.meshtastic);
    await expectLater(
      l.open(),
      throwsA(
        isA<LinkException>().having(
          (e) => e.message,
          'message',
          contains('no Meshtastic Bluetooth service'),
        ),
      ),
    );
    expect(l.state, LinkState.disconnected);
    expect(backend.calls, contains('disconnect dev-1'));
  });

  test('wraps connect errors in LinkException', () async {
    backend.connectError = Exception('timeout');
    final l = link(BleProfile.meshcore);
    await expectLater(l.open(), throwsA(isA<LinkException>()));
    expect(l.state, LinkState.disconnected);
  });

  test('reports a dropped connection', () async {
    final l = link(BleProfile.meshcore);
    final states = <LinkState>[];
    l.states.listen(states.add);
    await l.open();
    backend.dropConnection();
    await settle();
    expect(l.state, LinkState.disconnected);
    expect(states.last, LinkState.disconnected);
    await expectLater(l.send(bytes([1])), throwsA(isA<LinkException>()));
  });

  test('write errors become LinkException', () async {
    final l = link(BleProfile.meshcore);
    await l.open();
    backend.writeError = Exception('gatt 133');
    await expectLater(l.send(bytes([1])), throwsA(isA<LinkException>()));
  });

  test('close disconnects once and is safe to repeat', () async {
    final l = link(BleProfile.meshcore);
    await l.open();
    await l.close();
    await l.close();
    expect(backend.calls.where((c) => c == 'disconnect dev-1'), hasLength(1));
    expect(l.state, LinkState.disconnected);
  });

  test('the log never contains payload bytes', () async {
    final l = link(BleProfile.meshcore);
    await l.open();
    await l.send(bytes([0xde, 0xad, 0xbe, 0xef]));
    final text = log.export().toLowerCase();
    expect(text, isNot(contains('dead')));
    expect(text, contains('connected'));
  });
}
