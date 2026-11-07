import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'NOTORYX PRO'**
  String get appTitle;

  /// No description provided for @tabInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get tabInbox;

  /// No description provided for @tabNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get tabNodes;

  /// No description provided for @tabRadios.
  ///
  /// In en, this message translates to:
  /// **'Radios'**
  String get tabRadios;

  /// No description provided for @protocolMeshCore.
  ///
  /// In en, this message translates to:
  /// **'MeshCore'**
  String get protocolMeshCore;

  /// No description provided for @protocolMeshtastic.
  ///
  /// In en, this message translates to:
  /// **'Meshtastic'**
  String get protocolMeshtastic;

  /// No description provided for @inboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet. Connect a radio on the Radios tab.'**
  String get inboxEmpty;

  /// No description provided for @inboxNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get inboxNoMessages;

  /// No description provided for @inboxChannelsHeader.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get inboxChannelsHeader;

  /// No description provided for @inboxDirectHeader.
  ///
  /// In en, this message translates to:
  /// **'Direct messages'**
  String get inboxDirectHeader;

  /// No description provided for @youPrefix.
  ///
  /// In en, this message translates to:
  /// **'You: {text}'**
  String youPrefix(String text);

  /// No description provided for @nodesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No nodes yet. Nodes appear as your radios hear them.'**
  String get nodesEmpty;

  /// No description provided for @nodeKindPerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get nodeKindPerson;

  /// No description provided for @nodeKindRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get nodeKindRelay;

  /// No description provided for @nodeKindRoom.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get nodeKindRoom;

  /// No description provided for @nodeKindSensor.
  ///
  /// In en, this message translates to:
  /// **'Sensor'**
  String get nodeKindSensor;

  /// No description provided for @nodeKindUnknown.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get nodeKindUnknown;

  /// No description provided for @nodeCannotMessage.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t accept direct messages'**
  String get nodeCannotMessage;

  /// No description provided for @radiosConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected radios'**
  String get radiosConnected;

  /// No description provided for @radiosNone.
  ///
  /// In en, this message translates to:
  /// **'No radio connected. Find one below.'**
  String get radiosNone;

  /// No description provided for @radiosFindBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Find Bluetooth radios'**
  String get radiosFindBluetooth;

  /// No description provided for @radiosAddWifi.
  ///
  /// In en, this message translates to:
  /// **'Add Wi-Fi radio'**
  String get radiosAddWifi;

  /// No description provided for @radiosUsb.
  ///
  /// In en, this message translates to:
  /// **'USB radios'**
  String get radiosUsb;

  /// No description provided for @radiosUsbNone.
  ///
  /// In en, this message translates to:
  /// **'No USB radio plugged in.'**
  String get radiosUsbNone;

  /// No description provided for @radiosRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get radiosRefresh;

  /// No description provided for @radiosScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth radios'**
  String get radiosScanTitle;

  /// No description provided for @radiosScanning.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get radiosScanning;

  /// No description provided for @radiosScanNothing.
  ///
  /// In en, this message translates to:
  /// **'No radios found yet. Make sure the radio is on and not connected to another phone.'**
  String get radiosScanNothing;

  /// No description provided for @radiosShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all Bluetooth devices'**
  String get radiosShowAll;

  /// No description provided for @radiosUnknownProtocol.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get radiosUnknownProtocol;

  /// No description provided for @radiosPickProtocol.
  ///
  /// In en, this message translates to:
  /// **'Which kind of radio is this?'**
  String get radiosPickProtocol;

  /// No description provided for @radiosHost.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get radiosHost;

  /// No description provided for @radiosHostHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.40 or radio.local'**
  String get radiosHostHint;

  /// No description provided for @radiosHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the radio\'s address'**
  String get radiosHostRequired;

  /// No description provided for @radiosPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get radiosPort;

  /// No description provided for @radiosPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a port between 1 and 65535'**
  String get radiosPortInvalid;

  /// No description provided for @radiosConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get radiosConnect;

  /// No description provided for @radiosCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get radiosCancel;

  /// No description provided for @radiosDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get radiosDisconnect;

  /// No description provided for @radiosTryNow.
  ///
  /// In en, this message translates to:
  /// **'Try now'**
  String get radiosTryNow;

  /// No description provided for @statusStopped.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get statusStopped;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get statusConnecting;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting (attempt {attempt})'**
  String statusReconnecting(int attempt);

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Stopped: {reason}'**
  String statusFailed(String reason);

  /// No description provided for @radioFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware {version}'**
  String radioFirmware(String version);

  /// No description provided for @composerHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get composerHint;

  /// No description provided for @composerSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get composerSend;

  /// No description provided for @composerBytes.
  ///
  /// In en, this message translates to:
  /// **'{used}/{max}'**
  String composerBytes(int used, int max);

  /// No description provided for @composerOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect this radio to send messages.'**
  String get composerOffline;

  /// No description provided for @conversationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Say hello.'**
  String get conversationEmpty;

  /// No description provided for @pathDirect.
  ///
  /// In en, this message translates to:
  /// **'direct'**
  String get pathDirect;

  /// No description provided for @pathHops.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{heard directly} =1{1 hop} other{{count} hops}}'**
  String pathHops(int count);

  /// No description provided for @pathSnr.
  ///
  /// In en, this message translates to:
  /// **'SNR {snr} dB'**
  String pathSnr(String snr);

  /// No description provided for @pathRssi.
  ///
  /// In en, this message translates to:
  /// **'{rssi} dBm'**
  String pathRssi(int rssi);

  /// No description provided for @pathMqtt.
  ///
  /// In en, this message translates to:
  /// **'via internet'**
  String get pathMqtt;

  /// No description provided for @deliveryPending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get deliveryPending;

  /// No description provided for @deliverySent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get deliverySent;

  /// No description provided for @deliveryRelayed.
  ///
  /// In en, this message translates to:
  /// **'Heard repeated'**
  String get deliveryRelayed;

  /// No description provided for @deliveryDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get deliveryDelivered;

  /// No description provided for @deliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Not delivered: {reason}'**
  String deliveryFailed(String reason);

  /// No description provided for @channelPrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get channelPrimary;

  /// No description provided for @lastHeard.
  ///
  /// In en, this message translates to:
  /// **'Heard {when}'**
  String lastHeard(String when);

  /// No description provided for @agoNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get agoNow;

  /// No description provided for @agoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String agoMinutes(int count);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String agoHours(int count);

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String agoDays(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
