import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mesh/mesh.dart';
import '../meshcore/meshcore.dart';
import '../meshcore/raw_packet.dart';
import '../meshtastic/meshtastic.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'meshcore_settings.dart';
import 'meshtastic_settings.dart';
import 'radio_target.dart';
import 'retry_policy.dart';

/// One connected radio: its link, protocol session and supervisor, with
/// everything it hears saved to the [MeshStore].
///
/// Screens listen to this for status and call [sendText]; the protocol
/// differences stay inside the two subclasses.
abstract class RadioConnection extends ChangeNotifier {
  RadioConnection({
    required this.target,
    required this.link,
    required this.store,
    required this.log,
    List<Duration>? retryDelays,
    this.retries = const RetryPolicy(),
  }) {
    supervisor = LinkSupervisor(
      link,
      delays:
          retryDelays ??
          const [
            Duration(seconds: 2),
            Duration(seconds: 5),
            Duration(seconds: 15),
            Duration(seconds: 30),
          ],
      onConnected: (_) => setUp(),
      isFatal: (e) =>
          e is UnsupportedFirmware || e is UnsupportedMeshtasticFirmware,
      log: log,
    );
    _statusSub = supervisor.statuses.listen((_) => notifyListeners());
  }

  /// Creates the right connection for [target]'s protocol.
  factory RadioConnection.forTarget(
    RadioTarget target, {
    required MeshStore store,
    required ConnectionLog log,
    LinkFactory links = const LinkFactory(),
    List<Duration>? retryDelays,
    RetryPolicy retries = const RetryPolicy(),
  }) {
    final link = links.create(target, log: log);
    return switch (target.protocol) {
      RadioProtocol.meshcore => MeshCoreConnection(
        target: target,
        link: link,
        store: store,
        log: log,
        retryDelays: retryDelays,
        retries: retries,
      ),
      RadioProtocol.meshtastic => MeshtasticConnection(
        target: target,
        link: link,
        store: store,
        log: log,
        retryDelays: retryDelays,
        retries: retries,
      ),
    };
  }

  final RadioTarget target;
  final RadioLink link;
  final MeshStore store;
  final ConnectionLog log;

  /// How hard to try delivering direct messages.
  final RetryPolicy retries;
  late final LinkSupervisor supervisor;
  late final StreamSubscription<SupervisorStatus> _statusSub;
  Radio? _radio;

  /// Packets heard, for the diagnostics screen.
  final PacketLog packetLog = PacketLog();

  /// Noise and channel-activity readings over time.
  final RadioSamples samples = RadioSamples();

  /// The radio's frequency, when known (MeshCore reports it).
  double? frequencyMHz;

  /// This radio's own contact card, for "show my code"; set on connect.
  ContactCard? ownCard;

  /// The channels on the radio, with their keys (for sharing).
  Future<List<ChannelSlot>> channelSlots();

  /// Joins [invite]'s channel in the first free slot and returns the slot;
  /// a channel already on the radio returns its slot. Throws
  /// [ChannelsFull] when no slot is free.
  Future<int> addChannel(ChannelInvite invite);

  /// Leaves the channel in slot [index].
  Future<void> removeChannel(int index);

  /// Takes one reading of the radio's noise and activity, if the protocol
  /// can be asked; null otherwise.
  Future<RadioSample?> sampleRadio();

  /// Whether [trace] can reach [node] (it must be on this radio, and for
  /// MeshCore have a known route through repeaters).
  bool canTrace(Node node);

  /// Traces the route to [node] and reports each hop's signal.
  Future<TraceResult> trace(Node node);

  /// Runs [trace] and saves a successful result. A failed save still
  /// returns the result, as the trace itself worked.
  Future<TraceResult> traceAndSave(Node node) async {
    final r = await trace(node);
    try {
      await store.addTrace(node.radioId, node.displayName, r);
    } on Object catch (e) {
      debugPrint('Could not save the trace: $e');
    }
    return r;
  }

  /// Display names for this radio's nodes, for labelling hops.
  Future<Map<NodeKey, Node>> knownNodes() async {
    final r = _radio;
    if (r == null) return const {};
    return {for (final n in await store.nodes(r.id)) n.key: n};
  }

  RadioProtocol get protocol => target.protocol;

  /// The radio, once its first handshake finished.
  Radio? get radio => _radio;

  SupervisorStatus get status => supervisor.status;

  /// Largest message text in UTF-8 bytes.
  int get maxTextBytes;

  /// Connects and keeps the radio connected.
  Future<void> start() => supervisor.start();

  /// Tries to reconnect now.
  Future<void> tryNow() => supervisor.tryNow();

  /// Disconnects for good.
  Future<void> stop() => supervisor.stop();

  /// Runs after every (re)connection: handshake and sync into the store.
  @protected
  Future<void> setUp();

  @protected
  Future<void> setRadio(Radio radio) async {
    _radio = radio;
    await store.upsertRadio(radio, connectedAt: DateTime.now());
    notifyListeners();
  }

