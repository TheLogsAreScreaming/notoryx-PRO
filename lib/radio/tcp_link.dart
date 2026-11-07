import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'connection_log.dart';
import 'radio_link.dart';

/// Opens a socket; replaceable in tests.
typedef SocketConnector =
    Future<Socket> Function(String host, int port, Duration timeout);

Future<Socket> _connectSocket(String host, int port, Duration timeout) =>
    Socket.connect(host, port, timeout: timeout);

/// A radio reached over Wi-Fi or Ethernet.
///
/// MeshCore companions listen on port 5000 and Meshtastic nodes on 4403;
/// both send a framed byte stream, so [deliversFrames] is false.
class TcpRadioLink extends BaseRadioLink {
  TcpRadioLink({
    required this.host,
    required this.protocol,
    int? port,
    this.timeout = const Duration(seconds: 10),
    ConnectionLog? log,
    SocketConnector connector = _connectSocket,
  }) : port = port ?? defaultPort(protocol),
       _log = log,
       _connector = connector;

  /// The usual TCP port for each protocol.
  static int defaultPort(RadioProtocol protocol) => switch (protocol) {
    RadioProtocol.meshcore => 5000,
    RadioProtocol.meshtastic => 4403,
  };

  /// Host name or IP address of the radio.
  final String host;

  /// TCP port.
  final int port;

  /// How long to wait for the connection.
  final Duration timeout;

  @override
  final RadioProtocol protocol;

  final ConnectionLog? _log;
  final SocketConnector _connector;
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;

  @override
  LinkKind get kind => LinkKind.tcp;

  @override
  String get label => '$host:$port';

  @override
  bool get deliversFrames => false;

  String get _source => 'TCP ${ConnectionLog.redactHost(host)}:$port';

  @override
  Future<void> open() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    setState(LinkState.connecting);
    _log?.add(_source, 'connecting');
    try {
      final socket = await _connector(host, port, timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _subscription = socket.listen(
        deliver,
        onError: (Object error) {
          _log?.add(_source, 'error: $error');
          _dropped();
        },
        onDone: _dropped,
        cancelOnError: true,
      );
      setState(LinkState.connected);
      _log?.add(_source, 'connected');
    } on Object catch (error) {
      _log?.add(_source, 'connect failed: $error');
      setState(LinkState.disconnected);
      throw LinkException('Could not reach $label', error);
    }
  }

  void _dropped() {
    if (state == LinkState.disconnected) return;
    _log?.add(_source, 'connection closed');
    _teardown();
    setState(LinkState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {
    requireConnected();
    _socket!.add(data);
    await _socket!.flush();
  }

  @override
  Future<void> close() async {
    if (state == LinkState.idle || state == LinkState.disconnected) return;
    _log?.add(_source, 'disconnecting');
    final socket = _socket;
    _teardown();
    setState(LinkState.disconnected);
    try {
      await socket?.close();
    } on Object catch (_) {
      // Already gone; nothing to do.
    }
    socket?.destroy();
  }

  void _teardown() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket = null;
  }
}
