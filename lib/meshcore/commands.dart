import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';
import 'codes.dart';

/// Text message kinds in MeshCore.
enum TextType {
  plain(0),
  cliData(1),
  signedPlain(2);

  const TextType(this.code);

  /// Byte value.
  final int code;

  /// The enum value for [code]; [plain] if unknown.
  static TextType of(int code) =>
      values.firstWhere((t) => t.code == code, orElse: () => plain);
}

/// Builders for MeshCore companion commands.
///
/// Each returns one frame, ready for a Bluetooth write or for
/// `wrapStreamFrame` on USB and TCP.
abstract final class MeshCoreCommands {
  /// `APP_START`: identifies the app; the radio replies with SELF_INFO.
  static Uint8List appStart(String appName) {
    final w = ByteWriter()
      ..u8(Cmd.appStart)
      ..bytes(Uint8List(7))
      ..bytes(utf8.encode(appName));
    return _checked(w);
  }

  /// `DEVICE_QUERY`: the radio replies with DEVICE_INFO.
  static Uint8List deviceQuery([
    int appVersion = MeshCoreLimits.appProtocolVersion,
  ]) => Uint8List.fromList([Cmd.deviceQuery, appVersion]);

  /// `GET_CONTACTS`, optionally only those changed after [since]
  /// (the radio's `lastmod` clock, from the previous END_OF_CONTACTS).
  static Uint8List getContacts({int? since}) {
    final w = ByteWriter()..u8(Cmd.getContacts);
    if (since != null) w.u32(since);
    return w.toBytes();
  }

  /// `GET_DEVICE_TIME`.
  static Uint8List getDeviceTime() => Uint8List.fromList([Cmd.getDeviceTime]);

  /// `SET_DEVICE_TIME` to [unixSeconds]. The radio refuses to go backwards.
  static Uint8List setDeviceTime(int unixSeconds) =>
      (ByteWriter()
            ..u8(Cmd.setDeviceTime)
            ..u32(unixSeconds))
          .toBytes();

  /// `SEND_SELF_ADVERT`: zero-hop by default, flooded when [flood].
  static Uint8List sendSelfAdvert({bool flood = false}) =>
      Uint8List.fromList([Cmd.sendSelfAdvert, flood ? 1 : 0]);

  /// `SET_ADVERT_NAME`.
  static Uint8List setAdvertName(String name) {
    final encoded = utf8.encode(name);
    if (encoded.isEmpty || encoded.length > 31) {
      throw ArgumentError.value(name, 'name', 'must be 1..31 bytes');
    }
    return Uint8List.fromList([Cmd.setAdvertName, ...encoded]);
  }

  /// `SEND_TXT_MSG` to the contact whose public key starts with
  /// [publicKey] (at least 6 bytes; only the first 6 are sent).
  ///
  /// [attempt] numbers retries of the same message (0 first).
  static Uint8List sendText({
    required List<int> publicKey,
    required String text,
    required int timestamp,
    int attempt = 0,
    TextType type = TextType.plain,
  }) {
    if (publicKey.length < MeshCoreLimits.keyPrefix) {
      throw ArgumentError.value(publicKey.length, 'publicKey', 'too short');
    }
    final w = ByteWriter()
      ..u8(Cmd.sendText)
      ..u8(type.code)
      ..u8(attempt & 0xff)
      ..u32(timestamp)
      ..bytes(publicKey.sublist(0, MeshCoreLimits.keyPrefix))
      ..bytes(_text(text));
    return _checked(w);
  }

  /// `SEND_CHANNEL_TXT_MSG` to channel slot [channel].
  static Uint8List sendChannelText({
    required int channel,
    required String text,
    required int timestamp,
  }) {
    final w = ByteWriter()
      ..u8(Cmd.sendChannelText)
      ..u8(TextType.plain.code)
      ..u8(channel)
      ..u32(timestamp)
      ..bytes(_text(text));
    return _checked(w);
  }

  /// `SYNC_NEXT_MESSAGE`: fetches one queued message.
  static Uint8List syncNextMessage() =>
      Uint8List.fromList([Cmd.syncNextMessage]);

  /// `GET_BATT_AND_STORAGE`.
  static Uint8List getBattAndStorage() =>
      Uint8List.fromList([Cmd.getBattAndStorage]);

  /// `GET_CHANNEL` for slot [index].
  static Uint8List getChannel(int index) =>
      Uint8List.fromList([Cmd.getChannel, index]);

