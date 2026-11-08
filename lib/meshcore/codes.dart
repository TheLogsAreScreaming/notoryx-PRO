/// Command, reply and push codes of the MeshCore companion protocol.
///
/// Values come from the MeshCore companion firmware (v1.18.0, protocol
/// version 14) and docs/companion_protocol.md in meshcore-dev/MeshCore.
abstract final class Cmd {
  static const appStart = 1;
  static const sendText = 2;
  static const sendChannelText = 3;
  static const getContacts = 4;
  static const getDeviceTime = 5;
  static const setDeviceTime = 6;
  static const sendSelfAdvert = 7;
  static const setAdvertName = 8;
  static const addUpdateContact = 9;
  static const syncNextMessage = 10;
  static const setRadioParams = 11;
  static const setTxPower = 12;
  static const resetPath = 13;
  static const setAdvertLatLon = 14;
  static const removeContact = 15;
  static const reboot = 19;
  static const getBattAndStorage = 20;
  static const deviceQuery = 22;
  static const sendLogin = 26;
  static const sendStatusRequest = 27;
  static const getChannel = 31;
  static const sendTracePath = 36;
  static const setOtherParams = 38;
  static const getStats = 56;
  static const setPathHashMode = 61;
  static const runCli = 66;
  static const setChannel = 32;
}

/// Replies to commands (below 0x80).
abstract final class Resp {
  static const ok = 0;
  static const err = 1;
  static const contactsStart = 2;
  static const contact = 3;
  static const endOfContacts = 4;
  static const selfInfo = 5;
  static const sent = 6;
  static const contactMsg = 7;
  static const channelMsg = 8;
  static const currentTime = 9;
  static const noMoreMessages = 10;
  static const battAndStorage = 12;
  static const deviceInfo = 13;
  static const disabled = 15;
  static const contactMsgV3 = 16;
  static const channelMsgV3 = 17;
  static const channelInfo = 18;
  static const stats = 24;
  static const channelData = 27;
  static const cliReply = 29;
}

/// Notifications the radio sends at any time (0x80 and up).
abstract final class Push {
  static const advert = 0x80;
  static const pathUpdated = 0x81;
  static const sendConfirmed = 0x82;
  static const messagesWaiting = 0x83;
  static const loginSuccess = 0x85;
  static const loginFail = 0x86;
  static const statusResponse = 0x87;
  static const rxLog = 0x88;
  static const traceData = 0x89;
  static const newAdvert = 0x8a;
  static const contactDeleted = 0x8f;
  static const contactsFull = 0x90;
}

/// Error codes carried by [Resp.err].
enum MeshCoreErrorCode {
  unsupported(1, 'The radio does not support this command'),
  notFound(2, 'Not found on the radio'),
  tableFull(3, 'The radio is busy or its table is full'),
  badState(4, 'The radio is busy with another request'),
  fileError(5, 'The radio could not save'),
  illegalArgument(6, 'The radio rejected a value'),
  unknown(0, 'The radio reported an error');

  const MeshCoreErrorCode(this.code, this.message);

  /// Byte value.
  final int code;

  /// Text to show people.
  final String message;

  /// The enum value for [code]; [unknown] if not listed.
  static MeshCoreErrorCode of(int? code) => values.firstWhere(
    (e) => e.code == code && e != unknown,
    orElse: () => unknown,
  );
}

/// Protocol limits.
abstract final class MeshCoreLimits {
  /// Largest frame the firmware accepts.
  static const maxFrame = 176;

  /// Largest message text in bytes.
  static const maxTextBytes = 160;

  /// Public key length.
  static const publicKey = 32;

  /// Bytes of public key used to address a direct message.
  static const keyPrefix = 6;

  /// Channel name field length.
  static const channelName = 32;

  /// Channel secret length.
  static const channelSecret = 16;

  /// Out-path field length in contact frames.
  static const pathField = 64;

  /// Protocol version this app understands, sent in DEVICE_QUERY.
  static const appProtocolVersion = 3;
}
