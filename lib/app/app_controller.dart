import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../mesh/channel_links.dart';
import '../mesh/model.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'channel_bridge.dart';
import 'checklists.dart';
import 'auto_responder.dart';
import 'automations.dart';
import 'distress_beacon.dart';
import 'geofence_alerts.dart';
import 'message_alerts.dart';
import 'message_scheduler.dart';
import 'sentinel.dart';
import 'timeline.dart';
import 'mqtt_feed.dart';
import 'radio_connection.dart';
import 'radio_target.dart';
import 'retry_policy.dart';

/// App-wide state: the store and the connected radios: up to [maxRadios]
/// of them, from either mesh.
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    this.links = const LinkFactory(),
    ConnectionLog? log,
    this.retryDelays,
    this.retries = const RetryPolicy(),
    Notifier? notifier,
  }) : log = log ?? ConnectionLog(),
       alerts = notifier == null
           ? null
           : MessageAlerts(store: store, notifier: notifier),
       geofences = notifier == null
           ? null
           : GeofenceAlerts(store: store, notifier: notifier);

  /// Message notifications; null when there is no notifier (tests).
  final MessageAlerts? alerts;

  /// Geofence crossings; null when there is no notifier (tests).
  final GeofenceAlerts? geofences;

  final MeshStore store;
  final LinkFactory links;
  final ConnectionLog log;
  final List<Duration>? retryDelays;

  /// Delivery retry settings for every connection.
  final RetryPolicy retries;
  final Map<String, RadioConnection> _connections = {};

  /// Read-only MQTT feeds.
  late final MqttFeeds feeds = MqttFeeds(store);

  /// Opt-in links between MeshCore and Meshtastic conversations.
  late final ChannelBridge bridge = ChannelBridge(store, send: _bridgeSend);

  Future<bool> _bridgeSend(Conversation to, String text) async {
    final c = connectionForRadio(to.radioId);
    if (c == null) return false;
    await c.sendText(to, text);
    return true;
  }

  /// Most radios connected at once (Bluetooth adapters and phones cope
  /// badly with more).
  static const maxRadios = 4;

  /// Connected (or reconnecting) radios, in the order they were added.
  List<RadioConnection> get connections =>
      List.unmodifiable(_connections.values);

  /// The connection for the radio [id], if it is connected.
  RadioConnection? connectionForRadio(RadioId id) {
    for (final c in _connections.values) {
      if (c.radio?.id == id) return c;
    }
    return null;
  }

  /// Whether another radio can be added.
  bool get canAddRadio => _connections.length < maxRadios;

  /// Connects to [target]. Reconnecting to the same radio replaces its old
  /// connection; other radios, of either mesh, stay connected.
  Future<RadioConnection> connect(RadioTarget target) async {
    final existing = _connections[target.address];
    if (existing != null) await disconnect(existing);
    if (!canAddRadio) throw const TooManyRadios(maxRadios);
    final c = RadioConnection.forTarget(
      target,
      store: store,
      log: log,
      links: links,
      retryDelays: retryDelays,
      retries: retries,
    );
    c.addListener(notifyListeners);
    _connections[target.address] = c;
    notifyListeners();
    await bridge.load();
    await c.start();
    return c;
  }

  /// Rules with triggers and actions (off until the person adds some).
  late final automations = AutomationEngine(
    store: store,
    hooks: AutomationHooks(
      send: _sendScheduled,
      alert: (title, body) async => alerts?.notifier.show(
        id: 0x30000000 | (title.hashCode & 0xfffffff),
        title: title,
        body: body,
        payload: 'automation',
      ),
      playSound: () => SystemSound.play(SystemSoundType.alert),
      joinChannel: (radio, link) async {
        final c = connectionForRadio(radio);
        if (c == null || c.status.phase != SupervisorPhase.connected) {
          return false;
        }
        final invite = ChannelInvite.parse(
          link,
        ).where((i) => i.protocol == c.protocol).firstOrNull;
        if (invite == null) {
          throw const FormatException('No channel for this radio in the link');
        }
        await c.addChannel(invite);
        return true;
      },
      post: (url, json) async =>
          (await http
                  .post(
                    url,
                    headers: const {'content-type': 'application/json'},
                    body: json,
                  )
                  .timeout(const Duration(seconds: 10)))
              .statusCode,
    ),
  );

  /// Automatic replies.
  late final responder = AutoResponder(store: store, send: _sendScheduled);

  /// Offline checklists and their saved records.
  late final checklists = ChecklistBook(store);

  /// New nodes, signal changes and new places, for the timeline.
  late final timeline = TimelineRecorder(store);

  /// Messages to send later.
  late final scheduler = MessageScheduler(store: store, send: _sendScheduled);

  /// Opt-in community moderation (off until the user turns it on).
  late final sentinel = SentinelService(
    read: store.preference,
    write: store.setPreference,
  );

  Future<bool> _sendScheduled(Conversation c, String text) async {
    final radio = connectionForRadio(c.radioId);
    if (radio == null || radio.status.phase != SupervisorPhase.connected) {
      return false;
    }
    await radio.sendText(c, text);
    return true;
  }

  /// The distress beacon running now, if any.
  final beacon = ValueNotifier<DistressBeacon?>(null);
  RadioConnection? _beaconRadio;

  /// Notification ID of a running beacon.
  static const beaconNoticeId = 2;

  /// Starts a distress beacon on [conversation]; one at a time.
  Future<void> startBeacon(
    RadioConnection connection,
    Conversation conversation, {
    required Duration every,
    required Duration lasts,
    required String noticeTitle,
    required String noticeBody,
    required String noticeStop,
    String note = '',
    bool drill = false,
    bool shortPosition = false,
  }) async {
    if (beacon.value != null) return;
    final b = DistressBeacon(
      conversation: conversation,
      every: every,
      lasts: lasts,
      note: note,
      drill: drill,
      shortPosition: shortPosition,
      maxBytes: connection.maxTextBytes,
      incoming: store.incoming,
      send: (text) async {
        if (!connections.contains(connection)) {
          throw StateError('Radio disconnected');
        }
        await connection.sendText(conversation, text);
      },
      position: () async {
        final radio = connection.radio;
        final p =
            radio?.position ??
            (radio == null
                ? null
                : (await store.node(radio.id, radio.self))?.position);
        return p == null ? null : (p.latitude, p.longitude);
      },
    );
    b.addListener(() {
      if (b.active || !identical(beacon.value, b)) return;
      beacon.value = null;
      _beaconRadio = null;
      unawaited(alerts?.notifier.cancel(beaconNoticeId));
    });
    beacon.value = b;
    _beaconRadio = connection;
    unawaited(
      alerts?.notifier.showBeacon(
        id: beaconNoticeId,
        title: noticeTitle,
        body: noticeBody,
        stopLabel: noticeStop,
        payload: conversation.key,
      ),
    );
    await b.start();
  }

  /// Disconnects [connection].
  Future<void> disconnect(RadioConnection connection) async {
    final key = _connections.entries
        .where((e) => identical(e.value, connection))
        .map((e) => e.key)
        .firstOrNull;
    if (key == null) return;
    if (identical(_beaconRadio, connection)) await beacon.value?.stop();
    _connections.remove(key);
    connection.removeListener(notifyListeners);
    notifyListeners();
    await connection.stop();
    await connection.close();
  }

  /// Disconnects every radio and waits until they have finished.
  Future<void> shutdown() async {
    automations.stop();
    scheduler.stop();
    responder.stop();
    await timeline.stop();
    await beacon.value?.stop();
    await alerts?.dispose();
    await feeds.stopAll();
    await bridge.stop();
    for (final c in [..._connections.values]) {
      await disconnect(c);
    }
  }

  @override
  void dispose() {
    for (final c in [..._connections.values]) {
      disconnect(c);
    }
    sentinel.dispose();
    super.dispose();
  }
}

/// Thrown when connecting would exceed [AppController.maxRadios].
class TooManyRadios implements Exception {
  const TooManyRadios(this.max);
  final int max;
  @override
  String toString() => 'TooManyRadios: at most $max radios';
}