  /// `SET_CHANNEL`: stores [name] and its 16-byte [secret] in slot [index].
  ///
  /// An all-zero secret with an empty name clears the slot; an all-zero
  /// secret with a name is refused, since anyone could read that channel.
  static Uint8List setChannel(int index, String name, List<int> secret) {
    if (secret.length != MeshCoreLimits.channelSecret) {
      throw ArgumentError.value(secret.length, 'secret', 'must be 16 bytes');
    }
    if (name.isNotEmpty && secret.every((b) => b == 0)) {
      throw ArgumentError.value(secret, 'secret', 'all-zero secret');
    }
    if (utf8.encode(name).length >= MeshCoreLimits.channelName) {
      throw ArgumentError.value(name, 'name', 'must be under 32 bytes');
    }
    final w = ByteWriter()
      ..u8(Cmd.setChannel)
      ..u8(index)
      ..fixedString(name, MeshCoreLimits.channelName)
      ..bytes(secret);
    return w.toBytes();
  }

  /// `GET_STATS` for [type]: 0 core, 1 radio, 2 packets (protocol 8+).
  static Uint8List getStats(int type) =>
      Uint8List.fromList([Cmd.getStats, type]);

  /// `SEND_TRACE_PATH` along [path] (repeater hashes of [hashSize] bytes:
  /// 1, 2, 4 or 8). The radio replies SENT with [tag], then a TRACE_DATA
  /// push when the trace comes back.
  static Uint8List sendTracePath({
    required int tag,
    required List<int> path,
    int hashSize = 1,
    int auth = 0,
  }) {
    const sizes = {1: 0, 2: 1, 4: 2, 8: 3};
    final flags = sizes[hashSize];
    if (flags == null || path.isEmpty || path.length % hashSize != 0) {
      throw ArgumentError.value(path, 'path', 'bad trace path');
    }
    final w = ByteWriter()
      ..u8(Cmd.sendTracePath)
      ..u32(tag)
      ..u32(auth)
      ..u8(flags)
      ..bytes(path);
    return _checked(w);
  }

  /// `SEND_CONTROL_DATA` carrying a node-discover request (protocol 8+):
  /// sent zero-hop, so only nodes in direct range hear it. Nodes whose
  /// type bit is set in [types] (bit 2 = repeaters) answer with [tag].
  /// [prefixOnly] asks for 8-byte key prefixes instead of full keys.
  static Uint8List discoverNodes({
    required int tag,
    int types = 1 << 2,
    bool prefixOnly = false,
    int since = 0,
  }) {
    final w = ByteWriter()
      ..u8(Cmd.sendControlData)
      ..u8(discoverRequest | (prefixOnly ? 1 : 0))
      ..u8(types)
      ..u32(tag)
      ..u32(since);
    return _checked(w);
  }

  /// Control-data type of a node-discover request (upper 4 bits).
  static const discoverRequest = 0x80;

  /// Control-data type of a node-discover answer (upper 4 bits; the lower
  /// 4 are the answering node's type).
  static const discoverAnswer = 0x90;

  /// `SET_RADIO_PARAMS`: frequency in MHz, bandwidth in kHz, spreading
  /// factor 5–12, coding rate 5–8 (as the firmware checks them).
  static Uint8List setRadioParams({
    required double frequencyMHz,
    required double bandwidthKHz,
    required int spreadingFactor,
    required int codingRate,
  }) {
    final freq = (frequencyMHz * 1000).round();
    final bw = (bandwidthKHz * 1000).round();
    if (freq < 150000 || freq > 2500000) {
      throw ArgumentError.value(frequencyMHz, 'frequencyMHz', '150–2500 MHz');
    }
    if (bw < 7000 || bw > 500000) {
      throw ArgumentError.value(bandwidthKHz, 'bandwidthKHz', '7.8–500 kHz');
    }
    if (spreadingFactor < 5 || spreadingFactor > 12) {
      throw ArgumentError.value(spreadingFactor, 'spreadingFactor', '5–12');
    }
    if (codingRate < 5 || codingRate > 8) {
      throw ArgumentError.value(codingRate, 'codingRate', '5–8');
    }
    return (ByteWriter()
          ..u8(Cmd.setRadioParams)
          ..u32(freq)
          ..u32(bw)
          ..u8(spreadingFactor)
          ..u8(codingRate))
        .toBytes();
  }

  /// `SET_RADIO_TX_POWER` in dBm (-9 up to the radio's maximum).
  static Uint8List setTxPower(int dbm) =>
      Uint8List.fromList([Cmd.setTxPower, dbm & 0xff]);

  /// `SET_ADVERT_LATLON` in degrees.
  static Uint8List setAdvertPosition(double latitude, double longitude) {
    if (latitude.abs() > 90 || longitude.abs() > 180) {
      throw ArgumentError('position out of range');
    }
    return (ByteWriter()
          ..u8(Cmd.setAdvertLatLon)
          ..i32((latitude * 1e6).round())
          ..i32((longitude * 1e6).round()))
        .toBytes();
  }

