import 'model.dart';

/// One telemetry reading from a node: its battery and radio load, and any
/// weather sensor readings it reports.
class TelemetryPoint {
  const TelemetryPoint({
    required this.radioId,
    required this.node,
    required this.time,
    this.batteryLevel,
    this.voltage,
    this.channelUtilization,
    this.airUtilTx,
    this.uptimeSeconds,
    this.temperature,
    this.relativeHumidity,
    this.barometricPressure,
  });

  final RadioId radioId;
  final NodeKey node;

  /// When the reading was taken (or received, if the node didn't say).
  final DateTime time;

  /// Percent; above 100 means the node runs on external power.
  final int? batteryLevel;
  final double? voltage;

  /// Percent of time the channel is busy, as this node hears it.
  final double? channelUtilization;

  /// Percent of the last hour this node spent transmitting.
  final double? airUtilTx;
  final int? uptimeSeconds;

  /// Degrees Celsius.
  final double? temperature;

  /// Percent.
  final double? relativeHumidity;

  /// hPa.
  final double? barometricPressure;

  /// Whether the node runs on external power rather than its battery.
  bool get isPowered => (batteryLevel ?? 0) > 100;

  bool get isEmpty =>
      batteryLevel == null &&
      voltage == null &&
      channelUtilization == null &&
      airUtilTx == null &&
      uptimeSeconds == null &&
      temperature == null &&
      relativeHumidity == null &&
      barometricPressure == null;
}

/// How long telemetry history is kept.
const telemetryKeep = Duration(days: 14);