  /// Saves an outgoing message, sends it and tracks its delivery.
  /// Returns the stored message ID.
  Future<int> sendText(Conversation conversation, String text) async {
    final radio = _radio;
    if (radio == null || conversation.radioId != radio.id) {
      throw StateError('Not connected to ${conversation.radioId}');
    }
    final now = DateTime.now();
    final id = (await store.addMessage(
      Message(
        conversation: conversation,
        text: text,
        outgoing: true,
        sentAt: now,
        receivedAt: now,
        delivery: const Pending(),
        from: radio.self,
      ),
    ))!;
    await _transmitSafely(id, conversation, text, now);
    return id;
  }

  /// Sends a failed message again, keeping its place in the conversation.
  Future<void> resend(int id) async {
    final stored = await store.message(id);
    final radio = _radio;
    if (stored == null || !stored.message.outgoing || radio == null) return;
    final m = stored.message;
    if (m.radioId != radio.id || m.delivery is! Failed) return;
    await store.setDelivery(id, const Pending());
    await _transmitSafely(id, m.conversation, m.text, m.sentAt);
  }

  Future<void> _transmitSafely(
    int id,
    Conversation conversation,
    String text,
    DateTime sentAt,
  ) async {
    try {
      await transmit(id, conversation, text, sentAt);
    } on Object catch (e) {
      await store.setDelivery(id, Failed(describeError(e)));
    }
  }

  /// Protocol-specific sending: records the native ID and first state,
  /// then keeps retrying in the background as [retries] says.
  @protected
  Future<void> transmit(
    int id,
    Conversation conversation,
    String text,
    DateTime sentAt,
  );

  /// Text for an error, for a failed message.
  static String describeError(Object e) => switch (e) {
    MeshCoreException(:final code) => code.message,
    MeshCoreTimeout() => 'The radio did not answer',
    MeshtasticTimeout() => 'The radio did not answer',
    LinkException(:final message) => message,
    _ => 'Could not send',
  };

  /// Set once [close] starts; late events are ignored after that.
  @protected
  bool closed = false;

  @mustCallSuper
  Future<void> close() async {
    closed = true;
    await supervisor.dispose();
    await _statusSub.cancel();
  }
}

/// A MeshCore companion radio.
class MeshCoreConnection extends RadioConnection {
  MeshCoreConnection({
    required super.target,
    required super.link,
    required super.store,
    required super.log,
    super.retryDelays,
    super.retries,
  }) : session = MeshCoreSession(link, log: log) {
    _subs
      ..add(session.messages.listen((f) => unawaited(_onMessage(f))))
      ..add(session.pushes.listen((f) => unawaited(_onPush(f))));
  }

  final MeshCoreSession session;
  final List<StreamSubscription<Object?>> _subs = [];
  MeshCoreMapper? _mapper;

  @override
  int get maxTextBytes => MeshCoreLimits.maxTextBytes;

  @override
  Future<void> setUp() async {
    final h = await session.handshake();
    _notePathHash(h.device);
    selfInfo = h.self;
    frequencyMHz = h.self.frequencyMHz;
    ownCard = ContactCard(
      protocol: RadioProtocol.meshcore,
      name: h.self.name,
      publicKey: h.self.publicKey,
    );
    final radio = MeshCoreMapper.radio(h);
    final mapper = _mapper = MeshCoreMapper(radio.id);
    await setRadio(radio);
    maxContacts = h.device.maxContacts;
    final contacts = await session.getContacts();
    await store.upsertNodes(contacts.contacts.map(mapper.node));
    await store.replaceRadioContacts(
      radio.id,
      contacts.contacts.map((c) => NodeKey.meshcore(c.keyHex)),
    );
    final slots = channelSlotCount = h.device.maxChannels ?? 8;
    final channels = await session.getChannels(slots);
    await store.replaceChannels(
      radio.id,
      channels.map(mapper.channel).nonNulls,
    );
    await session.fetchMessages();
  }

  Future<void> _onMessage(MeshCoreFrame frame) async {
    final mapper = _mapper;
    final radio = this.radio;
    if (mapper == null || radio == null) return;
    NodeKey? sender;
    // Repeater command replies go to the console, not the inbox.
    if (frame is ContactMessageFrame && frame.textType == TextType.cliData) {
      return;
    }
    if (frame is ContactMessageFrame) {
      sender = await store.meshCoreNodeByPrefix(
        radio.id,
        toHex(frame.keyPrefix),
      );
    }
    final message = mapper.received(frame, findContact: (_) => sender);
    if (message != null) await store.addMessage(message);
  }

