import 'dart:typed_data';

import 'protobuf.dart';

/// `AdminMessage` fields this app uses (admin.proto).
abstract final class AdminField {
  static const getOwnerRequest = 3;
  static const getOwnerResponse = 4;
  static const getConfigRequest = 5;
  static const getConfigResponse = 6;
  static const getModuleConfigRequest = 7;
  static const getModuleConfigResponse = 8;
  static const getMetadataRequest = 12;
  static const getMetadataResponse = 13;
  static const setOwner = 32;
  static const setChannel = 33;
  static const setConfig = 34;
  static const setModuleConfig = 35;
  static const beginEditSettings = 64;
  static const commitEditSettings = 65;
  static const rebootSeconds = 97;
  static const sessionPasskey = 101;
}

/// Which part of the settings a [SettingsSection] is.
///
/// [field] is the `Config` / `ModuleConfig` oneof field number (also used in
/// the config download); the `ConfigType` / `ModuleConfigType` asked for in
/// a get request is one less.
enum SectionKind {
  device(1, module: false),
  position(2, module: false),
  lora(6, module: false),
  telemetry(6, module: true),

  /// `User`: the node's names. Not part of `Config`.
  owner(0, module: false);

  const SectionKind(this.field, {required this.module});

  final int field;
  final bool module;

  /// `ConfigType` / `ModuleConfigType` value for a get request.
  int get requestType => field - 1;
}

/// `Config.DeviceConfig` fields edited here.
abstract final class DeviceField {
  static const role = 1;
  static const rebroadcastMode = 6;
  static const nodeInfoBroadcastSecs = 7;
}

/// `Config.PositionConfig` fields edited here.
abstract final class PositionField {
  static const broadcastSecs = 1;
  static const smartBroadcast = 2;
  static const fixedPosition = 3;
  static const gpsUpdateInterval = 5;
  static const gpsMode = 13;
}

/// `Config.LoRaConfig` fields edited here.
abstract final class LoraField {
  static const usePreset = 1;
  static const modemPreset = 2;
  static const region = 7;
  static const hopLimit = 8;
  static const txEnabled = 9;
  static const txPower = 10;
  static const channelNum = 11;
  static const ignoreMqtt = 104;
  static const okToMqtt = 105;
}

/// `ModuleConfig.TelemetryConfig` fields edited here.
abstract final class TelemetryField {
  static const deviceInterval = 1;
  static const environmentInterval = 2;
  static const environmentEnabled = 3;
}

/// `User` fields edited here.
abstract final class OwnerField {
  static const longName = 2;
  static const shortName = 3;
  static const isLicensed = 6;
}

/// One settings message (a `Config` section, the telemetry module or the
/// owner), read from a node and edited in place.
///
/// Only the fields the app edits are touched: everything else the node
/// sent, including fields newer than this app, is written back exactly as
/// it arrived, because setting a section replaces all of it on the node.
class SettingsSection {
  SettingsSection(SectionKind kind, Uint8List raw)
    : this._(kind, raw, const {});

  SettingsSection._(this.kind, this.raw, this._changes)
    : _fields = readFields(raw);

  final SectionKind kind;

  /// The message as the node sent it.
  final Uint8List raw;
  final List<ProtoField> _fields;
  final Map<int, Object> _changes;

  /// Whether anything was changed.
  bool get changed => _changes.isNotEmpty;

  /// The fields changed, by number.
  Set<int> get changedFields => _changes.keys.toSet();

  ProtoField? _last(int number) {
    ProtoField? found;
    for (final f in _fields) {
      if (f.number == number) found = f;
    }
    return found;
  }

  /// An integer, enum or bool field (0 when not set).
  int number(int field) {
    if (_changes[field] case final int v) return v;
    final f = _last(field);
    return f == null || f.wireType != WireType.varint ? 0 : f.asInt;
  }

  /// A signed `int32` field.
  int signed(int field) => number(field).toSigned(32);

  bool flag(int field) => number(field) != 0;

  /// A string field.
  String text(int field) {
    if (_changes[field] case final String v) return v;
    final f = _last(field);
    return f == null || f.wireType != WireType.lengthDelimited
        ? ''
        : f.asString;
  }

