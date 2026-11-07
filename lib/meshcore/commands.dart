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

  static Uint8List _checked(ByteWriter w) {
    final frame = w.toBytes();
    if (frame.length > MeshCoreLimits.maxFrame) {
      throw ArgumentError.value(frame.length, 'frame', 'too long');
    }
    return frame;
  }
}
