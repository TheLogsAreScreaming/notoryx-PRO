import '../radio/radio.dart';

/// A radio the person chose to connect to, on some transport.
sealed class RadioTarget {
  const RadioTarget(this.protocol);

  final RadioProtocol protocol;

  /// Name to show while connecting.
  String get label;

  LinkKind get kind;

  /// Where the radio is (transport and address); two targets with the
  /// same address are the same radio.
  String get address;
}

/// A radio found by a Bluetooth scan.
final class BleTarget extends RadioTarget {
  const BleTarget({
    required this.deviceId,
    required this.name,
    required RadioProtocol protocol,
  }) : super(protocol);

  final String deviceId;
  final String name;

  @override
  String get label => name;

  @override
  LinkKind get kind => LinkKind.bluetooth;

  @override
  String get address => 'ble:$deviceId';
}

/// A radio on the network.
final class TcpTarget extends RadioTarget {
  const TcpTarget({
    required this.host,
    required RadioProtocol protocol,
    this.port,
  }) : super(protocol);

  final String host;
  final int? port;

  @override
  String get label => '$host:${port ?? TcpRadioLink.defaultPort(protocol)}';

  @override
  LinkKind get kind => LinkKind.tcp;

  @override
  String get address => 'tcp:$label';
}

/// A radio plugged in by USB (Android).
final class UsbTarget extends RadioTarget {
  const UsbTarget({required this.port, required RadioProtocol protocol})
    : super(protocol);

  final SerialPortInfo port;

  @override
  String get label => port.name;

  @override
  LinkKind get kind => LinkKind.usb;

  @override
  String get address => 'usb:${port.id}';
}

/// Makes [RadioLink]s for targets; tests replace it.
class LinkFactory {
  const LinkFactory({
    this.ble = const UniversalBleBackend(),
    this.usb = const UsbSerialPorts(),
  });

  final BleBackend ble;
  final UsbSerialPorts usb;

  RadioLink create(RadioTarget target, {ConnectionLog? log}) =>
      switch (target) {
        BleTarget(:final deviceId, :final name) => BleRadioLink(
          deviceId: deviceId,
          name: name,
          profile: BleProfile.of(target.protocol),
          backend: ble,
          log: log,
        ),
        TcpTarget(:final host, :final port) => TcpRadioLink(
          host: host,
          port: port,
          protocol: target.protocol,
          log: log,
        ),
        UsbTarget(:final port) => SerialRadioLink(
          port: port,
          protocol: target.protocol,
          opener: usb.open,
          log: log,
        ),
      };
}
