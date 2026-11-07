import 'package:flutter/foundation.dart';

import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'radio_connection.dart';
import 'radio_target.dart';

/// App-wide state: the store and the connected radios (at most one per
/// protocol, so a MeshCore and a Meshtastic radio can be used together).
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    this.links = const LinkFactory(),
    ConnectionLog? log,
    this.retryDelays,
  }) : log = log ?? ConnectionLog();

  final MeshStore store;
  final LinkFactory links;
  final ConnectionLog log;
  final List<Duration>? retryDelays;
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

  @override
  void dispose() {
    for (final p in RadioProtocol.values) {
      disconnect(p);
    }
    super.dispose();
  }
}
