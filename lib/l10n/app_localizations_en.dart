// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NOTORYX PRO';

  @override
  String get tabInbox => 'Inbox';

  @override
  String get tabNodes => 'Nodes';

  @override
  String get tabRadios => 'Radios';

  @override
  String get protocolMeshCore => 'MeshCore';

  @override
  String get protocolMeshtastic => 'Meshtastic';

  @override
  String get inboxEmpty =>
      'No conversations yet. Connect a radio on the Radios tab.';

  @override
  String get inboxNoMessages => 'No messages yet';

  @override
  String get inboxChannelsHeader => 'Channels';

  @override
  String get inboxDirectHeader => 'Direct messages';

  @override
  String youPrefix(String text) {
    return 'You: $text';
  }

  @override
  String get nodesEmpty =>
      'No nodes yet. Nodes appear as your radios hear them.';

  @override
  String get nodeKindPerson => 'Person';

  @override
  String get nodeKindRelay => 'Relay';

  @override
  String get nodeKindRoom => 'Room';

  @override
  String get nodeKindSensor => 'Sensor';

  @override
  String get nodeKindUnknown => 'Node';

  @override
  String get nodeCannotMessage => 'Doesn\'t accept direct messages';

  @override
  String get radiosConnected => 'Connected radios';

  @override
  String get radiosNone => 'No radio connected. Find one below.';

  @override
  String get radiosFindBluetooth => 'Find Bluetooth radios';

  @override
  String get radiosAddWifi => 'Add Wi-Fi radio';

  @override
  String get radiosUsb => 'USB radios';

  @override
  String get radiosUsbNone => 'No USB radio plugged in.';

  @override
  String get radiosRefresh => 'Refresh';

  @override
  String get radiosScanTitle => 'Bluetooth radios';

  @override
  String get radiosScanning => 'Searching…';

  @override
  String get radiosScanNothing =>
      'No radios found yet. Make sure the radio is on and not connected to another phone.';

  @override
  String get radiosShowAll => 'Show all Bluetooth devices';

  @override
  String get radiosUnknownProtocol => 'Unknown';

  @override
  String get radiosPickProtocol => 'Which kind of radio is this?';

  @override
  String get radiosHost => 'Address';

  @override
  String get radiosHostHint => '192.168.1.40 or radio.local';

  @override
  String get radiosHostRequired => 'Enter the radio\'s address';

  @override
  String get radiosPort => 'Port';

  @override
  String get radiosPortInvalid => 'Use a port between 1 and 65535';

  @override
  String get radiosConnect => 'Connect';

  @override
  String get radiosCancel => 'Cancel';

  @override
  String get radiosDisconnect => 'Disconnect';

  @override
  String get radiosTryNow => 'Try now';

  @override
  String get statusStopped => 'Disconnected';

  @override
  String get statusConnecting => 'Connecting…';

  @override
  String get statusConnected => 'Connected';

  @override
  String statusReconnecting(int attempt) {
    return 'Reconnecting (attempt $attempt)';
  }

  @override
  String statusFailed(String reason) {
    return 'Stopped: $reason';
  }

  @override
  String radioFirmware(String version) {
    return 'Firmware $version';
  }

  @override
  String get composerHint => 'Message';

  @override
  String get composerSend => 'Send';

  @override
  String composerBytes(int used, int max) {
    return '$used/$max';
  }

  @override
  String get composerOffline => 'Connect this radio to send messages.';

  @override
  String get conversationEmpty => 'No messages yet. Say hello.';

  @override
  String get pathDirect => 'direct';

  @override
  String pathHops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hops',
      one: '1 hop',
      zero: 'heard directly',
    );
    return '$_temp0';
  }

  @override
  String pathSnr(String snr) {
    return 'SNR $snr dB';
  }

  @override
  String pathRssi(int rssi) {
    return '$rssi dBm';
  }

  @override
  String get pathMqtt => 'via internet';

  @override
  String get deliveryPending => 'Sending';

  @override
  String get deliverySent => 'Sent';

  @override
  String get deliveryRelayed => 'Heard repeated';

  @override
  String get deliveryDelivered => 'Delivered';

  @override
  String deliveryFailed(String reason) {
    return 'Not delivered: $reason';
  }

  @override
  String get channelPrimary => 'Primary';

  @override
  String lastHeard(String when) {
    return 'Heard $when';
  }

  @override
  String get agoNow => 'just now';

  @override
  String agoMinutes(int count) {
    return '$count min ago';
  }

  @override
  String agoHours(int count) {
    return '$count h ago';
  }

  @override
  String agoDays(int count) {
    return '$count d ago';
  }
}
