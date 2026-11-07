import 'dart:typed_data';

import 'bytes.dart';
import 'codes.dart';
import 'commands.dart';

/// Anything the radio sends: a reply to a command or a push.
sealed class MeshCoreFrame {
  const MeshCoreFrame();

  /// Whether this is an unrequested notification (code 0x80 or above).
  bool get isPush => false;
}

/// `OK`, with the optional 32-bit value some commands return.
final class OkFrame extends MeshCoreFrame {
  const OkFrame([this.value]);
  final int? value;
}

/// `ERR` with its reason.
final class ErrorFrame extends MeshCoreFrame {
  const ErrorFrame(this.code);
  final MeshCoreErrorCode code;
}

/// `DISABLED`: the feature is turned off on the radio.
final class DisabledFrame extends MeshCoreFrame {
  const DisabledFrame();
}

/// Start of a contact list; [total] counts all contacts, not just changed.
final class ContactsStartFrame extends MeshCoreFrame {
  const ContactsStartFrame(this.total);
  final int total;
}

/// Kinds of MeshCore node.
enum NodeType {
  unknown(0),
  chat(1),
  repeater(2),
  room(3),
  sensor(4);

  const NodeType(this.code);
  final int code;

  static NodeType of(int code) =>
      values.firstWhere((t) => t.code == code, orElse: () => unknown);
}

/// One contact (from GET_CONTACTS, or a NEW_ADVERT push when auto-add is off).
final class ContactFrame extends MeshCoreFrame {
  const ContactFrame({
    required this.publicKey,
    required this.type,
    required this.flags,
    required this.pathLength,
    required this.path,
    required this.name,
    required this.lastAdvert,
    required this.latitude,
    required this.longitude,
    required this.lastModified,
    this.fromNewAdvert = false,
  });

  /// Full 32-byte public key.
  final Uint8List publicKey;
  final NodeType type;

  /// Bit flags; bit 0 marks a favourite.
  final int flags;

  /// Encoded out-path length; 0xFF means no known route (flood).
  final int pathLength;

  /// Out-path bytes actually in use.
  final Uint8List path;
  final String name;

  /// When the node last advertised, by its own clock (Unix seconds).
  final int lastAdvert;

  /// Advertised position in degrees, or null if none.
  final double? latitude;
  final double? longitude;

  /// Radio's change counter for incremental sync.
  final int lastModified;

  /// True when it came from a NEW_ADVERT push (node heard, not yet saved).
  final bool fromNewAdvert;

  @override
  bool get isPush => fromNewAdvert;

  /// Whether a direct route is known.
  bool get hasPath => pathLength != 0xff;

  /// Number of hops on the known route, or null when flooding.
  int? get hops => hasPath ? pathLength & 0x3f : null;

  /// Bytes per hop in the path (1–3, from the top two bits).
  int get hashSize => ((pathLength >> 6) & 0x3) + 1;

  /// Hex form of [publicKey].
  String get keyHex => toHex(publicKey);
}

/// End of a contact list; [lastModified] is the `since` for the next sync.
final class EndOfContactsFrame extends MeshCoreFrame {
  const EndOfContactsFrame(this.lastModified);
  final int lastModified;
}

/// The radio's own identity and settings (reply to APP_START).
final class SelfInfoFrame extends MeshCoreFrame {
  const SelfInfoFrame({
    required this.advertType,
    required this.txPower,
    required this.maxTxPower,
    required this.publicKey,
    required this.latitude,
    required this.longitude,
    required this.multiAcks,
    required this.advertLocationPolicy,
    required this.telemetryMode,
    required this.manualAddContacts,
    required this.frequencyMHz,
    required this.bandwidthKHz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.name,
  });

  final int advertType;
  final int txPower;
  final int maxTxPower;
  final Uint8List publicKey;
  final double latitude;
  final double longitude;
  final int multiAcks;
  final int advertLocationPolicy;
  final int telemetryMode;
  final bool manualAddContacts;
  final double frequencyMHz;
  final double bandwidthKHz;
  final int spreadingFactor;
  final int codingRate;
  final String name;
}

/// A direct message was handed to the mesh (reply to SEND_TXT_MSG).
final class SentFrame extends MeshCoreFrame {
  const SentFrame({
    required this.flood,
    required this.ackCode,
    required this.timeoutMs,
  });

  /// True if it went by flood rather than a known route.
  final bool flood;

  /// Matches the SEND_CONFIRMED push when the recipient acknowledges.
  final int ackCode;

