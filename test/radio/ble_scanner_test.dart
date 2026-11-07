import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/radio/radio.dart';

import '../support/fake_ble.dart';

/// Lets the scanner's async setup run.
Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('classifyAdvertisement', () {
    test('uses advertised services first', () {
      expect(
        classifyAdvertisement(
          services: [BleProfile.meshtastic.service.toUpperCase()],
          name: 'MeshCore-Confusing',
        ),
        RadioProtocol.meshtastic,
      );
      expect(
        classifyAdvertisement(services: [BleProfile.meshcore.service]),
        RadioProtocol.meshcore,
      );
    });

    test('falls back to the default names', () {
      expect(
        classifyAdvertisement(services: [], name: 'MeshCore-Ridge'),
        RadioProtocol.meshcore,
      );
      expect(
        classifyAdvertisement(services: [], name: 'Meshtastic_3f2a'),
        RadioProtocol.meshtastic,
      );
      expect(classifyAdvertisement(services: [], name: 'Headphones'), isNull);
      expect(classifyAdvertisement(services: ['180f']), isNull);
    });
  });

  test('normalizeUuid expands short IDs', () {
    expect(normalizeUuid('180F'), '0000180f-0000-1000-8000-00805f9b34fb');
    expect(normalizeUuid('0000180f'), '0000180f-0000-1000-8000-00805f9b34fb');
    expect(
      normalizeUuid(BleProfile.meshcore.service.toUpperCase()),
      BleProfile.meshcore.service,
    );
  });

  test('sortRadios puts known, strong radios first', () {
    final sorted = sortRadios([
      const FoundRadio(
        deviceId: 'a',
        name: 'Unknown',
        protocol: null,
        rssi: -30,
      ),
      const FoundRadio(
        deviceId: 'b',
        name: 'Far',
        protocol: RadioProtocol.meshcore,
        rssi: -90,
      ),
      const FoundRadio(
        deviceId: 'c',
        name: 'Near',
        protocol: RadioProtocol.meshtastic,
        rssi: -40,
      ),
    ]);
    expect(sorted.map((r) => r.deviceId), ['c', 'b', 'a']);
  });

  group('BleRadioScanner', () {
    late FakeBleBackend backend;

    setUp(() => backend = FakeBleBackend());

    test('finds both kinds of radio and hides others', () async {
      final scanner = BleRadioScanner(backend);
      final results = <List<FoundRadio>>[];
      final sub = scanner.scan().listen(results.add);
      await flush();
      expect(backend.scanning, isTrue);

      backend.advertise(
        const BleAdvert(
          deviceId: '1',
          name: 'MeshCore-Alpha',
          services: [],
          rssi: -60,
        ),
      );
      backend.advertise(
        BleAdvert(
          deviceId: '2',
          name: 'Base',
          services: [BleProfile.meshtastic.service],
          rssi: -50,
        ),
      );
      backend.advertise(
        const BleAdvert(deviceId: '3', name: 'Watch', services: [], rssi: -20),
      );
      await flush();

      final last = results.last;
      expect(last.map((r) => r.name), ['Base', 'MeshCore-Alpha']);
      expect(last.first.protocol, RadioProtocol.meshtastic);

      await sub.cancel();
      expect(backend.scanning, isFalse);
    });

    test('showAll includes unrecognised devices', () async {
      final scanner = BleRadioScanner(backend);
      final results = <List<FoundRadio>>[];
      final sub = scanner.scan(showAll: true).listen(results.add);
      await flush();
      backend.advertise(
        const BleAdvert(deviceId: 'x', name: null, services: [], rssi: -70),
      );
      await flush();
      expect(results.last.single.name, 'x');
      expect(results.last.single.protocol, isNull);
      await sub.cancel();
    });

    test('stops by itself after the duration', () async {
      final scanner = BleRadioScanner(backend);
      final done = Completer<void>();
      scanner
          .scan(duration: const Duration(milliseconds: 20))
          .listen((_) {}, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 2));
      expect(backend.scanning, isFalse);
    });

    test('reports Bluetooth turned off', () async {
      backend.state = BleAvailability.off;
      final scanner = BleRadioScanner(backend);
      await expectLater(
        scanner.scan(),
        emitsError(
          isA<ScanUnavailable>().having(
            (e) => e.message,
            'message',
            contains('turned off'),
          ),
        ),
      );
      expect(backend.calls, isNot(contains('startScan')));
    });

    test('asks for permission once, then scans', () async {
      backend.state = BleAvailability.unauthorized;
      backend.stateAfterPermission = BleAvailability.ready;
      final scanner = BleRadioScanner(backend);
      final sub = scanner.scan().listen((_) {});
      await flush();
      expect(backend.calls, ['requestPermissions', 'startScan']);
      await sub.cancel();
    });
  });
}
