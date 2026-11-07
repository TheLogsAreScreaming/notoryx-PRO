import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// A device seen while scanning.
class BleAdvert {
  const BleAdvert({
    required this.deviceId,
    required this.name,
    required this.services,
    this.rssi,
  });

  /// Platform device ID (a MAC address on Android, a UUID on Apple).
  final String deviceId;

  /// Advertised name, if any.
  final String? name;

  /// Advertised service IDs.
  final List<String> services;

  /// Signal strength in dBm.
  final int? rssi;
}

/// Whether Bluetooth can be used right now.
enum BleAvailability { ready, off, unauthorized, unsupported, unknown }

/// The Bluetooth operations the radio links need.
///
/// [UniversalBleBackend] is the real one; tests supply a fake.
abstract class BleBackend {
  /// Current Bluetooth availability.
  Future<BleAvailability> availability();

  /// Asks for Bluetooth permission where the platform needs it.
  Future<void> requestPermissions();

  /// Devices seen while a scan runs.
  Stream<BleAdvert> get adverts;

  /// Starts scanning. [services] narrows results where supported.
  Future<void> startScan({List<String> services = const []});

  /// Stops scanning.
  Future<void> stopScan();

  /// Connects to [deviceId].
  Future<void> connect(String deviceId, {Duration? timeout});

  /// Disconnects from [deviceId].
  Future<void> disconnect(String deviceId);

  /// Emits false when [deviceId] disconnects.
  Stream<bool> connection(String deviceId);

  /// Discovers services; returns their IDs.
  Future<List<String>> discoverServices(String deviceId);

  /// Asks for a larger packet size; returns the size granted.
  Future<int> requestMtu(String deviceId, int mtu);

  /// Turns on notifications for a characteristic.
  Future<void> subscribe(String deviceId, String service, String char);

  /// Values notified on a characteristic.
  Stream<Uint8List> values(String deviceId, String char);

  /// Reads a characteristic.
  Future<Uint8List> read(String deviceId, String service, String char);

  /// Writes a characteristic, waiting for the radio's acknowledgement.
  Future<void> write(
    String deviceId,
    String service,
    String char,
    Uint8List value,
  );
}

/// [BleBackend] on top of the universal_ble plugin.
class UniversalBleBackend implements BleBackend {
  const UniversalBleBackend();

  @override
  Future<BleAvailability> availability() async {
    final state = await UniversalBle.getBluetoothAvailabilityState();
    return switch (state) {
      AvailabilityState.poweredOn => BleAvailability.ready,
      AvailabilityState.poweredOff => BleAvailability.off,
      AvailabilityState.unauthorized => BleAvailability.unauthorized,
      AvailabilityState.unsupported => BleAvailability.unsupported,
      AvailabilityState.unknown ||
      AvailabilityState.resetting => BleAvailability.unknown,
    };
  }

  @override
  Future<void> requestPermissions() => UniversalBle.requestPermissions();

  @override
  Stream<BleAdvert> get adverts => UniversalBle.scanStream.map(
    (d) => BleAdvert(
      deviceId: d.deviceId,
      name: d.name,
      services: d.services,
      rssi: d.rssi,
    ),
  );

  @override
  Future<void> startScan({List<String> services = const []}) =>
      UniversalBle.startScan(
        scanFilter: services.isEmpty
            ? null
            : ScanFilter(withServices: services),
      );

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId, {Duration? timeout}) =>
      UniversalBle.connect(
        deviceId,
        timeout: timeout ?? const Duration(seconds: 20),
      );

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Stream<bool> connection(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Future<List<String>> discoverServices(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);
    return [for (final s in services) s.uuid];
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) =>
      UniversalBle.requestMtu(deviceId, mtu);

  @override
  Future<void> subscribe(String deviceId, String service, String char) =>
      UniversalBle.subscribeNotifications(deviceId, service, char);

  @override
  Stream<Uint8List> values(String deviceId, String char) =>
      UniversalBle.characteristicValueStream(deviceId, char);

  @override
  Future<Uint8List> read(String deviceId, String service, String char) =>
      UniversalBle.read(deviceId, service, char);

  @override
  Future<void> write(
    String deviceId,
    String service,
    String char,
    Uint8List value,
  ) => UniversalBle.write(deviceId, service, char, value);
}
