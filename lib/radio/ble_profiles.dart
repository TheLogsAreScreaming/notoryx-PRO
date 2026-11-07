import 'radio_link.dart';

/// Bluetooth service and characteristic IDs for each protocol.
///
/// MeshCore companions use the Nordic UART service: the app writes frames to
/// [write] and gets one frame per notification on [notify]. Meshtastic nodes
/// use their own service: the app writes `ToRadio` packets to [write], is
/// told about new data by a notification on [notify] (FromNum), and then
/// reads `FromRadio` packets from [read] until it returns nothing.
class BleProfile {
  const BleProfile._({
    required this.protocol,
    required this.service,
    required this.write,
    required this.notify,
    this.read,
  });

  /// The protocol this profile carries.
  final RadioProtocol protocol;

  /// Primary service ID.
  final String service;

  /// Characteristic the app writes to.
  final String write;

  /// Characteristic the radio notifies on.
  final String notify;

  /// Characteristic the app polls for queued packets (Meshtastic only).
  final String? read;

  /// Whether received data must be fetched by reading [read].
  bool get pollsForData => read != null;

  /// MeshCore companion over the Nordic UART service.
  static const meshcore = BleProfile._(
    protocol: RadioProtocol.meshcore,
    service: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    write: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
    notify: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  );

  /// Meshtastic node (ToRadio / FromNum / FromRadio).
  static const meshtastic = BleProfile._(
    protocol: RadioProtocol.meshtastic,
    service: '6ba1b218-15a8-461f-9fa8-5dcae273eafd',
    write: 'f75c76d2-129e-4dad-a1dd-7866124401e7',
    notify: 'ed9da18b-a800-4f66-a670-aa7547e34453',
    read: '2c55e69e-4993-11ed-b878-0242ac120002',
  );

  /// Both profiles.
  static const all = [meshcore, meshtastic];

  /// The profile for [protocol].
  static BleProfile of(RadioProtocol protocol) => switch (protocol) {
    RadioProtocol.meshcore => meshcore,
    RadioProtocol.meshtastic => meshtastic,
  };
}

/// Works out which protocol an advertising device speaks.
///
/// Advertised service IDs decide it when present. Some radios leave the
/// service out of their advertisement, so names are a fallback: MeshCore
/// companions advertise as `MeshCore-<node name>` and Meshtastic nodes as
/// `Meshtastic_<id>` by default. Returns null when it can't tell.
RadioProtocol? classifyAdvertisement({
  required List<String> services,
  String? name,
}) {
  final ids = services.map(normalizeUuid).toSet();
  for (final profile in BleProfile.all) {
    if (ids.contains(profile.service)) return profile.protocol;
  }
  final n = (name ?? '').trim().toLowerCase();
  if (n.startsWith('meshcore')) return RadioProtocol.meshcore;
  if (n.startsWith('meshtastic')) return RadioProtocol.meshtastic;
  return null;
}

/// Lower-case, full-length form of a Bluetooth UUID.
///
/// Expands 16-bit (`180f`) and 32-bit IDs onto the Bluetooth base UUID so
/// IDs from different platforms compare equal.
String normalizeUuid(String uuid) {
  final u = uuid.trim().toLowerCase();
  const base = '-0000-1000-8000-00805f9b34fb';
  if (u.length == 4) return '0000$u$base';
  if (u.length == 8) return '$u$base';
  return u;
}
