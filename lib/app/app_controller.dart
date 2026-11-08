import 'mqtt_feed.dart';
import 'package:flutter/foundation.dart';

import '../mesh/model.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'message_alerts.dart';
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
           : MessageAlerts(store: store, notifier: notifier);

  /// Message notifications; null when there is no notifier (tests).
  final MessageAlerts? alerts;

  final MeshStore store;
  final LinkFactory links;
  final ConnectionLog log;
  final List<Duration>? retryDelays;

  /// Delivery retry settings for every connection.
  final RetryPolicy retries;
  final Map<String, RadioConnection> _connections = {};

  /// Read-only MQTT feeds.
  late final MqttFeeds feeds = MqttFeeds(store);

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
    await c.start();
    return c;
  }

  /// Disconnects [connection].
  Future<void> disconnect(RadioConnection connection) async {
    final key = _connections.entries
        .where((e) => identical(e.value, connection))
        .map((e) => e.key)
        .firstOrNull;
    if (key == null) return;
    _connections.remove(key);
    connection.removeListener(notifyListeners);
    notifyListeners();
    await connection.stop();
    await connection.close();
  }

  /// Disconnects every radio and waits until they have finished.
  Future<void> shutdown() async {
    await alerts?.dispose();
    await feeds.stopAll();
    for (final c in [..._connections.values]) {
      await disconnect(c);
    }
  }

  @override
  void dispose() {
    for (final c in [..._connections.values]) {
      disconnect(c);
    }
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
