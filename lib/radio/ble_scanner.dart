import 'dart:async';

import 'ble_backend.dart';
import 'ble_profiles.dart';
import 'radio_link.dart';

/// A Bluetooth device found by [BleRadioScanner].
class FoundRadio {
  const FoundRadio({
    required this.deviceId,
    required this.name,
    required this.protocol,
    this.rssi,
  });

  /// Platform device ID.
  final String deviceId;

  /// Advertised name, or the device ID when it has none.
  final String name;

  /// Which protocol it speaks; null if unknown (shown only with "show all").
  final RadioProtocol? protocol;

  /// Signal strength in dBm.
  final int? rssi;
}

/// Why a scan can't run.
class ScanUnavailable implements Exception {
  const ScanUnavailable(this.availability);

  /// The Bluetooth state that stopped the scan.
  final BleAvailability availability;

  /// Text to show people.
  String get message => switch (availability) {
    BleAvailability.off => 'Bluetooth is turned off.',
    BleAvailability.unauthorized =>
      'NOTORYX PRO needs Bluetooth permission to find radios.',
    BleAvailability.unsupported => "This device doesn't support Bluetooth LE.",
    BleAvailability.unknown || BleAvailability.ready =>
      "Bluetooth isn't ready yet. Try again in a moment.",
  };

  @override
  String toString() => 'ScanUnavailable: $message';
}

/// Finds MeshCore and Meshtastic radios over Bluetooth.
///
/// Scans without a service filter, because some radios don't advertise their
/// service, and sorts each device with [classifyAdvertisement].
class BleRadioScanner {
  BleRadioScanner(this._backend);

  final BleBackend _backend;

  /// Scans for [duration] and emits every radio found, updated as their
  /// signal changes. Devices that aren't recognised as either protocol are
  /// included only when [showAll] is true.
  Stream<List<FoundRadio>> scan({
    Duration duration = const Duration(seconds: 15),
    bool showAll = false,
  }) {
    late final StreamController<List<FoundRadio>> controller;
    StreamSubscription<BleAdvert>? sub;
    Timer? timer;
    final found = <String, FoundRadio>{};

    Future<void> finish() async {
      timer?.cancel();
      await sub?.cancel();
      sub = null;
      try {
        await _backend.stopScan();
      } on Object catch (_) {
        // Already stopped.
      }
      if (!controller.isClosed) unawaited(controller.close());
    }

    controller = StreamController<List<FoundRadio>>(
      onListen: () async {
        try {
          var availability = await _backend.availability();
          if (availability == BleAvailability.unauthorized) {
            await _backend.requestPermissions();
            availability = await _backend.availability();
          }
          if (availability != BleAvailability.ready) {
            throw ScanUnavailable(availability);
          }
          sub = _backend.adverts.listen((advert) {
            final protocol = classifyAdvertisement(
              services: advert.services,
              name: advert.name,
            );
            if (protocol == null && !showAll) return;
            final name = (advert.name ?? '').isEmpty
                ? advert.deviceId
                : advert.name!;
            found[advert.deviceId] = FoundRadio(
              deviceId: advert.deviceId,
              name: name,
              protocol: protocol,
              rssi: advert.rssi,
            );
            controller.add(sortRadios(found.values));
          });
          await _backend.startScan();
          timer = Timer(duration, () => unawaited(finish()));
        } on Object catch (error, stack) {
          controller.addError(error, stack);
          await finish();
        }
      },
      onCancel: finish,
    );
    return controller.stream;
  }
}

/// Known radios first, then strongest signal first, then by name.
List<FoundRadio> sortRadios(Iterable<FoundRadio> radios) {
  final list = List.of(radios);
  list.sort((a, b) {
    final known = (a.protocol == null ? 1 : 0) - (b.protocol == null ? 1 : 0);
    if (known != 0) return known;
    final signal = (b.rssi ?? -999) - (a.rssi ?? -999);
    if (signal != 0) return signal;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}
