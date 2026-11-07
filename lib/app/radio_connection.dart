import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mesh/mesh.dart';
import '../meshcore/meshcore.dart';
import '../meshtastic/meshtastic.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
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
    LinkException(:final message) => message,
    _ => 'Could not send',
  };

  @mustCallSuper
  Future<void> close() async {
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
    final radio = MeshCoreMapper.radio(h);
    final mapper = _mapper = MeshCoreMapper(radio.id);
    await setRadio(radio);
    final contacts = await session.getContacts();
    await store.upsertNodes(contacts.contacts.map(mapper.node));
    final slots = h.device.maxChannels ?? 8;
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
      case ContactsFullPush():
        log.add('MeshCore ${link.label}', "radio's contact list is full");
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
      ..add(session.nodes.listen((n) => unawaited(_onNode(n))));
  }

  final MeshtasticSession session;
  final List<StreamSubscription<Object?>> _subs = [];
  MeshtasticMapper? _mapper;

  @override
  int get maxTextBytes => meshtasticMaxPayload;

  @override
  Future<void> setUp() async {
    final config = await session.handshake();
    final radio = MeshtasticMapper.radio(config);
    final mapper = _mapper = MeshtasticMapper(radio.id);
    await setRadio(radio);
    await store.upsertNodes(
      config.nodes.values
          .where((n) => n.num != config.myInfo.nodeNum)
          .map(mapper.node),
    );
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
    if (!await store.setDeliveryByNativeId(radio.id, d.packetId, state)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
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