  /// How long the radio suggests waiting for that acknowledgement.
  final int timeoutMs;
}

/// A received direct message.
final class ContactMessageFrame extends MeshCoreFrame {
  const ContactMessageFrame({
    required this.keyPrefix,
    required this.pathLength,
    required this.textType,
    required this.timestamp,
    required this.text,
    this.snr,
    this.signature,
  });

  /// First 6 bytes of the sender's public key.
  final Uint8List keyPrefix;

  /// Hops it flooded over; 0xFF when it came by a direct route.
  final int pathLength;
  final TextType textType;

  /// Sender's clock, Unix seconds.
  final int timestamp;
  final String text;

  /// Signal-to-noise ratio in dB (protocol v3 and later).
  final double? snr;

  /// 4-byte signature prefix for signed messages.
  final Uint8List? signature;
}

/// A received channel message; [text] is usually `Name: message`.
final class ChannelMessageFrame extends MeshCoreFrame {
  const ChannelMessageFrame({
    required this.channel,
    required this.pathLength,
    required this.textType,
    required this.timestamp,
    required this.text,
    this.snr,
  });

  final int channel;
  final int pathLength;
  final TextType textType;
  final int timestamp;
  final String text;
  final double? snr;

  /// The sender's name before `: `, if present.
  String? get senderName {
    final i = text.indexOf(': ');
    return i > 0 ? text.substring(0, i) : null;
  }

  /// The message without the sender prefix.
  String get body {
    final i = text.indexOf(': ');
    return i > 0 ? text.substring(i + 2) : text;
  }
}

/// A received binary channel datagram.
final class ChannelDataFrame extends MeshCoreFrame {
  const ChannelDataFrame({
    required this.channel,
    required this.pathLength,
    required this.dataType,
    required this.payload,
    required this.snr,
  });

  final int channel;
  final int pathLength;
  final int dataType;
  final Uint8List payload;
  final double snr;
}

/// The radio's clock (reply to GET_DEVICE_TIME).
final class CurrentTimeFrame extends MeshCoreFrame {
  const CurrentTimeFrame(this.unixSeconds);
  final int unixSeconds;
}

/// No queued messages left (reply to SYNC_NEXT_MESSAGE).
final class NoMoreMessagesFrame extends MeshCoreFrame {
  const NoMoreMessagesFrame();
}

/// Battery and storage (reply to GET_BATT_AND_STORAGE).
final class BatteryFrame extends MeshCoreFrame {
  const BatteryFrame({required this.millivolts, this.usedKb, this.totalKb});
  final int millivolts;
  final int? usedKb;
  final int? totalKb;
}

/// Firmware and hardware details (reply to DEVICE_QUERY).
final class DeviceInfoFrame extends MeshCoreFrame {
  const DeviceInfoFrame({
    required this.firmwareCode,
    this.maxContacts,
    this.maxChannels,
    this.blePin,
    this.buildDate,
    this.model,
    this.version,
    this.clientRepeat,
    this.pathHashMode,
  });

  /// Protocol version the firmware speaks (14 for v1.18).
  final int firmwareCode;
  final int? maxContacts;
  final int? maxChannels;
  final int? blePin;
  final String? buildDate;
  final String? model;
  final String? version;
  final bool? clientRepeat;
  final int? pathHashMode;
}

/// One channel slot (reply to GET_CHANNEL).
final class ChannelInfoFrame extends MeshCoreFrame {
  const ChannelInfoFrame({
    required this.index,
    required this.name,
    required this.secret,
  });

  final int index;
  final String name;
  final Uint8List secret;

  /// Whether the slot is unused.
  bool get isEmpty => name.isEmpty && secret.every((b) => b == 0);
}

/// A known contact advertised again (push).
final class AdvertPush extends MeshCoreFrame {
  const AdvertPush(this.publicKey);
  final Uint8List publicKey;
  @override
  bool get isPush => true;
}

/// The route to a contact changed (push).
final class PathUpdatedPush extends MeshCoreFrame {
  const PathUpdatedPush(this.publicKey);
  final Uint8List publicKey;
  @override
  bool get isPush => true;
}

/// A direct message was acknowledged (push).
final class SendConfirmedPush extends MeshCoreFrame {
  const SendConfirmedPush({required this.ackCode, required this.roundTripMs});
  final int ackCode;
  final int roundTripMs;
  @override
  bool get isPush => true;
}

