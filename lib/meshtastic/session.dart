import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../radio/connection_log.dart';
import '../radio/radio_link.dart';
import 'admin.dart';
import 'firmware.dart';
import 'messages.dart';
import 'protobuf.dart';
import 'stream_framing.dart';

/// The node didn't finish sending its config in time.
class MeshtasticTimeout implements Exception {
  const MeshtasticTimeout(this.what);
  final String what;
  @override
  String toString() => 'MeshtasticTimeout: $what';
}

/// Everything the node sent during the config download.
class MeshtasticConfig {
  const MeshtasticConfig({
    required this.myInfo,
    required this.metadata,
    required this.nodes,
    required this.channels,
    required this.configSections,
    required this.moduleSections,
    this.config = const {},
  });

  /// `Config` sections by oneof field number (e.g. 6 for LoRa), each the
  /// section's own bytes.
  final Map<int, Uint8List> config;

  /// The LoRa section, when the node sent one.
  SettingsSection? get lora => config[SectionKind.lora.field] == null
      ? null
      : SettingsSection(SectionKind.lora, config[SectionKind.lora.field]!);

  final MyNodeInfo myInfo;
  final DeviceMetadata? metadata;

  /// The node database, by node number (including this node).
  final Map<int, MeshNodeInfo> nodes;

  /// Channel slots in index order.
  final List<MeshChannel> channels;

  /// How many `Config` and `ModuleConfig` sections arrived (kept raw for
  /// the admin step).
  final int configSections;
  final int moduleSections;

  /// This node's own entry, if it sent one.
  MeshNodeInfo? get self => nodes[myInfo.nodeNum];
}

/// A received text message, with how it arrived.
class MeshtasticText {
  const MeshtasticText({
    required this.packet,
    required this.text,
    required this.isDirect,
  });

  final MeshPacket packet;
  final String text;

  /// Sent to this node rather than to a channel.
  final bool isDirect;

  int get from => packet.from;
  int get channel => packet.channel;
  int get id => packet.id;
  int? get hops => packet.hopsTaken;
  double? get snr => packet.rxSnr;
  int? get rssi => packet.rxRssi;
  bool get viaMqtt => packet.viaMqtt;

  /// Message this replies to, or 0.
  int get replyId => packet.decoded?.replyId ?? 0;

  /// Whether this is an emoji reaction to [replyId].
  bool get isReaction => (packet.decoded?.emoji ?? 0) != 0;
}

/// Where a sent packet got to.
enum DeliveryStatus {
  /// The node accepted it into its send queue.
  queued,

  /// Another node was heard repeating it (all a broadcast can get).
  relayed,

  /// The recipient acknowledged it.
  delivered,

  /// It failed; see [DeliveryUpdate.error].
  failed,
}

/// A change in a sent packet's delivery.
class DeliveryUpdate {
  const DeliveryUpdate(this.packetId, this.status, {this.error, this.from});

  final int packetId;
  final DeliveryStatus status;
  final RoutingError? error;

  /// Node that reported it.
  final int? from;

  @override
  String toString() => 'DeliveryUpdate($packetId, $status, $error)';
}

/// News about another node: its names, position or how it was last heard.
class NodeUpdate {
  const NodeUpdate({
    required this.num,
    this.user,
    this.position,
    this.snr,
    this.hops,
    this.viaMqtt = false,
  });

  final int num;
  final MeshUser? user;
  final MeshPosition? position;
  final double? snr;
  final int? hops;
  final bool viaMqtt;
}

/// Talks to a Meshtastic node over any [RadioLink].
///
/// [handshake] downloads the node's config and refuses firmware older than
/// [MeshtasticFirmware.minimum] before anything is written to the node.
/// Afterwards a heartbeat keeps USB and TCP connections open, text messages
/// arrive on [texts], acks and failures on [deliveries], and node news on
/// [nodes].
class MeshtasticSession {
  MeshtasticSession(
    this.link, {
    this.configTimeout = const Duration(seconds: 120),
    this.heartbeatInterval = const Duration(minutes: 5),
    ConnectionLog? log,
    Random? random,
  }) : _log = log,
       _random = random ?? Random.secure();

  final RadioLink link;

  /// How long the config download may take (large node databases are slow
  /// over Bluetooth).
  final Duration configTimeout;

  /// Time between heartbeats.
  final Duration heartbeatInterval;

  final ConnectionLog? _log;
  final Random _random;
  final _events = StreamController<FromRadio>.broadcast();
  final _texts = StreamController<MeshtasticText>.broadcast();
  final _deliveries = StreamController<DeliveryUpdate>.broadcast();
  final _nodes = StreamController<NodeUpdate>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  final Map<int, int> _sent = {}; // packet id -> destination
  MeshtasticFrameDecoder? _decoder;
  Timer? _heartbeat;
  bool _attached = false;
  bool _woken = false;
  int? _myNode;