  /// A copy with [field] set to [value] (an `int`, `bool` or `String`).
  /// Setting a field back to what the node has drops the change.
  SettingsSection withValue(int field, Object value) {
    final v = value is bool ? (value ? 1 : 0) : value;
    final original = v is String
        ? _originalText(field)
        : _originalNumber(field);
    final changes = Map<int, Object>.of(_changes);
    if (v == original) {
      changes.remove(field);
    } else {
      changes[field] = v;
    }
    return SettingsSection._(kind, raw, changes);
  }

  int _originalNumber(int field) {
    final f = _last(field);
    return f == null || f.wireType != WireType.varint ? 0 : f.asInt;
  }

  String _originalText(int field) {
    final f = _last(field);
    return f == null || f.wireType != WireType.lengthDelimited
        ? ''
        : f.asString;
  }

  /// The edited message: untouched fields as received, changed ones new.
  Uint8List encode() {
    final w = ProtoWriter();
    for (final f in _fields) {
      if (!_changes.containsKey(f.number)) w.field(f);
    }
    for (final MapEntry(key: n, value: v) in _changes.entries) {
      switch (v) {
        case String():
          w.string(n, v);
        case int():
          w.uint(n, v);
      }
    }
    return w.toBytes();
  }

  /// The message for a set request: `Config`/`ModuleConfig` wrapping this
  /// section, or the `User` itself for the owner.
  Uint8List get setPayload => kind == SectionKind.owner
      ? encode()
      : (ProtoWriter()..bytes(kind.field, encode(), always: true)).toBytes();
}

/// Builds `AdminMessage`s. [passkey] is the node's session passkey from
/// its last answer; nodes refuse changes without it.
abstract final class AdminMessages {
  static Uint8List _with(void Function(ProtoWriter w) body, List<int> passkey) {
    final w = ProtoWriter();
    body(w);
    w.bytes(AdminField.sessionPasskey, passkey);
    return w.toBytes();
  }

  /// Asks for one settings section (or the owner).
  static Uint8List get(SectionKind kind, {List<int> passkey = const []}) =>
      _with(
        (w) => switch (kind) {
          SectionKind.owner => w.boolean(AdminField.getOwnerRequest, true),
          _ when kind.module => w.uint(
            AdminField.getModuleConfigRequest,
            kind.requestType,
            always: true,
          ),
          _ => w.uint(
            AdminField.getConfigRequest,
            kind.requestType,
            always: true,
          ),
        },
        passkey,
      );

  /// Asks for firmware version and hardware (also yields a passkey).
  static Uint8List getMetadata({List<int> passkey = const []}) =>
      _with((w) => w.boolean(AdminField.getMetadataRequest, true), passkey);

  /// Replaces one settings section with [section]'s edited version.
  static Uint8List set(SettingsSection section, List<int> passkey) => _with(
    (w) => w.bytes(
      switch (section.kind) {
        SectionKind.owner => AdminField.setOwner,
        _ when section.kind.module => AdminField.setModuleConfig,
        _ => AdminField.setConfig,
      },
      section.setPayload,
      always: true,
    ),
    passkey,
  );

  /// Replaces one channel slot (`set_channel`); bytes from
  /// `MeshChannel.encode`.
  static Uint8List setChannel(Uint8List channel, List<int> passkey) => _with(
    (w) => w.bytes(AdminField.setChannel, channel, always: true),
    passkey,
  );

  /// Starts a batch of changes; the node saves them all on [commitEdit].
  static Uint8List beginEdit(List<int> passkey) =>
      _with((w) => w.boolean(AdminField.beginEditSettings, true), passkey);

  /// Saves a batch of changes; the node restarts if they need it.
  static Uint8List commitEdit(List<int> passkey) =>
      _with((w) => w.boolean(AdminField.commitEditSettings, true), passkey);

  /// Restarts the node after [seconds].
  static Uint8List reboot(List<int> passkey, {int seconds = 2}) => _with(
    (w) => w.uint(AdminField.rebootSeconds, seconds, always: true),
    passkey,
  );
}

/// An `AdminMessage` answer from a node.
class AdminReply {
  const AdminReply(this.field, this.body, this.passkey);

  /// Which answer it is (an [AdminField]).
  final int field;

  /// The answer's message bytes (a `Config`, `ModuleConfig`, `User` ...).
  final Uint8List body;

