import '../meshcore/frames.dart';

/// A MeshCore companion's own settings, as edited on the settings screen.
class MeshCoreSettings {
  const MeshCoreSettings({
    required this.name,
    required this.txPower,
    required this.maxTxPower,
    required this.frequencyMHz,
    required this.bandwidthKHz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.latitude,
    required this.longitude,
    required this.shareLocationInAdverts,
    required this.manualAddContacts,
    required this.telemetryMode,
    required this.multiAcks,
  });

  /// The settings the radio reported.
  factory MeshCoreSettings.from(SelfInfoFrame s) => MeshCoreSettings(
    name: s.name,
    txPower: s.txPower,
    maxTxPower: s.maxTxPower,
    frequencyMHz: s.frequencyMHz,
    bandwidthKHz: s.bandwidthKHz,
    spreadingFactor: s.spreadingFactor,
    codingRate: s.codingRate,
    latitude: s.latitude,
    longitude: s.longitude,
    shareLocationInAdverts: s.advertLocationPolicy != 0,
    manualAddContacts: s.manualAddContacts,
    telemetryMode: s.telemetryMode,
    multiAcks: s.multiAcks,
  );

  final String name;
  final int txPower;

  /// Highest transmit power this hardware allows, dBm.
  final int maxTxPower;
  final double frequencyMHz;
  final double bandwidthKHz;
  final int spreadingFactor;
  final int codingRate;
  final double latitude;
  final double longitude;
  final bool shareLocationInAdverts;

  /// Off: the radio adds nodes it hears to its contacts by itself.
  final bool manualAddContacts;
  final int telemetryMode;
  final int multiAcks;

  /// Bandwidths LoRa radios support, kHz.
  static const bandwidths = [
    7.8,
    10.4,
    15.6,
    20.8,
    31.25,
    41.7,
    62.5,
    125.0,
    250.0,
    500.0,
  ];

  /// Whether the frequency/bandwidth/SF/CR differ from [other].
  bool radioDiffers(MeshCoreSettings other) =>
      frequencyMHz != other.frequencyMHz ||
      bandwidthKHz != other.bandwidthKHz ||
      spreadingFactor != other.spreadingFactor ||
      codingRate != other.codingRate;

  bool otherDiffers(MeshCoreSettings other) =>
      shareLocationInAdverts != other.shareLocationInAdverts ||
      manualAddContacts != other.manualAddContacts ||
      telemetryMode != other.telemetryMode ||
      multiAcks != other.multiAcks;

  MeshCoreSettings copyWith({
    String? name,
    int? txPower,
    double? frequencyMHz,
    double? bandwidthKHz,
    int? spreadingFactor,
    int? codingRate,
    double? latitude,
    double? longitude,
    bool? shareLocationInAdverts,
    bool? manualAddContacts,
  }) => MeshCoreSettings(
    name: name ?? this.name,
    txPower: txPower ?? this.txPower,
    maxTxPower: maxTxPower,
    frequencyMHz: frequencyMHz ?? this.frequencyMHz,
    bandwidthKHz: bandwidthKHz ?? this.bandwidthKHz,
    spreadingFactor: spreadingFactor ?? this.spreadingFactor,
    codingRate: codingRate ?? this.codingRate,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    shareLocationInAdverts:
        shareLocationInAdverts ?? this.shareLocationInAdverts,
    manualAddContacts: manualAddContacts ?? this.manualAddContacts,
    telemetryMode: telemetryMode,
    multiAcks: multiAcks,
  );
}
