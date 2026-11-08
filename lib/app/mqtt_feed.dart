import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../mesh/mesh.dart';
import '../meshcore/raw_packet.dart';
import '../meshtastic/meshtastic.dart';
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';
import 'radio_connection.dart';

/// Where one MQTT feed comes from.
class MqttFeedConfig {
  const MqttFeedConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.topic,
    this.port = 1883,
    this.tls = false,
    this.username = '',
    this.password = '',
  });

  factory MqttFeedConfig.fromJson(Map<String, dynamic> j) => MqttFeedConfig(
    id: j['id'] as String,
    name: j['name'] as String,
    protocol: RadioProtocol.values.byName(j['protocol'] as String),
    host: j['host'] as String,
    topic: j['topic'] as String,
    port: j['port'] as int,
    tls: j['tls'] as bool,
    username: j['username'] as String,
    password: j['password'] as String,
  );

  final String id;
  final String name;
  final RadioProtocol protocol;
  final String host;
  final String topic;
  final int port;
  final bool tls;
  final String username;
  final String password;

  /// A topic to start from, for each mesh's usual layout.
  static String defaultTopic(RadioProtocol p) => switch (p) {
    RadioProtocol.meshtastic => 'msh/US/2/e/#',
    RadioProtocol.meshcore => 'meshcore/+/+/packets',
  };

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'host': host,
    'topic': topic,
    'port': port,
    'tls': tls,
    'username': username,
    'password': password,
  };
}

/// Turns one MQTT message into a log entry; null if it isn't a packet this
/// app can read. Broker data is untrusted, so nothing here may throw.
PacketLogEntry? parseFeedMessage(
  RadioProtocol protocol,
  Uint8List payload,
  DateTime now,
) {
  try {
    return switch (protocol) {
      RadioProtocol.meshtastic => _meshtastic(payload, now),
      RadioProtocol.meshcore => _meshcore(payload, now),
    };
  } on ProtobufException {
    return null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  } on RangeError {
    return null;
  }
}

/// A Meshtastic `ServiceEnvelope`: packet, channel name and gateway.
PacketLogEntry? _meshtastic(Uint8List payload, DateTime now) {
  MeshPacket? packet;
  var channel = '';
  var gateway = '';
  for (final f in readFields(payload)) {
    switch (f.number) {
      case 1:
        packet = MeshPacket.decode(f.asBytes);
      case 2:
        channel = f.asString;
      case 3:
        gateway = f.asString;
    }
  }
  final p = packet;
  if (p == null || p.from == 0) return null;
  final data = p.decoded;
  return PacketLogEntry(
    time: now,
    protocol: RadioProtocol.meshtastic,
    kind: data == null
        ? 'Encrypted'
        : MeshtasticConnection.portName(data.portnum),
    from: meshtasticNodeId(p.from),
    to: p.isBroadcast ? null : meshtasticNodeId(p.to),
    path: PathFacts(
      hops: p.hopsTaken,
      snr: p.rxSnr,
      rssi: p.rxRssi,
      viaMqtt: true,
    ),
    bytes: data?.payload.length ?? p.encrypted?.length,
    detail: [channel, gateway].where((s) => s.isNotEmpty).join(' · '),
    encrypted: data == null,
  );
}

/// A MeshCore observer's JSON report. Only `raw` (hex) is required.
PacketLogEntry? _meshcore(Uint8List payload, DateTime now) {
  final j = jsonDecode(utf8.decode(payload));
  if (j is! Map<String, dynamic>) return null;
  final hex = j['raw'];
  if (hex is! String || hex.isEmpty || hex.length.isOdd) return null;
  final raw = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final info = MeshCorePacketInfo.parse(raw);
  if (info == null) return null;
  double? number(String key) => switch (j[key]) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
  final origin = j['origin'];
  return PacketLogEntry(
    time: now,
    protocol: RadioProtocol.meshcore,
    kind: info.payload.label,
    path: PathFacts(
      hops: info.hops,
      snr: number('SNR'),
      rssi: number('RSSI')?.round(),
      route: info.isFlood ? RouteKind.flood : RouteKind.direct,
    ),
    bytes: raw.length,
    detail: [
      if (origin is String && origin.isNotEmpty) origin,
      if (info.path.isNotEmpty) info.pathText,
    ].join(' · '),
    encrypted: true,
  );
}

/// A connection to a broker; replaceable in tests.
abstract interface class MqttBroker {
  /// Connects and subscribes; throws if it can't.
  Future<void> open({
    required void Function(Uint8List payload) onMessage,
    required void Function(bool connected) onConnection,
  });