/// Messages are queued; fetch them with SYNC_NEXT_MESSAGE (push).
final class MessagesWaitingPush extends MeshCoreFrame {
  const MessagesWaitingPush();
  @override
  bool get isPush => true;
}

/// A raw packet the radio heard, for diagnostics (push).
final class RxLogPush extends MeshCoreFrame {
  const RxLogPush({required this.snr, required this.rssi, required this.raw});
  final double snr;
  final int rssi;
  final Uint8List raw;
  @override
  bool get isPush => true;
}

/// The radio dropped a contact to make room (push).
final class ContactDeletedPush extends MeshCoreFrame {
  const ContactDeletedPush(this.publicKey);
  final Uint8List publicKey;
  @override
  bool get isPush => true;
}

/// The radio's contact list is full (push).
final class ContactsFullPush extends MeshCoreFrame {
  const ContactsFullPush();
  @override
  bool get isPush => true;
}

/// A frame this app doesn't decode yet.
final class UnknownFrame extends MeshCoreFrame {
  const UnknownFrame(this.code, this.data);
  final int code;
  final Uint8List data;
  @override
  bool get isPush => code >= 0x80;
}

/// A frame too short or malformed to decode.
final class MalformedFrame extends MeshCoreFrame {
  const MalformedFrame(this.code, this.reason);
  final int code;
  final String reason;
  @override
  bool get isPush => code >= 0x80;
}

/// Decodes one frame from the radio. Never throws.
MeshCoreFrame decodeFrame(Uint8List data) {
  if (data.isEmpty) return const MalformedFrame(-1, 'empty frame');
  final code = data[0];
  final r = ByteReader(data)..skip(1);
  try {
    return _decode(code, r, data);
  } on FrameTooShort catch (e) {
    return MalformedFrame(code, e.toString());
  }
}

double _snr(int raw) => raw / 4.0;

MeshCoreFrame _decode(int code, ByteReader r, Uint8List data) {
  switch (code) {
    case Resp.ok:
      return OkFrame(r.remaining >= 4 ? r.u32() : null);
    case Resp.err:
      return ErrorFrame(MeshCoreErrorCode.of(r.remaining >= 1 ? r.u8() : null));
    case Resp.disabled:
      return const DisabledFrame();
    case Resp.contactsStart:
      return ContactsStartFrame(r.u32());
    case Resp.contact:
      return _contact(r, fromNewAdvert: false);
    case Push.newAdvert:
      return _contact(r, fromNewAdvert: true);
    case Resp.endOfContacts:
      return EndOfContactsFrame(r.u32());
    case Resp.selfInfo:
      return _selfInfo(r);
    case Resp.sent:
      return SentFrame(
        flood: r.u8() == 1,
        ackCode: r.u32(),
        timeoutMs: r.u32(),
      );
    case Resp.contactMsg:
      return _contactMessage(r, snr: null);
    case Resp.contactMsgV3:
      {
        final snr = _snr(r.i8());
        r.skip(2);
        return _contactMessage(r, snr: snr);
      }
    case Resp.channelMsg:
      return _channelMessage(r, snr: null);
    case Resp.channelMsgV3:
      {
        final snr = _snr(r.i8());
        r.skip(2);
        return _channelMessage(r, snr: snr);
      }
    case Resp.channelData:
      {
        final snr = _snr(r.i8());
        r.skip(2);
        final channel = r.u8();
        final pathLength = r.u8();
        final dataType = r.u16();
        final length = r.u8();
        return ChannelDataFrame(
          channel: channel,
          pathLength: pathLength,
          dataType: dataType,
          payload: r.bytes(length),
          snr: snr,
        );
      }
    case Resp.currentTime:
      return CurrentTimeFrame(r.u32());
    case Resp.noMoreMessages:
      return const NoMoreMessagesFrame();
    case Resp.battAndStorage:
      {
        final mv = r.u16();
        if (r.remaining >= 8) {
          return BatteryFrame(
            millivolts: mv,
            usedKb: r.u32(),
            totalKb: r.u32(),
          );
        }
        return BatteryFrame(millivolts: mv);
      }
    case Resp.deviceInfo:
      return _deviceInfo(r);
    case Resp.channelInfo:
      return ChannelInfoFrame(
        index: r.u8(),
        name: r.fixedString(MeshCoreLimits.channelName),
        secret: r.bytes(MeshCoreLimits.channelSecret),
      );
    case Push.advert:
      return AdvertPush(r.bytes(MeshCoreLimits.publicKey));
    case Push.pathUpdated:
      return PathUpdatedPush(r.bytes(MeshCoreLimits.publicKey));
    case Push.sendConfirmed:
      return SendConfirmedPush(ackCode: r.u32(), roundTripMs: r.u32());
    case Push.messagesWaiting:
      return const MessagesWaitingPush();
    case Push.rxLog:
      return RxLogPush(snr: _snr(r.i8()), rssi: r.i8(), raw: r.rest());
    case Push.contactDeleted:
      return ContactDeletedPush(r.bytes(MeshCoreLimits.publicKey));
    case Push.contactsFull:
      return const ContactsFullPush();
    default:
      return UnknownFrame(code, Uint8List.fromList(data));
  }
}

