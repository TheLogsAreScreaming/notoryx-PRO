import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:notoryx_pro/radio/radio.dart';

/// A scripted [BleBackend] for tests.
class FakeBleBackend implements BleBackend {
  BleAvailability state = BleAvailability.ready;
  BleAvailability? stateAfterPermission;
  List<String> services = [
    BleProfile.meshcore.service,
    BleProfile.meshtastic.service,
  ];
  Object? connectError;
  Object? mtuError;
  Object? writeError;

  /// Packets returned by successive reads; empty means "nothing queued".
  final Queue<Uint8List> readQueue = Queue<Uint8List>();
  final List<Uint8List> writes = [];
  final List<String> calls = [];
  int reads = 0;
  bool scanning = false;

  final _adverts = StreamController<BleAdvert>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final _values = StreamController<Uint8List>.broadcast();

  void advertise(BleAdvert advert) => _adverts.add(advert);
  void notify(List<int> bytes) => _values.add(Uint8List.fromList(bytes));
  void dropConnection() => _connection.add(false);

  @override
  Future<BleAvailability> availability() async => state;

  @override
  Future<void> requestPermissions() async {
    calls.add('requestPermissions');
    if (stateAfterPermission != null) state = stateAfterPermission!;
  }

  @override
  Stream<BleAdvert> get adverts => _adverts.stream;

  @override
  Future<void> startScan({List<String> services = const []}) async {
    calls.add('startScan');
    scanning = true;
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
    scanning = false;
  }

  @override
  Future<void> connect(String deviceId, {Duration? timeout}) async {
    calls.add('connect $deviceId');
    if (connectError != null) throw connectError!;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect $deviceId');
  }

  @override
  Stream<bool> connection(String deviceId) => _connection.stream;

  @override
  Future<List<String>> discoverServices(String deviceId) async => services;

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    if (mtuError != null) throw mtuError!;
    return mtu;
  }

  @override
  Future<void> subscribe(String deviceId, String service, String char) async {
    calls.add('subscribe $char');
  }

  @override
  Stream<Uint8List> values(String deviceId, String char) => _values.stream;

  @override
  Future<Uint8List> read(String deviceId, String service, String char) async {
    reads++;
    return readQueue.isEmpty ? Uint8List(0) : readQueue.removeFirst();
  }

  @override
  Future<void> write(
    String deviceId,
    String service,
    String char,
    Uint8List value,
  ) async {
    if (writeError != null) throw writeError!;
    calls.add('write $char');
    writes.add(value);
  }
}