  Future<void> _onPush(MeshCoreFrame frame) async {
    final radio = this.radio;
    final mapper = _mapper;
    if (radio == null || mapper == null) return;
    switch (frame) {
      case SendConfirmedPush(:final ackCode):
        final waiter = _waiting[ackCode];
        if (waiter != null && !waiter.isCompleted) waiter.complete(frame);
        await store.setDeliveryByNativeId(
          radio.id,
          ackCode,
          MeshCoreMapper.confirmed(frame),
        );
      case ContactFrame(fromNewAdvert: true):
        await store.upsertNode(mapper.node(frame));
      case RxLogPush(:final snr, :final rssi, :final raw):
        final stranger = meshtasticBroadcastSender(raw);
        if (stranger != null) {
          packetLog.add(
            PacketLogEntry(
              time: DateTime.now(),
              protocol: RadioProtocol.meshtastic,
              kind: 'Meshtastic broadcast',
              from: meshtasticNodeId(stranger),
              path: PathFacts(snr: snr, rssi: rssi),
              bytes: raw.length,
              encrypted: true,
              otherMesh: true,
            ),
          );
          return;
        }
        final info = MeshCorePacketInfo.parse(raw);
        packetLog.add(
          PacketLogEntry(
            time: DateTime.now(),
            protocol: RadioProtocol.meshcore,
            kind: info?.payload.label ?? 'Unreadable packet',
            path: PathFacts(
              hops: info?.hops,
              snr: snr,
              rssi: rssi,
              route: info == null
                  ? RouteKind.unknown
                  : info.isFlood
                  ? RouteKind.flood
                  : RouteKind.direct,
            ),
            bytes: raw.length,
            detail: info == null || info.path.isEmpty ? null : info.pathText,
            encrypted: true,
          ),
        );
      case ContactsFullPush():
        log.add('MeshCore ${link.label}', "radio's contact list is full");
      case ContactDeletedPush(:final publicKey):
        await store.setOnRadio(
          radio.id,
          NodeKey.meshcore(toHex(publicKey)),
          false,
        );
      default:
        break;
    }
  }

  @override
  Future<void> transmit(
    int id,
    Conversation conversation,
    String text,
    DateTime sentAt,
  ) async {
    switch (conversation) {
      case DirectConversation(:final node):
        final key = fromHex(node.native);
        // The radio can only message nodes in its own contact list.
        if (await store.node(conversation.radioId, node) case final n?) {
          await ensureOnRadio(n);
        }
        // First attempt now (errors reach the caller); the rest run on.
        final first = await _attempt(id, key, text, sentAt, 0);
        unawaited(
          _keepTrying(id, key, text, sentAt, first).catchError((Object e) {
            return store.setDelivery(
              id,
              Failed(RadioConnection.describeError(e)),
            );
          }),
        );
      case ChannelConversation(:final index):
        await session.sendChannelText(channel: index, text: text, at: sentAt);
        await store.setAttempts(id, 1);
        await store.setDelivery(id, const Sent());
    }
  }

  @override
  Future<RadioSample?> sampleRadio() async {
    try {
      final s = await session.radioStats();
      final sample = RadioSample(
        time: DateTime.now(),
        noiseFloor: s.noiseFloor,
        lastSnr: s.lastSnr,
        lastRssi: s.lastRssi,
      );
      samples.add(sample);
      return sample;
    } on UnsupportedFirmware {
      return null;
    }
  }

  @override
  bool canTrace(Node node) =>
      node.radioId == radio?.id && node.route.isNotEmpty;

  /// Out along the route and back to us: hops h0…hk-1 then hk-2…h0.
  static List<int> tracePath(Node node) {
    final size = node.routeHashSize;
    final hops = [
      for (var i = 0; i + size <= node.route.length; i += size)
        node.route.sublist(i, i + size),
    ];
    return [
      for (final h in hops) ...h,
      for (final h in hops.reversed.skip(1)) ...h,
    ];
  }

  @override
  Future<TraceResult> trace(Node node) async {
    final size = node.routeHashSize;
    final hopCount = node.route.length ~/ size;
    final clock = Stopwatch()..start();
    final push = await session.trace(tracePath(node), hashSize: size);
    clock.stop();
    final known = (await knownNodes()).values.toList();
    TraceHop hop(int i, double snr) {
      final prefix = toHex(push.hashes.sublist(i * size, (i + 1) * size));
      final matches = [
        for (final n in known)
          if (n.key.native.startsWith(prefix)) n,
      ];
      final n = matches.length == 1 ? matches.single : null;
      return TraceHop(n?.displayName ?? prefix, snr, node: n);
    }

    final all = [
      for (var i = 0; i < push.hopSnrs.length; i++) hop(i, push.hopSnrs[i]),
      TraceHop(radio?.name ?? 'Your radio', push.finalSnr),
    ];
    return TraceResult(
      target: node.key,
      towards: all.take(hopCount).toList(),
      back: all.skip(hopCount).toList(),
      time: DateTime.now(),
      roundTrip: clock.elapsed,
    );
  }

  /// The radio's own identity and settings, from the last handshake.
  SelfInfoFrame? selfInfo;

  /// The settings to edit, or null before the first handshake.
  MeshCoreSettings? get settings {
    final s = selfInfo;
    return s == null ? null : MeshCoreSettings.from(s);
  }

  /// Sends only what changed from the radio's current settings, then reads
  /// them back so the screen shows what the radio really accepted.
  /// The radio's hop ID size in bytes; null if its firmware can't set it.
  int? get pathHashBytes => _pathHashBytes;
  int? _pathHashBytes;