  /// `SET_OTHER_PARAMS`: contact auto-add, telemetry sharing bits,
  /// whether adverts include the position, and extra acks.
  static Uint8List setOtherParams({
    required bool manualAddContacts,
    required int telemetryMode,
    required int advertLocationPolicy,
    required int multiAcks,
  }) => Uint8List.fromList([
    Cmd.setOtherParams,
    manualAddContacts ? 1 : 0,
    telemetryMode & 0x3f,
    advertLocationPolicy,
    multiAcks,
  ]);

  /// `SET_PATH_HASH_MODE`: [mode] is the hop ID size in bytes, minus one.
  static Uint8List setPathHashMode(int mode) =>
      Uint8List.fromList([Cmd.setPathHashMode, 0, mode]);

  /// `REBOOT`: the radio restarts without replying.
  static Uint8List reboot() =>
      Uint8List.fromList([Cmd.reboot, ...utf8.encode('reboot')]);

  /// `SEND_LOGIN` to a repeater or room server.
  static Uint8List sendLogin(List<int> publicKey, String password) {
    final pw = utf8.encode(password);
    if (pw.length > 15) {
      throw ArgumentError.value(password, 'password', 'longer than 15 bytes');
    }
    return Uint8List.fromList([Cmd.sendLogin, ..._key(publicKey), ...pw]);
  }

  /// `SEND_STATUS_REQ` to a repeater or room server.
  static Uint8List sendStatusRequest(List<int> publicKey) =>
      Uint8List.fromList([Cmd.sendStatusRequest, ..._key(publicKey)]);

  /// `RUN_CLI_COMMAND` on the companion radio itself (protocol 14+).
  static Uint8List runCli(String command) {
    final text = utf8.encode(command);
    if (text.isEmpty) throw ArgumentError.value(command, 'command', 'empty');
    return _checked(
      ByteWriter()
        ..u8(Cmd.runCli)
        ..bytes(text),
    );
  }

  /// `ADD_UPDATE_CONTACT`: puts a node in the radio's contact list, laid
  /// out like a contact record. [pathLength] 0xFF means no known route, so
  /// the radio floods until it learns one.
  static Uint8List addUpdateContact({
    required List<int> publicKey,
    required int type,
    required String name,
    int flags = 0,
    int pathLength = 0xff,
    List<int> path = const [],
    int lastAdvert = 0,
    double? latitude,
    double? longitude,
  }) {
    if (path.length > MeshCoreLimits.pathField) {
      throw ArgumentError.value(path.length, 'path', 'longer than 64 bytes');
    }
    final w = ByteWriter()
      ..u8(Cmd.addUpdateContact)
      ..bytes(_key(publicKey))
      ..u8(type)
      ..u8(flags)
      ..u8(pathLength)
      ..bytes([
        ...path,
        ...List.filled(MeshCoreLimits.pathField - path.length, 0),
      ])
      ..fixedString(_fit(name, 31), 32)
      ..u32(lastAdvert)
      ..i32(((latitude ?? 0) * 1e6).round())
      ..i32(((longitude ?? 0) * 1e6).round());
    return _checked(w);
  }

  /// `REMOVE_CONTACT` by full public key.
  static Uint8List removeContact(List<int> publicKey) =>
      Uint8List.fromList([Cmd.removeContact, ..._key(publicKey)]);

  /// `RESET_PATH` so the next message to the contact floods.
  static Uint8List resetPath(List<int> publicKey) =>
      Uint8List.fromList([Cmd.resetPath, ..._key(publicKey)]);

  static List<int> _key(List<int> publicKey) {
    if (publicKey.length != MeshCoreLimits.publicKey) {
      throw ArgumentError.value(publicKey.length, 'publicKey', 'must be 32');
    }
    return publicKey;
  }

  static List<int> _text(String text) {
    final encoded = utf8.encode(text);
    if (encoded.isEmpty) {
      throw ArgumentError.value(text, 'text', 'empty');
    }
    if (encoded.length > MeshCoreLimits.maxTextBytes) {
      throw ArgumentError.value(
        encoded.length,
        'text',
        'longer than ${MeshCoreLimits.maxTextBytes} bytes',
      );
    }
    return encoded;
  }

  /// [text] cut to at most [bytes] bytes of UTF-8, on a character boundary.
  static String _fit(String text, int bytes) {
    var out = text;
    while (utf8.encode(out).length > bytes) {
      out = String.fromCharCodes(out.runes.toList()..removeLast());
    }
    return out;
  }

  static Uint8List _checked(ByteWriter w) {
    final frame = w.toBytes();
    if (frame.length > MeshCoreLimits.maxFrame) {
      throw ArgumentError.value(frame.length, 'frame', 'too long');
    }
    return frame;
  }
}
