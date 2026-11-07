/// A Meshtastic firmware version such as `2.8.2.d5f1619`.
class MeshtasticVersion implements Comparable<MeshtasticVersion> {
  const MeshtasticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Reads the first three numbers; null if there aren't three.
  static MeshtasticVersion? tryParse(String text) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
    if (m == null) return null;
    return MeshtasticVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(MeshtasticVersion other) {
    if (major != other.major) return major - other.major;
    if (minor != other.minor) return minor - other.minor;
    return patch - other.patch;
  }

  bool operator <(MeshtasticVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is MeshtasticVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Which Meshtastic firmware this app works with.
abstract final class MeshtasticFirmware {
  /// Oldest supported release: 2.5 brought public-key direct messages and
  /// the device metadata fields the app relies on.
  static const minimum = MeshtasticVersion(2, 5, 0);

  /// Whether [version] (from `DeviceMetadata.firmware_version`) is usable.
  static bool isSupported(String version) {
    final v = MeshtasticVersion.tryParse(version);
    return v != null && !(v < minimum);
  }
}

/// The node's firmware is too old, or didn't say which version it runs.
class UnsupportedMeshtasticFirmware implements Exception {
  const UnsupportedMeshtasticFirmware(this.version);

  /// What the node reported; empty if it sent no metadata.
  final String version;

  /// Text to show people.
  String get message => version.isEmpty
      ? "This Meshtastic node didn't report its firmware version, so it is "
            'probably too old for NOTORYX PRO. Update it to '
            '${MeshtasticFirmware.minimum} or newer.'
      : 'This node runs Meshtastic $version. NOTORYX PRO needs '
            '${MeshtasticFirmware.minimum} or newer; update the node first.';

  @override
  String toString() => 'UnsupportedMeshtasticFirmware: $message';
}