  void _notePathHash(DeviceInfoFrame device) {
    final mode = device.pathHashMode;
    _pathHashBytes =
        mode != null &&
            MeshCoreFirmware.supports(
              device.firmwareCode,
              MeshCoreFeature.pathHashMode,
            )
        ? mode + 1
        : null;
  }

  Future<MeshCoreSettings> applySettings(
    MeshCoreSettings wanted, {
    int? pathHashBytes,
  }) async {
    final now = settings;
    if (now == null) throw StateError('Not connected');
    if (wanted.name.trim() != now.name) {
      await session.setName(wanted.name.trim());
    }
    if (wanted.txPower != now.txPower) {
      await session.setTxPower(wanted.txPower);
    }
    if (wanted.radioDiffers(now)) {
      await session.setRadioParams(
        frequencyMHz: wanted.frequencyMHz,
        bandwidthKHz: wanted.bandwidthKHz,
        spreadingFactor: wanted.spreadingFactor,
        codingRate: wanted.codingRate,
      );
    }
    if (wanted.latitude != now.latitude || wanted.longitude != now.longitude) {
      await session.setPosition(wanted.latitude, wanted.longitude);
    }
    if (wanted.otherDiffers(now)) {
      await session.setOtherParams(
        manualAddContacts: wanted.manualAddContacts,
        telemetryMode: wanted.telemetryMode,
        advertLocationPolicy: wanted.shareLocationInAdverts ? 1 : 0,
        multiAcks: wanted.multiAcks,
      );
    }
    if (pathHashBytes != null && pathHashBytes != _pathHashBytes) {
      await session.setPathHashMode(pathHashBytes - 1);
      _notePathHash(await session.deviceQuery());
    }
    final fresh = selfInfo = await session.appStart();
    frequencyMHz = fresh.frequencyMHz;
    final radio = this.radio;
    if (radio != null) {
      await setRadio(
        Radio(
          id: radio.id,
          name: fresh.name,
          self: radio.self,
          firmware: radio.firmware,
          model: radio.model,
          maxChannels: radio.maxChannels,
          position: fresh.latitude == 0 && fresh.longitude == 0
              ? null
              : GeoPoint(fresh.latitude, fresh.longitude),
        ),
      );
    }
    return MeshCoreSettings.from(fresh);
  }

  /// How many contacts the radio can hold, from its device info.
  int? maxContacts;

  /// Channel slots the radio has.
  int channelSlotCount = 8;

  @override
  Future<List<ChannelSlot>> channelSlots() async => [
    for (final f in await session.getChannels(channelSlotCount))
      if (!f.isEmpty)
        ChannelSlot(
          index: f.index,
          invite: ChannelInvite(
            protocol: RadioProtocol.meshcore,
            name: f.name,
            secret: f.secret,
          ),
        ),
  ];

  @override
  Future<int> addChannel(ChannelInvite invite) async {
    final all = await session.getChannels(channelSlotCount);
    for (final f in all) {
      if (!f.isEmpty && toHex(f.secret) == hexOf(invite.secret)) return f.index;
    }
    var free = -1;
    for (var i = 0; i < channelSlotCount; i++) {
      final used = i < all.length && !all[i].isEmpty;
      if (!used) {
        free = i;
        break;
      }
    }
    if (free < 0) throw const ChannelsFull();
    await session.setChannel(free, invite.name, invite.secret);
    await _refreshChannels();
    return free;
  }

  @override
  Future<void> removeChannel(int index) async {
    await session.setChannel(index, '', Uint8List(16));
    await _refreshChannels();
  }

  Future<void> _refreshChannels() async {
    final radio = this.radio;
    final mapper = _mapper;
    if (radio == null || mapper == null) return;
    final channels = await session.getChannels(channelSlotCount);
    await store.replaceChannels(
      radio.id,
      channels.map(mapper.channel).nonNulls,
    );
  }

  /// Puts [node] in the radio's contact list if it isn't there, so the
  /// radio can message it. When the list is full, the least recently heard
  /// contact that isn't a favourite (people before repeaters and rooms)
  /// makes room; the app still keeps it.
  Future<void> ensureOnRadio(Node node) async {
    final radio = this.radio;
    if (radio == null || node.radioId != radio.id) return;
    final on = await store.radioContacts(radio.id);
    if (on.contains(node.key)) return;
    if (node.publicKey.length != 32) return;
    final max = maxContacts;
    if (max != null && max > 0 && on.length >= max) {
      final victim = await _leastNeeded(radio.id, on, except: node.key);
      if (victim != null) {
        await session.removeContact(victim.publicKey);
        await store.setOnRadio(radio.id, victim.key, false);
        log.add(
          'MeshCore ${link.label}',
          'made room on the radio: removed ${victim.displayName}',
        );
      }
    }
    await session.addContact(
      publicKey: node.publicKey,
      type: switch (node.kind) {
        NodeKind.person => NodeType.chat.code,
        NodeKind.relay => NodeType.repeater.code,
        NodeKind.room => NodeType.room.code,
        NodeKind.sensor => NodeType.sensor.code,
        _ => NodeType.unknown.code,
      },
      name: node.name,
      flags: node.isFavorite ? 1 : 0,
      lastAdvert: (node.lastHeard?.millisecondsSinceEpoch ?? 0) ~/ 1000,
      latitude: node.position?.latitude,
      longitude: node.position?.longitude,
    );
    await store.setOnRadio(radio.id, node.key, true);
    log.add('MeshCore ${link.label}', 'added ${node.displayName} to the radio');
  }

