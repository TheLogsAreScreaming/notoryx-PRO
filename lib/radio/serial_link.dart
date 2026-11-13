import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:usb_serial/usb_serial.dart';

import 'connection_log.dart';
import 'radio_link.dart';

/// An open serial port; [UsbSerialPortHandle] is the Android one.
abstract class SerialPortHandle {
  /// Bytes arriving from the radio.
  Stream<Uint8List> get input;

  /// Sends bytes.
  Future<void> write(Uint8List data);

  /// Closes the port.
  Future<void> close();
}

/// Opens the serial port described by a [SerialPortInfo].
typedef SerialOpener = Future<SerialPortHandle> Function(SerialPortInfo port);

/// A USB serial device that might be a radio.
class SerialPortInfo {
  const SerialPortInfo({
    required this.id,
    required this.name,
    this.vendorId,
    this.productId,
  });

  /// Platform ID used to open the port.
  final String id;

  /// Product or device name to show.
  final String name;

  /// USB vendor ID.
  final int? vendorId;

  /// USB product ID.
  final int? productId;
}

/// A radio plugged in by USB cable.
///
/// MeshCore and Meshtastic both use 115200 baud over USB and send a framed
/// byte stream, so [deliversFrames] is false.
class SerialRadioLink extends BaseRadioLink {
  SerialRadioLink({
    required this.port,
    required this.protocol,
    required SerialOpener opener,
    ConnectionLog? log,
  }) : _opener = opener,
       _log = log;

  /// The port to open.
  final SerialPortInfo port;

  @override
  final RadioProtocol protocol;

  final SerialOpener _opener;
  final ConnectionLog? _log;
  SerialPortHandle? _handle;
  StreamSubscription<Uint8List>? _subscription;

  @override
  LinkKind get kind => LinkKind.usb;

  @override
  String get label => port.name;

  @override
  bool get deliversFrames => false;

  String get _source => 'USB ${port.name}';

  @override
  Future<void> open() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    setState(LinkState.connecting);
    _log?.add(_source, 'opening');
    try {
      final handle = await _opener(port);
      _handle = handle;
      _subscription = handle.input.listen(
        deliver,
        onError: (Object error) {
          _log?.add(_source, 'error: $error');
          _dropped();
        },
        onDone: _dropped,
        cancelOnError: true,
      );
      setState(LinkState.connected);
      _log?.add(_source, 'connected');
    } on Object catch (error) {
      _log?.add(_source, 'open failed: $error');
      setState(LinkState.disconnected);
      throw LinkException('Could not open ${port.name}', error);
    }
  }

  void _dropped() {
    if (state == LinkState.disconnected) return;
    _log?.add(_source, 'unplugged or closed');
    final handle = _handle;
    _teardown();
    setState(LinkState.disconnected);
    unawaited(handle?.close().catchError((Object _) {}));
  }

  @override
  Future<void> send(Uint8List data) async {
    requireConnected();
    try {
      await _handle!.write(data);
    } on Object catch (error) {
      _log?.add(_source, 'write failed: $error');
      throw LinkException('Could not send to ${port.name}', error);
    }
  }

  @override
  Future<void> close() async {
    if (state == LinkState.idle || state == LinkState.disconnected) return;
    _log?.add(_source, 'closing');
    final handle = _handle;
    _teardown();
    setState(LinkState.disconnected);
    try {
      await handle?.close();
    } on Object catch (error) {
      _log?.add(_source, 'close error: $error');
    }
  }

  void _teardown() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _handle = null;
  }
}

/// Picks the device for [port] from [devices]: the same ID if still
/// present, otherwise the only device with the same vendor and product IDs.
T? matchUsbDevice<T>(
  SerialPortInfo port,
  List<({String id, int? vendorId, int? productId, T value})> devices,
) {
  for (final d in devices) {
    if (d.id == port.id) return d.value;
  }
  if (port.vendorId == null || port.productId == null) return null;
  final same = [
    for (final d in devices)
      if (d.vendorId == port.vendorId && d.productId == port.productId) d,
  ];
  return same.length == 1 ? same.single.value : null;
}

/// USB serial ports: on Android through the vendored usb_serial plugin, and
/// on Windows and Mac through libserialport.
class UsbSerialPorts {
  const UsbSerialPorts();

  /// Baud rate used by MeshCore and Meshtastic over USB.
  static const baudRate = 115200;

  /// Whether this platform has USB radio support.
  bool get supported => Platform.isAndroid || _desktop;