  /// Every `FromRadio`, decoded.
  Stream<FromRadio> get events => _events.stream;

  /// Text messages from other nodes.
  Stream<MeshtasticText> get texts => _texts.stream;

  /// Delivery news for packets sent with [sendText].
  Stream<DeliveryUpdate> get deliveries => _deliveries.stream;

  /// Node news heard on the mesh.
  Stream<NodeUpdate> get nodes => _nodes.stream;

  /// This node's number, once the handshake has run.
  int? get myNodeNum => _myNode;

  /// Recent debug console lines from a USB/TCP node, for the connection log.
  List<String> get consoleLines => _decoder?.consoleLines ?? const [];

  String get _source => 'Meshtastic ${link.label}';

  /// Starts listening to [link]. The link must be open.
  void attach() {
    if (_attached) return;
    _attached = true;
    final Stream<Uint8List> frames;
    if (link.deliversFrames) {
      frames = link.incoming;
    } else {
      final decoder = _decoder = MeshtasticFrameDecoder();
      frames = link.incoming.expand(decoder.add);
    }
    _subs.add(frames.listen(_onFrame));
    _subs.add(
      link.states.listen((s) {
        if (s == LinkState.disconnected) _stopHeartbeat();
      }),
    );
  }

  /// Stops listening; doesn't close [link].
  Future<void> detach() async {
    _stopHeartbeat();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _attached = false;
  }

  /// Downloads the node's config (`want_config_id`) and checks its firmware.
  Future<MeshtasticConfig> handshake() async {
    attach();
    final nonce = _nonZeroId();
    MyNodeInfo? myInfo;
    DeviceMetadata? metadata;
    final nodes = <int, MeshNodeInfo>{};
    final channels = <MeshChannel>[];
    var configs = 0, modules = 0;
    final config = <int, Uint8List>{};
    final done = Completer<void>();

    final sub = events.listen((e) {
      switch (e) {
        case MyInfoFromRadio(:final info):
          myInfo = info;
        case MetadataFromRadio(metadata: final m):
          metadata = m;
        case NodeInfoFromRadio(:final node):
          nodes[node.num] = node;
        case ChannelFromRadio(:final channel):
          channels.add(channel);
        case ConfigFromRadio(:final module, :final raw):
          module ? modules++ : configs++;
          if (!module) {
            try {
              for (final f in readFields(raw)) {
                if (f.wireType == WireType.lengthDelimited) {
                  config[f.number] = f.asBytes;
                }
              }
            } on ProtobufException {
              // Keep going; settings are read again for the admin screen.
            }
          }
        case ConfigCompleteFromRadio(nonce: final n) when n == nonce:
          if (!done.isCompleted) done.complete();
        default:
          break;
      }
    });

    try {
      if (!link.deliversFrames && !_woken) {
        _woken = true;
        await link.send(meshtasticSerialWake());
      }
      await _write(ToRadio.wantConfig(nonce));
      await done.future.timeout(
        configTimeout,
        onTimeout: () => throw const MeshtasticTimeout('config download'),
      );
    } finally {
      await sub.cancel();
    }

    final info = myInfo;
    if (info == null) {
      throw const MeshtasticTimeout('node did not say which node it is');
    }
    final version = metadata?.firmwareVersion ?? '';
    if (!MeshtasticFirmware.isSupported(version)) {
      _log?.add(_source, 'firmware not supported: "$version"');
      throw UnsupportedMeshtasticFirmware(version);
    }
    _myNode = info.nodeNum;
    channels.sort((a, b) => a.index.compareTo(b.index));
    _log?.add(
      _source,
      'ready: firmware $version, ${nodes.length} nodes, '
      '${channels.where((c) => c.isEnabled).length} channels',
    );
    _startHeartbeat();
    return MeshtasticConfig(
      myInfo: info,
      metadata: metadata,
      nodes: nodes,
      channels: channels,
      configSections: configs,
      moduleSections: modules,
      config: config,
    );
  }

  /// Sends a text message and returns its packet ID, which later
  /// [DeliveryUpdate]s refer to.
  ///
  /// [to] is a node number for a direct message, or [broadcastNode] for the
  /// channel at [channel].
  Future<int> sendText(
    String text, {
    int to = broadcastNode,
    int channel = 0,
    bool wantAck = true,
    int replyId = 0,
    bool reaction = false,
  }) async {
    final id = _nonZeroId();
    final packet = MeshPacket(
      from: 0,
      to: to,
      id: id,
      channel: channel,
      wantAck: wantAck,
      decoded: DataPayload(
        portnum: PortNum.textMessage,
        payload: textPayload(text),
        replyId: replyId,
        emoji: reaction ? 1 : 0,
      ),
    );
    _sent[id] = to;
    if (_sent.length > 500) _sent.remove(_sent.keys.first);
    await _write(ToRadio.packet(packet));
    return id;
  }

