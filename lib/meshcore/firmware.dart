/// Which MeshCore companion firmware this app can work with.
///
/// The firmware reports a protocol code in DEVICE_INFO (14 for v1.18).
/// Below [minimumCode] the app refuses to continue, rather than failing
/// in confusing ways later; individual features above that are checked with
/// [MeshCoreFirmware.supports].
abstract final class MeshCoreFirmware {
  /// Oldest protocol code the app supports.
  ///
  /// Code 3 brings the v3 message frames (with SNR) and the DEVICE_INFO
  /// layout the app relies on.
  static const minimumCode = 3;

  /// Whether a radio reporting [code] has [feature].
  static bool supports(int code, MeshCoreFeature feature) =>
      code >= feature.minimumCode;
}

/// Firmware features that arrived after [MeshCoreFirmware.minimumCode].
enum MeshCoreFeature {
  /// Stats, flood scope and control data.
  stats(8, 'Radio statistics'),

  /// Client repeat setting in DEVICE_INFO.
  clientRepeat(9, 'Client repeat'),

  /// Path hash size setting.
  pathHashMode(10, 'Path hash size'),

  /// Requests to nodes that aren't contacts.
  anonymousRequests(13, 'Requests to unknown nodes'),

  /// Running CLI commands on the companion itself.
  companionCli(14, 'Radio command line');

  const MeshCoreFeature(this.minimumCode, this.label);

  /// First protocol code with this feature.
  final int minimumCode;

  /// Name shown to people.
  final String label;
}

/// The radio's firmware is too old for this app, or for one feature.
class UnsupportedFirmware implements Exception {
  const UnsupportedFirmware({
    required this.found,
    required this.needed,
    this.version,
    this.feature,
  });

  /// Protocol code the radio reported.
  final int found;

  /// Protocol code required.
  final int needed;

  /// Firmware version text, such as `v1.18.0`, if known.
  final String? version;

  /// The feature that needs newer firmware; null for the app as a whole.
  final MeshCoreFeature? feature;

  /// Text to show people.
  String get message {
    final have = version ?? 'protocol $found';
    return feature == null
        ? 'This radio runs MeshCore $have, which is too old for NOTORYX PRO. '
              'Update the radio to a newer companion firmware.'
        : '${feature!.label} needs newer MeshCore firmware than $have.';
  }

  @override
  String toString() => 'UnsupportedFirmware: $message';
}