  Future<Node?> _leastNeeded(
    RadioId radio,
    Set<NodeKey> on, {
    required NodeKey except,
  }) async {
    int rank(Node n) => switch (n.kind) {
      NodeKind.relay || NodeKind.room => 1,
      _ => 0,
    };
    final candidates =
        [
          for (final n in await store.nodes(radio))
            if (on.contains(n.key) &&
                n.key != except &&
                !n.isFavorite &&
                n.publicKey.length == 32)
              n,
        ]..sort((a, b) {
          final r = rank(a).compareTo(rank(b));
          if (r != 0) return r;
          final ta = a.lastHeard?.millisecondsSinceEpoch ?? 0;
          final tb = b.lastHeard?.millisecondsSinceEpoch ?? 0;
          return ta.compareTo(tb);
        });
    return candidates.firstOrNull;
  }

  /// Sends this radio's advert: to neighbours, or flooded mesh-wide.
  Future<void> sendAdvert({bool flood = false}) =>
      session.sendAdvert(flood: flood);

  /// Restarts the radio; the app reconnects by itself.
  Future<void> reboot() => session.reboot();

  /// Whether the companion can run commands itself (protocol 14+).
  bool get hasCompanionCli => MeshCoreFirmware.supports(
    session.firmwareCode ?? 0,
    MeshCoreFeature.companionCli,
  );

  /// Runs a command on this radio.
  Future<String> runCli(String command) => session.runCli(command);

  /// Logs in to a repeater or room server.
  Future<LoginResultPush> login(Node server, String password) async {
    await ensureOnRadio(server);
    return session.login(fromHex(server.key.native), password);
  }

  /// A repeater or room server's status.
  Future<RepeaterStatusPush> serverStatus(Node server) async {
    await ensureOnRadio(server);
    return session.serverStatus(fromHex(server.key.native));
  }

  /// Runs a command on a repeater or room server you're logged in to.
  Future<String> serverCommand(Node server, String command) =>
      session.serverCommand(fromHex(server.key.native), command);

  final Map<int, Completer<SendConfirmedPush>> _waiting = {};

  Future<SentFrame> _attempt(
    int id,
    List<int> key,
    String text,
    DateTime sentAt,
    int attempt,
  ) async {
    final sent = await session.sendText(
      publicKey: key,
      text: text,
      at: sentAt,
      attempt: attempt.clamp(0, 3),
    );
    _waiting[sent.ackCode] = Completer<SendConfirmedPush>();
    await store.setNativeId(id, sent.ackCode);
    await store.setAttempts(id, attempt + 1);
    await store.setDelivery(id, MeshCoreMapper.sent(sent));
    return sent;
  }

  /// Waits for any attempt's acknowledgement; after the direct attempts,
  /// resets the route and floods, like the official MeshCore app.
  Future<void> _keepTrying(
    int id,
    List<int> key,
    String text,
    DateTime sentAt,
    SentFrame first,
  ) async {
    final acks = <int>{first.ackCode};
    var sent = first;
    var attempt = 0;
    var flooding = first.flood;
    var floodsLeft = retries.floodAttempts;
    var directLeft = flooding ? 0 : retries.directAttempts - 1;
    if (flooding) floodsLeft--;
    while (true) {
      if (await _confirmed(id, acks, retries.waitFor(sent.timeoutMs))) return;
      if (!flooding && directLeft == 0) {
        log.add('MeshCore ${link.label}', 'no ack on direct path; flooding');
        await session.resetPath(key);
        flooding = true;
      }
      if (flooding && floodsLeft <= 0) break;
      attempt++;
      sent = await _attempt(id, key, text, sentAt, attempt);
      acks.add(sent.ackCode);
      if (flooding || sent.flood) {
        flooding = true;
        floodsLeft--;
      } else {
        directLeft--;
      }
    }
    if (await _confirmed(id, acks, Duration.zero)) return;
    await store.setDelivery(
      id,
      Failed('No acknowledgement after ${attempt + 1} tries'),
    );
  }

