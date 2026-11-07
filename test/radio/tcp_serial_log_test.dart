import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/radio/radio.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

class FakePort implements SerialPortHandle {
  final inputs = StreamController<Uint8List>();
  final written = <Uint8List>[];
  bool closed = false;
  Object? writeError;

  @override
  Stream<Uint8List> get input => inputs.stream;

  @override
  Future<void> write(Uint8List data) async {
    if (writeError != null) throw writeError!;
    written.add(data);
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('TcpRadioLink', () {
    late ServerSocket server;
    late Completer<Socket> accepted;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      accepted = Completer<Socket>();
      server.listen(accepted.complete);
    });

    tearDown(() => server.close());

    test('default ports per protocol', () {
      expect(TcpRadioLink.defaultPort(RadioProtocol.meshcore), 5000);
      expect(TcpRadioLink.defaultPort(RadioProtocol.meshtastic), 4403);
      final l = TcpRadioLink(
        host: 'radio.local',
        protocol: RadioProtocol.meshtastic,
      );
      expect(l.port, 4403);
      expect(l.label, 'radio.local:4403');
      expect(l.deliversFrames, isFalse);
    });

    test(
      'sends and receives bytes, then notices the radio hanging up',
      () async {
        final l = TcpRadioLink(
          host: '127.0.0.1',
          port: server.port,
          protocol: RadioProtocol.meshcore,
        );
        final received = <int>[];
        l.incoming.listen(received.addAll);
        await l.open();
        expect(l.state, LinkState.connected);

        final remote = await accepted.future;
        final fromApp = <int>[];
        remote.listen(fromApp.addAll);

        await l.send(bytes([0x3c, 1, 0, 0x16]));
        remote.add([0x3e, 2, 0, 0x05, 0x01]);
        await remote.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(fromApp, [0x3c, 1, 0, 0x16]);
        expect(received, [0x3e, 2, 0, 0x05, 0x01]);

        await remote.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(l.state, LinkState.disconnected);
      },
    );

    test('a refused connection throws LinkException', () async {
      final log = ConnectionLog();
      final l = TcpRadioLink(
        host: '192.168.7.42',
        protocol: RadioProtocol.meshcore,
        log: log,
        connector: (host, port, timeout) async =>
            throw const SocketException('refused'),
      );
      await expectLater(l.open(), throwsA(isA<LinkException>()));
      expect(l.state, LinkState.disconnected);
      expect(log.export(), contains('192.168.7.x'));
      expect(log.export(), isNot(contains('192.168.7.42')));
    });

    test('close is safe to repeat', () async {
      final l = TcpRadioLink(
        host: '127.0.0.1',
        port: server.port,
        protocol: RadioProtocol.meshtastic,
      );
      await l.open();
      await l.close();
      await l.close();
      expect(l.state, LinkState.disconnected);
    });
  });

  group('SerialRadioLink', () {
    const info = SerialPortInfo(id: '7', name: 'RAK4631');

    test('passes bytes both ways', () async {
      final port = FakePort();
      final l = SerialRadioLink(
        port: info,
        protocol: RadioProtocol.meshtastic,
        opener: (_) async => port,
      );
      final received = <int>[];
      l.incoming.listen(received.addAll);
      await l.open();
      expect(l.kind, LinkKind.usb);
      await l.send(bytes([0x94, 0xc3, 0, 1, 9]));
      port.inputs.add(bytes([0x94, 0xc3]));
      await Future<void>.delayed(Duration.zero);
      expect(port.written.single, bytes([0x94, 0xc3, 0, 1, 9]));
      expect(received, [0x94, 0xc3]);
    });

    test(
      'unplugging marks the link disconnected and closes the port',
      () async {
        final port = FakePort();
        final l = SerialRadioLink(
          port: info,
          protocol: RadioProtocol.meshcore,
          opener: (_) async => port,
        );
        await l.open();
        await port.inputs.close();
        await Future<void>.delayed(Duration.zero);
        expect(l.state, LinkState.disconnected);
        expect(port.closed, isTrue);
      },
    );

    test('open failures become LinkException', () async {
      final l = SerialRadioLink(
        port: info,
        protocol: RadioProtocol.meshcore,
        opener: (_) async => throw StateError('no permission'),
      );
      await expectLater(l.open(), throwsA(isA<LinkException>()));
      expect(l.state, LinkState.disconnected);
    });

    test('write failures become LinkException', () async {
      final port = FakePort()..writeError = StateError('gone');
      final l = SerialRadioLink(
        port: info,
        protocol: RadioProtocol.meshcore,
        opener: (_) async => port,
      );
      await l.open();
      await expectLater(l.send(bytes([1])), throwsA(isA<LinkException>()));
    });
  });

  test('matchUsbDevice finds a replugged radio by vendor and product', () {
    const port = SerialPortInfo(
      id: '7',
      name: 'T-Beam',
      vendorId: 0x1a86,
      productId: 0x55d4,
    );
    expect(
      matchUsbDevice(port, [
        (id: '7', vendorId: 1, productId: 2, value: 'same id'),
      ]),
      'same id',
    );
    expect(
      matchUsbDevice(port, [
        (id: '9', vendorId: 0x1a86, productId: 0x55d4, value: 'replugged'),
        (id: '3', vendorId: 0x10c4, productId: 0xea60, value: 'other'),
      ]),
      'replugged',
    );
    expect(
      matchUsbDevice(port, [
        (id: '9', vendorId: 0x1a86, productId: 0x55d4, value: 'a'),
        (id: '10', vendorId: 0x1a86, productId: 0x55d4, value: 'b'),
      ]),
      isNull,
      reason: 'two identical radios: do not guess',
    );
  });

  group('ConnectionLog', () {
    test('keeps only the newest lines', () {
      final log = ConnectionLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.add('test', 'line $i');
      }
      expect(log.entries.map((e) => e.message), ['line 2', 'line 3', 'line 4']);
    });

    test('export has one line per entry with time and source', () {
      final log = ConnectionLog(
        clock: () => DateTime(2026, 11, 7, 9, 5, 3, 120),
      );
      log.add('BLE Alpha', 'connected');
      expect(log.export(), '09:05:03.120  BLE Alpha  connected');
      log.clear();
      expect(log.export(), isEmpty);
    });

    test('describeBytes never shows the payload', () {
      expect(ConnectionLog.describeBytes(bytes([])), '0 bytes');
      expect(
        ConnectionLog.describeBytes(bytes([0x05, 0xaa, 0xbb])),
        '3 bytes (type 0x05)',
      );
    });

    test('redactHost hides the last part of IPv4 only', () {
      expect(ConnectionLog.redactHost('10.0.0.25'), '10.0.0.x');
      expect(ConnectionLog.redactHost('radio.local'), 'radio.local');
      expect(ConnectionLog.redactHost('1.2.3'), '1.2.3');
    });
  });
}