  /// The node's session passkey, to send with changes; empty if none.
  final Uint8List passkey;

  static AdminReply decode(Uint8List data) {
    var field = 0;
    var body = Uint8List(0);
    var passkey = Uint8List(0);
    for (final f in readFields(data)) {
      if (f.number == AdminField.sessionPasskey) {
        passkey = f.asBytes;
      } else if (f.wireType == WireType.lengthDelimited) {
        field = f.number;
        body = f.asBytes;
      } else {
        field = f.number;
      }
    }
    return AdminReply(field, body, passkey);
  }

  /// The section inside a get-config or get-module-config answer (the
  /// oneof's own bytes), or the owner `User`.
  SettingsSection? section(SectionKind kind) {
    final expected = switch (kind) {
      SectionKind.owner => AdminField.getOwnerResponse,
      _ when kind.module => AdminField.getModuleConfigResponse,
      _ => AdminField.getConfigResponse,
    };
    if (field != expected) return null;
    if (kind == SectionKind.owner) return SettingsSection(kind, body);
    for (final f in readFields(body)) {
      if (f.number == kind.field && f.wireType == WireType.lengthDelimited) {
        return SettingsSection(kind, f.asBytes);
      }
    }
    // A section left entirely at defaults arrives with no bytes.
    return SettingsSection(kind, Uint8List(0));
  }
}

/// Device roles (`Config.DeviceConfig.Role`). Deprecated roles are kept so
/// a node set to one still shows what it is.
abstract final class MeshtasticRole {
  static const client = 0;
  static const clientMute = 1;
  static const router = 2;
  static const routerClient = 3;
  static const repeater = 4;
  static const tracker = 5;
  static const sensor = 6;
  static const tak = 7;
  static const clientHidden = 8;
  static const lostAndFound = 9;
  static const takTracker = 10;
  static const routerLate = 11;
  static const clientBase = 12;

  /// Roles offered for new choices, in a sensible order.
  static const choices = [
    client,
    clientMute,
    clientBase,
    clientHidden,
    tracker,
    sensor,
    router,
    routerLate,
    tak,
    takTracker,
    lostAndFound,
  ];

  /// Roles that relay for everyone; the screen warns before choosing one.
  static const infrastructure = {router, routerLate, routerClient, repeater};
}

/// LoRa regions (`Config.LoRaConfig.RegionCode`) with their names.
abstract final class MeshtasticRegion {
  static const unset = 0;
  static const names = {
    1: 'United States',
    2: 'EU 433 MHz',
    3: 'EU 868 MHz',
    4: 'China',
    5: 'Japan',
    6: 'Australia / New Zealand',
    7: 'Korea',
    8: 'Taiwan',
    9: 'Russia',
    10: 'India',
    11: 'New Zealand 865 MHz',
    12: 'Thailand',
    13: '2.4 GHz',
    14: 'Ukraine 433 MHz',
    16: 'Malaysia 433 MHz',
    17: 'Malaysia 919 MHz',
    18: 'Singapore 923 MHz',
    19: 'Philippines 433 MHz',
    20: 'Philippines 868 MHz',
    21: 'Philippines 915 MHz',
    22: 'Australia / NZ 433 MHz',
    23: 'Kazakhstan 433 MHz',
    24: 'Kazakhstan 863 MHz',
    25: 'Nepal 865 MHz',
    26: 'Brazil 902 MHz',
  };
}

/// Modem presets (`Config.LoRaConfig.ModemPreset`) offered, with names.
abstract final class MeshtasticPreset {
  static const longFast = 0;
  static const names = {
    0: 'Long Fast',
    7: 'Long Moderate',
    9: 'Long Turbo',
    3: 'Medium Slow',
    4: 'Medium Fast',
    5: 'Short Slow',
    6: 'Short Fast',
    8: 'Short Turbo',
    1: 'Long Slow',
    2: 'Very Long Slow',
  };

  /// Retired presets: shown when a node uses one, never offered.
  static const retired = {1, 2};
}

/// GPS modes (`Config.PositionConfig.GpsMode`).
abstract final class MeshtasticGpsMode {
  static const disabled = 0;
  static const enabled = 1;
  static const notPresent = 2;
}