  /// Whether any attempt in [acks] is confirmed within [wait]; if so the
  /// message is marked delivered (an early attempt's ack counts too).
  Future<bool> _confirmed(int id, Set<int> acks, Duration wait) async {
    final waits = [
      for (final a in acks)
        if (_waiting[a] case final c?) c.future,
    ];
    if (waits.isEmpty) return false;
    try {
      final push = await Future.any(waits).timeout(wait);
      for (final a in acks) {
        _waiting.remove(a);
      }
      await store.setDelivery(id, MeshCoreMapper.confirmed(push));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await session.dispose();
    await super.close();
  }
}

/// A Meshtastic node.
class MeshtasticConnection extends RadioConnection {
  MeshtasticConnection({
    required super.target,
    required super.link,
    required super.store,
    required super.log,
    super.retryDelays,
    super.retries,
  }) : session = MeshtasticSession(link, log: log) {
    _subs
      ..add(session.texts.listen((t) => unawaited(_onText(t))))
      ..add(session.deliveries.listen((d) => unawaited(_onDelivery(d))))
      ..add(session.nodes.listen((n) => unawaited(_onNode(n))))
      ..add(session.events.listen(_onEvent));
  }

  final MeshtasticSession session;
  final List<StreamSubscription<Object?>> _subs = [];
  MeshtasticMapper? _mapper;

  @override
  int get maxTextBytes => meshtasticMaxPayload;

  /// The radio has no LoRa region set, so it won't transmit.
  bool regionUnset = false;

  /// Channel slots as the radio last reported them, by index.
  final Map<int, MeshChannel> _channels = {};

  /// Meshtastic radios have eight channel slots; slot 0 is the primary.
  static const channelSlotCount = 8;

  @override
  Future<List<ChannelSlot>> channelSlots() async => [
    for (final c
        in _channels.values.toList()
          ..sort((a, b) => a.index.compareTo(b.index)))
      if (c.isEnabled)
        ChannelSlot(
          index: c.index,
          isPrimary: c.role == ChannelRole.primary,
          invite: ChannelInvite(
            protocol: RadioProtocol.meshtastic,
            name: c.name,
            secret: c.psk ?? Uint8List(0),
          ),
        ),
  ];

  @override
  Future<int> addChannel(ChannelInvite invite) async {
    for (final c in _channels.values) {
      if (c.isEnabled &&
          c.name == invite.name &&
          hexOf(c.psk ?? const []) == hexOf(invite.secret)) {
        return c.index;
      }
    }
    var free = -1;
    for (var i = 1; i < channelSlotCount; i++) {
      if (!(_channels[i]?.isEnabled ?? false)) {
        free = i;
        break;
      }
    }
    if (free < 0) throw const ChannelsFull();
    await _writeChannel(
      MeshChannel(
        index: free,
        role: ChannelRole.secondary,
        name: invite.name,
        psk: invite.secret,
      ),
    );
    return free;
  }

  @override
  Future<void> removeChannel(int index) async {
    if (index == 0) throw ArgumentError('The primary channel stays');
    await _writeChannel(MeshChannel(index: index, role: ChannelRole.disabled));
  }

  Future<void> _writeChannel(MeshChannel c) async {
    await session.writeChannel(_me, c);
    _channels[c.index] = c;
    final radio = this.radio;
    final mapper = _mapper;
    if (radio == null || mapper == null) return;
    await store.replaceChannels(
      radio.id,
      [for (final ch in _channels.values) ?mapper.channel(ch)]
        ..sort((a, b) => a.index.compareTo(b.index)),
    );
  }

  @override
  Future<void> setUp() async {
    final config = await session.handshake();
    regionUnset =
        config.lora?.number(LoraField.region) == MeshtasticRegion.unset;
    final me = config.self?.user;
    ownCard = ContactCard(
      protocol: RadioProtocol.meshtastic,
      name: me?.longName ?? '',
      shortName: me?.shortName ?? '',
      publicKey: me?.publicKey ?? Uint8List(0),
      nodeNum: config.myInfo.nodeNum,
    );
    final radio = MeshtasticMapper.radio(config);
    final mapper = _mapper = MeshtasticMapper(radio.id);
    await setRadio(radio);
    await store.upsertNodes(
      config.nodes.values
          .where((n) => n.num != config.myInfo.nodeNum)
          .map(mapper.node),
    );
    _channels
      ..clear()
      ..addAll({for (final c in config.channels) c.index: c});
    await store.replaceChannels(
      radio.id,
      config.channels.map(mapper.channel).nonNulls,
    );
  }

  Future<void> _onText(MeshtasticText t) async {
    final mapper = _mapper;
    if (mapper == null) return;
    await store.addMessage(mapper.received(t));
  }

  Future<void> _onDelivery(DeliveryUpdate d) async {
    final radio = this.radio;
    if (radio == null) return;
    if (await _maybeResend(d)) return;
    final state = MeshtasticMapper.delivery(d);
    // The node can answer before the packet ID is saved; try once more.
    if (closed) return;
    if (!await store.setDeliveryByNativeId(radio.id, d.packetId, state)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (closed) return;
      await store.setDeliveryByNativeId(radio.id, d.packetId, state);
    }
  }

  Future<void> _onNode(NodeUpdate u) async {
    final radio = this.radio;
    final mapper = _mapper;
    if (radio == null || mapper == null) return;
    final existing = await store.node(radio.id, NodeKey.meshtastic(u.num));
    await store.upsertNode(mapper.update(existing, u));
  }