ContactFrame _contact(ByteReader r, {required bool fromNewAdvert}) {
  final key = r.bytes(MeshCoreLimits.publicKey);
  final type = NodeType.of(r.u8());
  final flags = r.u8();
  final pathLength = r.u8();
  final pathField = r.bytes(MeshCoreLimits.pathField);
  final name = r.fixedString(32);
  final lastAdvert = r.u32();
  double? lat;
  double? lon;
  var lastModified = 0;
  if (r.remaining >= 8) {
    final rawLat = r.i32();
    final rawLon = r.i32();
    if (rawLat != 0 || rawLon != 0) {
      lat = rawLat / 1e6;
      lon = rawLon / 1e6;
    }
  }
  if (r.remaining >= 4) lastModified = r.u32();
  final used = pathLength == 0xff
      ? 0
      : (pathLength & 0x3f) * (((pathLength >> 6) & 0x3) + 1);
  return ContactFrame(
    publicKey: key,
    type: type,
    flags: flags,
    pathLength: pathLength,
    path: Uint8List.fromList(
      pathField.sublist(0, used.clamp(0, MeshCoreLimits.pathField)),
    ),
    name: name,
    lastAdvert: lastAdvert,
    latitude: lat,
    longitude: lon,
    lastModified: lastModified,
    fromNewAdvert: fromNewAdvert,
  );
}

SelfInfoFrame _selfInfo(ByteReader r) {
  return SelfInfoFrame(
    advertType: r.u8(),
    txPower: r.u8(),
    maxTxPower: r.u8(),
    publicKey: r.bytes(MeshCoreLimits.publicKey),
    latitude: r.i32() / 1e6,
    longitude: r.i32() / 1e6,
    multiAcks: r.u8(),
    advertLocationPolicy: r.u8(),
    telemetryMode: r.u8(),
    manualAddContacts: r.u8() != 0,
    frequencyMHz: r.u32() / 1000.0,
    bandwidthKHz: r.u32() / 1000.0,
    spreadingFactor: r.u8(),
    codingRate: r.u8(),
    name: decodeText(r.rest(), stopAtNull: true).trim(),
  );
}

ContactMessageFrame _contactMessage(ByteReader r, {required double? snr}) {
  final prefix = r.bytes(MeshCoreLimits.keyPrefix);
  final pathLength = r.u8();
  final type = TextType.of(r.u8());
  final timestamp = r.u32();
  final signature = type == TextType.signedPlain ? r.bytes(4) : null;
  return ContactMessageFrame(
    keyPrefix: prefix,
    pathLength: pathLength,
    textType: type,
    timestamp: timestamp,
    text: decodeText(r.rest(), stopAtNull: true),
    snr: snr,
    signature: signature,
  );
}

ChannelMessageFrame _channelMessage(ByteReader r, {required double? snr}) {
  return ChannelMessageFrame(
    channel: r.u8(),
    pathLength: r.u8(),
    textType: TextType.of(r.u8()),
    timestamp: r.u32(),
    text: decodeText(r.rest(), stopAtNull: true),
    snr: snr,
  );
}

DeviceInfoFrame _deviceInfo(ByteReader r) {
  final fw = r.u8();
  if (fw < 3 || r.remaining < 78) return DeviceInfoFrame(firmwareCode: fw);
  return DeviceInfoFrame(
    firmwareCode: fw,
    maxContacts: r.u8() * 2,
    maxChannels: r.u8(),
    blePin: r.u32(),
    buildDate: r.fixedString(12).trim(),
    model: r.fixedString(40).trim(),
    version: r.fixedString(20).trim(),
    clientRepeat: r.remaining >= 1 ? r.u8() != 0 : null,
    pathHashMode: r.remaining >= 1 ? r.u8() : null,
  );
}
