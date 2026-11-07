import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

/// Opens a serial port by its [SerialPortInfo.id].
typedef SerialOpener = Future<SerialPortHandle> Function(String id);

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
      final handle = await _opener(port.id);
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

/// USB serial ports on Android, through the vendored usb_serial plugin.
///
/// Other platforms report no ports for now; Mac USB support comes later.
class UsbSerialPorts {
  const UsbSerialPorts();

  /// Baud rate used by MeshCore and Meshtastic over USB.
  static const baudRate = 115200;

  /// Whether this platform has USB radio support.
  bool get supported => Platform.isAndroid;

  /// Ports plugged in now.
  Future<List<SerialPortInfo>> list() async {
    if (!supported) return const [];
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

  /// Opens the port with [id] at [baudRate], 8 data bits, no parity.
  Future<SerialPortHandle> open(String id) async {
    final devices = await UsbSerial.listDevices();
    UsbDevice? device;
    for (final d in devices) {
      if ('${d.deviceId}' == id) device = d;
    }
    if (device == null) throw const LinkException('The radio was unplugged');
    final port = await device.create();
    if (port == null || !await port.open()) {
      throw const LinkException('Android did not allow access to the radio');
    }
    // DTR on and RTS off: some boards reset or stay in the bootloader
    // otherwise.
    await port.setDTR(true);
    await port.setRTS(false);
    await port.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    return UsbSerialPortHandle(port);
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