  void _onEvent(FromRadio e) {
    if (e is! PacketFromRadio) return;
    final p = e.packet;
    final data = p.decoded;
    final me = session.myNodeNum;
    if (data != null && data.portnum == PortNum.telemetry) {
      try {
        final t = Telemetry.decode(data.payload);
        final local = t.local;
        if (local != null && p.from == me) {
          samples.add(
            RadioSample(
              time: DateTime.now(),
              noiseFloor: local.noiseFloor,
              channelUtilization: local.channelUtilization,
              airUtilTx: local.airUtilTx,
            ),
          );
        }
        unawaited(_saveTelemetry(p.from, t));
      } on ProtobufException {
        // Not ours to worry about; skip it.
      }
    }
    if (p.from == me) return;
    packetLog.add(
      PacketLogEntry(
        time: DateTime.now(),
        protocol: RadioProtocol.meshtastic,
        kind: data == null ? 'Encrypted' : portName(data.portnum),
        from: meshtasticNodeId(p.from),
        to: p.isBroadcast ? null : meshtasticNodeId(p.to),
        path: PathFacts(
          hops: p.hopsTaken,
          snr: p.rxSnr,
          rssi: p.rxRssi,
          viaMqtt: p.viaMqtt,
        ),
        bytes: data?.payload.length ?? p.encrypted?.length,
        encrypted: data == null,
      ),
    );
  }

  /// Keeps [t]'s battery, load and sensor readings in the history.
  Future<void> _saveTelemetry(int from, Telemetry t) async {
    final radio = this.radio;
    final device = t.device;
    final env = t.environment;
    if (radio == null || closed || (device == null && env == null)) return;
    final now = DateTime.now();
    // Use the node's own clock only when it looks right.
    var time = now;
    if (t.time case final secs?) {
      final told = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
      if (told.isBefore(now.add(const Duration(minutes: 5))) &&
          now.difference(told) < const Duration(hours: 6)) {
        time = told;
      }
    }
    await store.addTelemetry(
      TelemetryPoint(
        radioId: radio.id,
        node: NodeKey.meshtastic(from),
        time: time,
        batteryLevel: device?.batteryLevel,
        voltage: device?.voltage,
        channelUtilization: device?.channelUtilization,
        airUtilTx: device?.airUtilTx,
        uptimeSeconds: device?.uptimeSeconds,
        temperature: env?.temperature,
        relativeHumidity: env?.relativeHumidity,
        barometricPressure: env?.barometricPressure,
      ),
    );
  }

  /// This radio's node number, once connected.
  int? get myNodeNum => session.myNodeNum;

  /// Reads the settings of node [node] (this radio when null). Another
  /// node only answers if this radio's key is in its admin keys.
  Future<MeshtasticSettings> loadSettings({
    int? node,
    Duration timeout = const Duration(seconds: 30),
    List<SectionKind> kinds = MeshtasticSettings.kinds,
  }) async {
    final to = node ?? _me;
    final sections = <SectionKind, SettingsSection>{};
    for (final kind in kinds) {
      sections[kind] = await session.readSection(to, kind, timeout: timeout);
    }
    return MeshtasticSettings(sections);
  }

  /// Share of airtime this radio has reported using, at or above which a
  /// change over the mesh asks first. Well under the 10% many regions allow.
  static const busyAirUtilTx = 8.0;

  /// The airtime this radio last reported using, in percent.
  double? get recentAirUtilTx {
    for (final s in samples.samples.reversed) {
      if (s.airUtilTx != null) return s.airUtilTx;
    }
    return null;
  }

