import '../meshtastic/admin.dart';

/// A Meshtastic node's settings as edited on the settings screen: its
/// names, device role, LoRa, position and telemetry sections.
class MeshtasticSettings {
  const MeshtasticSettings(this.sections);

  /// The sections shown, in screen order.
  static const kinds = [
    SectionKind.owner,
    SectionKind.device,
    SectionKind.lora,
    SectionKind.position,
    SectionKind.telemetry,
  ];

  final Map<SectionKind, SettingsSection> sections;

  SettingsSection operator [](SectionKind kind) => sections[kind]!;

  /// A copy with one field changed.
  MeshtasticSettings withValue(SectionKind kind, int field, Object value) =>
      MeshtasticSettings({
        ...sections,
        kind: this[kind].withValue(field, value),
      });

  /// Sections with changes.
  List<SettingsSection> get changed => [
    for (final k in kinds)
      if (sections[k] case final s? when s.changed) s,
  ];

  bool get hasChanges => changed.isNotEmpty;

  /// Whether a change moves the node to other radio settings, so it would
  /// stop hearing the mesh unless every other node changes too.
  bool get radioChanged {
    final lora = sections[SectionKind.lora];
    if (lora == null) return false;
    return lora.changedFields.intersection({
      LoraField.region,
      LoraField.modemPreset,
      LoraField.usePreset,
      LoraField.channelNum,
    }).isNotEmpty;
  }

  /// Whether the role becomes one that relays for everyone.
  bool get becomesInfrastructure {
    final device = sections[SectionKind.device];
    if (device == null || !device.changedFields.contains(DeviceField.role)) {
      return false;
    }
    return MeshtasticRole.infrastructure.contains(
      device.number(DeviceField.role),
    );
  }

  /// Whether the names are acceptable to the firmware: a long name of up
  /// to 39 bytes and a short name of 1–4 characters.
  String? get nameProblem {
    final owner = sections[SectionKind.owner];
    if (owner == null) return null;
    final long = owner.text(OwnerField.longName).trim();
    final short = owner.text(OwnerField.shortName).trim();
    if (long.isEmpty) return 'long';
    if (longNameBytes(long) > 39) return 'long';
    if (short.isEmpty || short.runes.length > 4 || longNameBytes(short) > 7) {
      return 'short';
    }
    return null;
  }

  /// UTF-8 length of [s].
  static int longNameBytes(String s) {
    var n = 0;
    for (final r in s.runes) {
      n += r < 0x80
          ? 1
          : r < 0x800
          ? 2
          : r < 0x10000
          ? 3
          : 4;
    }
    return n;
  }
}