  static bool get _desktop => Platform.isWindows || Platform.isMacOS;

  /// Ports plugged in now.
  Future<List<SerialPortInfo>> list() async {
    if (!supported) return const [];
    if (_desktop) return _desktopPorts();
    final devices = await UsbSerial.listDevices();
    return [
      for (final d in devices)
        SerialPortInfo(
          id: '${d.deviceId}',
          name: d.productName ?? d.deviceName,
          vendorId: d.vid,
          productId: d.pid,
        ),
    ];
  }

  /// Opens [port] at [baudRate], 8 data bits, no parity.
  ///
  /// Android gives a replugged device a new ID, so if the old ID is gone the
  /// port is found again by its USB vendor and product IDs.
  Future<SerialPortHandle> open(SerialPortInfo port) async {
    if (_desktop) return _openDesktop(port);
    final devices = await UsbSerial.listDevices();
    final device = matchUsbDevice(port, [
      for (final d in devices)
        (id: '${d.deviceId}', vendorId: d.vid, productId: d.pid, value: d),
    ]);
    if (device == null) throw const LinkException('The radio was unplugged');
    final usb = await device.create();
    if (usb == null || !await usb.open()) {
      throw const LinkException('Android did not allow access to the radio');
    }
    // DTR on and RTS off: some boards reset or stay in the bootloader
    // otherwise.
    await usb.setDTR(true);
    await usb.setRTS(false);
    await usb.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    return UsbSerialPortHandle(usb);
  }
}

/// USB ports the desktop can see. Ports without a USB vendor ID (Bluetooth
/// serial, built-in modems) aren't radios, so they're left out.
List<SerialPortInfo> _desktopPorts() {
  final out = <SerialPortInfo>[];
  for (final name in SerialPort.availablePorts) {
    final p = SerialPort(name);
    try {
      final vid = p.vendorId;
      if (vid == null) continue;
      out.add(
        SerialPortInfo(
          id: name,
          name: '${p.description ?? name} ($name)',
          vendorId: vid,
          productId: p.productId,
        ),
      );
    } on Object {
      // A port that can't be described isn't one we can use.
    } finally {
      p.dispose();
    }
  }
  return out;
}

/// Opens a desktop port by name; after a replug Windows may give it a new
/// name, so it is found again by vendor and product ID.
SerialPortHandle _openDesktop(SerialPortInfo port) {
  final ports = _desktopPorts();
  final match = matchUsbDevice(port, [
    for (final p in ports)
      (id: p.id, vendorId: p.vendorId, productId: p.productId, value: p.id),
  ]);
  if (match == null) throw const LinkException('The radio was unplugged');
  final sp = SerialPort(match);
  if (!sp.openReadWrite()) {
    final error = SerialPort.lastError;
    sp.dispose();
    throw LinkException('Could not open $match', error);
  }
  final config = SerialPortConfig()
    ..baudRate = UsbSerialPorts.baudRate
    ..bits = 8
    ..stopBits = 1
    ..parity = SerialPortParity.none
    // DTR on and RTS off, as on Android: some boards reset otherwise.
    ..dtr = SerialPortDtr.on
    ..rts = SerialPortRts.off;
  try {
    sp.config = config;
  } finally {
    config.dispose();
  }
  return DesktopSerialPortHandle(sp);
}

/// [SerialPortHandle] for a port opened with libserialport.
class DesktopSerialPortHandle implements SerialPortHandle {
  DesktopSerialPortHandle(this._port) : _reader = SerialPortReader(_port);

  final SerialPort _port;
  final SerialPortReader _reader;

  @override
  Stream<Uint8List> get input => _reader.stream;

  @override
  Future<void> write(Uint8List data) async {
    var sent = 0;
    while (sent < data.length) {
      final n = _port.write(Uint8List.sublistView(data, sent), timeout: 2000);
      if (n <= 0) throw const LinkException('Could not write to the radio');
      sent += n;
    }
  }

  @override
  Future<void> close() async {
    _reader.close();
    _port.close();
    _port.dispose();
  }
}

/// [SerialPortHandle] for an Android [UsbPort].
class UsbSerialPortHandle implements SerialPortHandle {
  UsbSerialPortHandle(this._port);

  final UsbPort _port;

  @override
  Stream<Uint8List> get input => _port.inputStream ?? const Stream.empty();

  @override
  Future<void> write(Uint8List data) => _port.write(data);

  @override
  Future<void> close() async {
    await _port.close();
  }
}