  /// Saves what changed in [settings] on [node] (this radio when null).
  /// The node restarts if a change needs it; this radio then reconnects by
  /// itself.
  Future<void> saveSettings(
    MeshtasticSettings settings, {
    int? node,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await session.writeSections(
      node ?? _me,
      settings.changed,
      timeout: timeout,
    );
    final newRegion = settings.sections[SectionKind.lora]?.number(
      LoraField.region,
    );
    if (node == null &&
        newRegion != null &&
        newRegion != MeshtasticRegion.unset) {
      regionUnset = false;
      notifyListeners();
    }
    final owner = settings.sections[SectionKind.owner];
    final radio = this.radio;
    if (node == null && radio != null && owner != null && owner.changed) {
      final name = owner.text(OwnerField.longName).trim();
      await setRadio(
        Radio(
          id: radio.id,
          name: name,
          self: radio.self,
          firmware: radio.firmware,
          model: radio.model,
          maxChannels: radio.maxChannels,
          position: radio.position,
        ),
      );
    }
  }

  /// Fixes [node] (this radio when null) at [position].
  Future<void> setFixedPosition(GeoPoint position, {int? node}) =>
      session.setFixedPosition(
        node ?? _me,
        position.latitude,
        position.longitude,
        position.altitude,
      );

  /// Clears the fixed position of [node] (this radio when null).
  Future<void> removeFixedPosition({int? node}) =>
      session.removeFixedPosition(node ?? _me);

  /// Restarts [node] (this radio when null).
  Future<void> rebootNode({int? node}) => session.rebootNode(node ?? _me);

  int get _me {
    final me = session.myNodeNum;
    if (me == null) throw StateError('Not connected');
    return me;
  }

  /// English names for common Meshtastic ports.
  static String portName(int port) => switch (port) {
    PortNum.textMessage => 'Text message',
    PortNum.position => 'Position',
    PortNum.nodeInfo => 'Node info',
    PortNum.routing => 'Routing',
    PortNum.admin => 'Admin',
    PortNum.telemetry => 'Telemetry',
    PortNum.traceroute => 'Traceroute',
    _ => 'Port $port',
  };

  @override
  Future<RadioSample?> sampleRadio() async => samples.latest;

  @override
  bool canTrace(Node node) => node.radioId == radio?.id;

  @override
  Future<TraceResult> trace(Node node) async {
    final clock = Stopwatch()..start();
    final r = await session.traceroute(node.key.meshtasticNum!);
    clock.stop();
    final known = await knownNodes();
    TraceHop hop(int num, double? snr) {
      final n = known[NodeKey.meshtastic(num)];
      return TraceHop(n?.displayName ?? meshtasticNodeId(num), snr, node: n);
    }

    double? at(List<double?> l, int i) => i < l.length ? l[i] : null;
    final towardsNums = [...r.route, node.key.meshtasticNum!];
    final backNums = [...r.routeBack, session.myNodeNum ?? 0];
    return TraceResult(
      target: node.key,
      towards: [
        for (var i = 0; i < towardsNums.length; i++)
          hop(towardsNums[i], at(r.snrTowards, i)),
      ],
      back: r.snrBack.isEmpty
          ? const []
          : [
              for (var i = 0; i < backNums.length; i++)
                hop(backNums[i], at(r.snrBack, i)),
            ],
      time: DateTime.now(),
      roundTrip: clock.elapsed,
    );
  }

  /// Direct messages awaiting news: packet ID -> what's needed to resend.
  final Map<int, _PendingDm> _dms = {};

  @override
  Future<void> transmit(
    int id,
    Conversation conversation,
    String text,
    DateTime sentAt,
  ) async {
    switch (conversation) {
      case DirectConversation(:final node):
        await _sendDm(id, node.meshtasticNum!, text, attempt: 1);
      case ChannelConversation(:final index):
        final packetId = await session.sendText(text, channel: index);
        await store.setNativeId(id, packetId);
        await store.setAttempts(id, 1);
    }
  }

  Future<void> _sendDm(
    int id,
    int to,
    String text, {
    required int attempt,
  }) async {
    final packetId = await session.sendText(text, to: to);
    final pending = _PendingDm(id, to, text, attempt);
    _dms[packetId] = pending;
    await store.setNativeId(id, packetId);
    await store.setAttempts(id, attempt);
    pending.timer = Timer(retries.meshtasticTimeout, () {
      if (_dms.remove(packetId) != null) {
        unawaited(store.setDelivery(id, const Failed('No acknowledgement')));
      }
    });
  }

  /// Retries a direct message the mesh couldn't deliver; true if resent.
  Future<bool> _maybeResend(DeliveryUpdate d) async {
    final dm = _dms[d.packetId];
    if (dm == null || d.status == DeliveryStatus.queued) return false;
    _dms.remove(d.packetId);
    dm.timer?.cancel();
    if (d.status != DeliveryStatus.failed) return false;
    const retryable = {
      RoutingError.maxRetransmit,
      RoutingError.timeout,
      RoutingError.noResponse,
    };
    if (!retryable.contains(d.error) ||
        dm.attempt > retries.meshtasticResends) {
      return false;
    }
    log.add('Meshtastic ${link.label}', 'no ack; sending again');
    await store.setDelivery(dm.id, const Pending());
    await _sendDm(dm.id, dm.to, dm.text, attempt: dm.attempt + 1);
    return true;
  }

  @override
  Future<void> close() async {
    for (final dm in _dms.values) {
      dm.timer?.cancel();
    }
    _dms.clear();
    await session.sayGoodbye();
    for (final s in _subs) {
      await s.cancel();
    }
    await session.dispose();
    await super.close();
  }
}

class _PendingDm {
  _PendingDm(this.id, this.to, this.text, this.attempt);

  final int id;
  final int to;
  final String text;
  final int attempt;
  Timer? timer;
}

/// A channel on a radio, with what's needed to share it.
class ChannelSlot {
  const ChannelSlot({
    required this.index,
    required this.invite,
    this.isPrimary = false,
  });

  final int index;
  final ChannelInvite invite;

  /// Meshtastic primary channel (can't be removed).
  final bool isPrimary;

  String get name => invite.name;
}

/// Every channel slot on the radio is in use.
class ChannelsFull implements Exception {
  const ChannelsFull();
  @override
  String toString() => 'ChannelsFull';
}
