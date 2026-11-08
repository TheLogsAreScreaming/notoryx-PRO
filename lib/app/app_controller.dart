import 'package:flutter/foundation.dart';

import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'message_alerts.dart';
import 'radio_connection.dart';
import 'radio_target.dart';
import 'retry_policy.dart';

/// App-wide state: the store and the connected radios (at most one per
/// protocol, so a MeshCore and a Meshtastic radio can be used together).
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
  final Map<RadioProtocol, RadioConnection> _connections = {};

  /// Connected (or reconnecting) radios.
  List<RadioConnection> get connections =>
      List.unmodifiable(_connections.values);

  /// The connection for [protocol], if any.
  RadioConnection? connectionFor(RadioProtocol protocol) =>
      _connections[protocol];

  /// Connects to [target], replacing any radio of the same protocol.
  Future<RadioConnection> connect(RadioTarget target) async {
    await disconnect(target.protocol);
    final c = RadioConnection.forTarget(
      target,
      store: store,
      log: log,
      links: links,
      retryDelays: retryDelays,
      retries: retries,
    );
    c.addListener(notifyListeners);
    _connections[target.protocol] = c;
    notifyListeners();
    await c.start();
    return c;
  }

  /// Disconnects the radio for [protocol], if any.
  Future<void> disconnect(RadioProtocol protocol) async {
    final c = _connections.remove(protocol);
    if (c == null) return;
    c.removeListener(notifyListeners);
    notifyListeners();
    await c.stop();
    await c.close();
  }

  /// Disconnects every radio and waits until they have finished.
  Future<void> shutdown() async {
    await alerts?.dispose();
    for (final p in RadioProtocol.values) {
      await disconnect(p);
    }
  }

  @override
  void dispose() {
    for (final p in RadioProtocol.values) {
      disconnect(p);
    }
    super.dispose();
  }
}