  /// Asks [to] for the route between us (the firmware's traceroute).
  ///
  /// Throws [MeshtasticTimeout] if no answer comes within [timeout].
  Future<RouteDiscovery> traceroute(
    int to, {
    int channel = 0,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final id = _nonZeroId();
    final answer = events
        .where(
          (e) =>
              e is PacketFromRadio &&
              e.packet.decoded?.portnum == PortNum.traceroute &&
              e.packet.decoded?.requestId == id,
        )
        .cast<PacketFromRadio>()
        .first;
    await _write(
      ToRadio.packet(
        MeshPacket(
          from: 0,
          to: to,
          id: id,
          channel: channel,
          decoded: DataPayload(
            portnum: PortNum.traceroute,
            payload: Uint8List(0),
            wantResponse: true,
          ),
        ),
      ),
    );
    final reply = await answer.timeout(
      timeout,
      onTimeout: () => throw const MeshtasticTimeout('traceroute'),
    );
    return RouteDiscovery.decode(reply.packet.decoded!.payload);
  }

  /// Session passkeys per node, with when they arrived. Nodes accept
  /// changes only with a recent one (firmware keeps them about 5 minutes).
  final Map<int, (Uint8List, DateTime)> _passkeys = {};

  /// How long a passkey is trusted before asking for a fresh one.
  static const passkeyLifetime = Duration(minutes: 4);

  /// Sends an admin request to node [to] (this node's own number for the
  /// connected radio) and returns its answer.
  ///
  /// Other nodes are reached with a public-key encrypted packet; they only
  /// answer if this radio's key is in their admin keys. Throws
  /// [MeshtasticTimeout] if no answer arrives in [timeout].
  Future<AdminReply> adminRequest(
    int to,
    Uint8List admin, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = _nonZeroId();
    final answer = events
        .where(
          (e) =>
              e is PacketFromRadio &&
              e.packet.decoded?.portnum == PortNum.admin &&
              e.packet.decoded?.requestId == id,
        )
        .cast<PacketFromRadio>()
        .first;
    await _sendAdmin(to, admin, id: id, wantResponse: true);
    final packet = await answer.timeout(
      timeout,
      onTimeout: () => throw const MeshtasticTimeout('admin answer'),
    );
    final reply = AdminReply.decode(packet.packet.decoded!.payload);
    if (reply.passkey.isNotEmpty) {
      _passkeys[to] = (reply.passkey, DateTime.now());
    }
    return reply;
  }

  /// Reads one settings section (or the owner) from node [to].
  Future<SettingsSection> readSection(
    int to,
    SectionKind kind, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final reply = await adminRequest(
      to,
      AdminMessages.get(kind),
      timeout: timeout,
    );
    final section = reply.section(kind);
    if (section == null) {
      throw MeshtasticTimeout('answer for ${kind.name} settings');
    }
    return section;
  }

  /// Saves the changed [sections] on node [to] as one batch. The node
  /// restarts afterwards if a change needs it.
  Future<void> writeSections(
    int to,
    Iterable<SettingsSection> sections, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final changed = [
      for (final s in sections)
        if (s.changed) s,
    ];
    if (changed.isEmpty) return;
    final key = await _passkeyFor(to, timeout);
    await _sendAdmin(to, AdminMessages.beginEdit(key));
    for (final s in changed) {
      await _sendAdmin(to, AdminMessages.set(s, key));
    }
    await _sendAdmin(to, AdminMessages.commitEdit(key));
    _log?.add(
      _source,
      'saved ${changed.map((s) => s.kind.name).join(', ')} settings on '
      '${nodeIdOf(to)}',
    );
  }

  /// Restarts node [to].
  Future<void> rebootNode(
    int to, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final key = await _passkeyFor(to, timeout);
    await _sendAdmin(to, AdminMessages.reboot(key));
    _log?.add(_source, 'asked ${nodeIdOf(to)} to restart');
  }

  Future<Uint8List> _passkeyFor(int to, Duration timeout) async {
    final known = _passkeys[to];
    if (known != null &&
        DateTime.now().difference(known.$2) < passkeyLifetime) {
      return known.$1;
    }
    final reply = await adminRequest(
      to,
      AdminMessages.getMetadata(),
      timeout: timeout,
    );
    return reply.passkey;
  }

  Future<void> _sendAdmin(
    int to,
    Uint8List admin, {
    int? id,
    bool wantResponse = false,
  }) {
    final remote = to != _myNode;
    return _write(
      ToRadio.packet(
        MeshPacket(
          from: 0,
          to: to,
          id: id ?? _nonZeroId(),
          wantAck: remote && !wantResponse,
          pkiEncrypted: remote,
          decoded: DataPayload(
            portnum: PortNum.admin,
            payload: admin,
            wantResponse: wantResponse,
          ),
        ),
      ),
    );
  }

  /// Tells a USB/TCP node the app is leaving, then stops the heartbeat.
  Future<void> sayGoodbye() async {
    _stopHeartbeat();
    if (link.deliversFrames || link.state != LinkState.connected) return;
    try {
      await _write(ToRadio.disconnect());
    } on Object catch (_) {
      // Leaving anyway.
    }
  }

  Future<void> _write(Uint8List toRadio) {
    final bytes = link.deliversFrames ? toRadio : wrapMeshtasticFrame(toRadio);
    return link.send(bytes);
  }

  int _nonZeroId() {
    final hi = _random.nextInt(1 << 16);
    final lo = _random.nextInt(1 << 16);
    final id = (hi << 16) | lo;
    return id == 0 ? 1 : id;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (link.state != LinkState.connected) return;
      _write(ToRadio.heartbeat(_random.nextInt(1 << 16))).catchError((
        Object e,
      ) {
        _log?.add(_source, 'heartbeat failed: $e');
      });
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _onFrame(Uint8List data) {
    final FromRadio event;
    try {
      event = FromRadio.decode(data);
    } on ProtobufException catch (e) {
      _log?.add(_source, 'bad frame: ${e.message}');
      return;
    }
    if (!_events.isClosed) _events.add(event);
    switch (event) {
      case PacketFromRadio(:final packet):
        _onPacket(packet);
      case QueueStatusFromRadio(:final packetId, :final result)
          when _sent.containsKey(packetId):
        _deliver(
          DeliveryUpdate(
            packetId,
            result == 0 ? DeliveryStatus.queued : DeliveryStatus.failed,
            error: result == 0 ? null : RoutingError.unknown,
          ),
        );
      case RebootedFromRadio():
        _log?.add(_source, 'node rebooted; config must be read again');
      case NotificationFromRadio(:final message):
        _log?.add(_source, 'node says: $message');
      default:
        break;
    }
  }

  void _onPacket(MeshPacket p) {
    final data = p.decoded;
    if (data == null) return; // Not decryptable by this node.
    switch (data.portnum) {
      case PortNum.routing:
        _onRouting(p, data);
      case PortNum.textMessage:
        if (p.from == _myNode) return;
        if (!_texts.isClosed) {
          _texts.add(
            MeshtasticText(
              packet: p,
              text: decodeUtf8(data.payload),
              isDirect: !p.isBroadcast && p.to == _myNode,
            ),
          );
        }
      case PortNum.nodeInfo:
        _node(p, user: _tryDecode(data.payload, MeshUser.decode));
      case PortNum.position:
        _node(p, position: _tryDecode(data.payload, MeshPosition.decode));
    }
  }

  void _onRouting(MeshPacket p, DataPayload data) {
    final to = _sent[data.requestId];
    if (to == null) return;
    var code = 0;
    try {
      for (final f in readFields(data.payload)) {
        if (f.number == 3) code = f.asInt;
      }
    } on ProtobufException {
      return;
    }
    final error = RoutingError.of(code);
    if (error != RoutingError.none) {
      _deliver(
        DeliveryUpdate(
          data.requestId,
          DeliveryStatus.failed,
          error: error,
          from: p.from,
        ),
      );
      return;
    }
    // An ack from our own node only means it heard the packet repeated.
    final fromRecipient = to != broadcastNode && p.from == to;
    _deliver(
      DeliveryUpdate(
        data.requestId,
        fromRecipient ? DeliveryStatus.delivered : DeliveryStatus.relayed,
        from: p.from,
      ),
    );
  }

  void _deliver(DeliveryUpdate u) {
    if (!_deliveries.isClosed) _deliveries.add(u);
  }

  void _node(MeshPacket p, {MeshUser? user, MeshPosition? position}) {
    if (p.from == _myNode || (user == null && position == null)) return;
    if (_nodes.isClosed) return;
    _nodes.add(
      NodeUpdate(
        num: p.from,
        user: user,
        position: position,
        snr: p.rxSnr,
        hops: p.hopsTaken,
        viaMqtt: p.viaMqtt,
      ),
    );
  }

  static T? _tryDecode<T>(Uint8List data, T Function(Uint8List) decode) {
    try {
      return decode(data);
    } on ProtobufException {
      return null;
    }
  }

  /// Closes the streams; the session can't be used afterwards.
  Future<void> dispose() async {
    await detach();
    await _events.close();
    await _texts.close();
    await _deliveries.close();
    await _nodes.close();
  }
}

/// Lenient UTF-8 for message text.
String decodeUtf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