  Future<void> close();
}

/// Makes the broker connection for a feed.
typedef MqttBrokerFactory = MqttBroker Function(MqttFeedConfig config);

/// The real broker connection. It only ever subscribes: feeds are for
/// watching, and nothing from the radios is published.
class _ServerBroker implements MqttBroker {
  _ServerBroker(this.config);

  final MqttFeedConfig config;
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;

  @override
  Future<void> open({
    required void Function(Uint8List payload) onMessage,
    required void Function(bool connected) onConnection,
  }) async {
    final id = Random.secure().nextInt(1 << 32).toRadixString(16);
    final client = MqttServerClient.withPort(
      config.host,
      'notoryx-pro-$id',
      config.port,
    );
    _client = client;
    client
      ..secure = config.tls
      ..keepAlivePeriod = 60
      ..autoReconnect = true
      ..logging(on: false)
      ..setProtocolV311()
      ..onAutoReconnect = (() => onConnection(false))
      ..onAutoReconnected = (() => onConnection(true));
    await client.connect(
      config.username.isEmpty ? null : config.username,
      config.username.isEmpty ? null : config.password,
    );
    _updates = client.updates!.listen((batch) {
      for (final m in batch) {
        final publish = m.payload;
        if (publish is MqttPublishMessage) {
          onMessage(Uint8List.fromList(publish.payload.message));
        }
      }
    });
    client.subscribe(config.topic, MqttQos.atMostOnce);
    onConnection(true);
  }

  @override
  Future<void> close() async {
    await _updates?.cancel();
    final client = _client;
    if (client != null) {
      client.autoReconnect = false;
      client.disconnect();
    }
  }
}

/// Where a feed is up to.
enum MqttFeedState { off, connecting, connected, failed }

/// One feed and its live packet log.
class MqttFeed extends ChangeNotifier {
  MqttFeed(this.config, this._factory);

  final MqttFeedConfig config;
  final MqttBrokerFactory _factory;
  final PacketLog log = PacketLog();
  MqttBroker? _broker;

  MqttFeedState state = MqttFeedState.off;

  /// Why the last attempt failed.
  String? error;

  void _set(MqttFeedState s) {
    state = s;
    notifyListeners();
  }

  Future<void> start() async {
    if (_broker != null) return;
    final broker = _factory(config);
    _broker = broker;
    error = null;
    _set(MqttFeedState.connecting);
    try {
      await broker.open(
        onMessage: (payload) {
          final e = parseFeedMessage(config.protocol, payload, DateTime.now());
          if (e != null) log.add(e);
        },
        onConnection: (up) {
          if (identical(_broker, broker)) {
            _set(up ? MqttFeedState.connected : MqttFeedState.connecting);
          }
        },
      );
    } on Object catch (e) {
      if (!identical(_broker, broker)) return;
      _broker = null;
      error = '$e';
      _set(MqttFeedState.failed);
      unawaited(broker.close().catchError((Object _) {}));
    }
  }

  Future<void> stop() async {
    final broker = _broker;
    _broker = null;
    _set(MqttFeedState.off);
    await broker?.close();
  }
}

/// The saved feeds. Feeds only run when switched on.
class MqttFeeds extends ChangeNotifier {
  MqttFeeds(this.store, {MqttBrokerFactory? brokers})
    : _factory = brokers ?? _ServerBroker.new;

  static const _preference = 'mqtt.feeds';

  final MeshStore store;
  final MqttBrokerFactory _factory;
  List<MqttFeed> _feeds = const [];
  bool _loaded = false;

  List<MqttFeed> get feeds => List.unmodifiable(_feeds);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final text = await store.preference(_preference);
    if (text == null) return;
    _feeds = [
      for (final j in jsonDecode(text) as List<dynamic>)
        _watch(MqttFeedConfig.fromJson(j as Map<String, dynamic>)),
    ];
    notifyListeners();
  }

  MqttFeed _watch(MqttFeedConfig c) =>
      MqttFeed(c, _factory)..addListener(notifyListeners);

  Future<void> _save() => store.setPreference(
    _preference,
    jsonEncode([for (final f in _feeds) f.config.toJson()]),
  );

  Future<void> add(MqttFeedConfig config) async {
    _feeds = [..._feeds, _watch(config)];
    notifyListeners();
    await _save();
  }

  Future<void> remove(MqttFeed feed) async {
    await feed.stop();
    feed.removeListener(notifyListeners);
    _feeds = [
      for (final f in _feeds)
        if (!identical(f, feed)) f,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> stopAll() async {
    for (final f in _feeds) {
      await f.stop();
    }
  }
}
