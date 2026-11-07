import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mesh/mesh.dart';
import '../meshcore/meshcore.dart';
import '../meshtastic/meshtastic.dart';
import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'radio_target.dart';

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
  }) {
    final link = links.create(target, log: log);
    return switch (target.protocol) {
      RadioProtocol.meshcore => MeshCoreConnection(
        target: target,
        link: link,
        store: store,
        log: log,
        retryDelays: retryDelays,
      ),
      RadioProtocol.meshtastic => MeshtasticConnection(
        target: target,
        link: link,
        store: store,
        log: log,
        retryDelays: retryDelays,
      ),
    };
  }

  final RadioTarget target;
  final RadioLink link;
  final MeshStore store;
  final ConnectionLog log;
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
    try {
      await transmit(id, conversation, text);
    } on Object catch (e) {
      await store.setDelivery(id, Failed(describeError(e)));
    }
    return id;
  }

  /// Protocol-specific sending; records the native ID and first state.
  @protected
  Future<void> transmit(int id, Conversation conversation, String text);

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
  Future<void> transmit(int id, Conversation conversation, String text) async {
    switch (conversation) {
      case DirectConversation(:final node):
        final sent = await session.sendText(
          publicKey: fromHex(node.native),
          text: text,
        );
        await store.setNativeId(id, sent.ackCode);
        await store.setDelivery(id, MeshCoreMapper.sent(sent));
      case ChannelConversation(:final index):
        await session.sendChannelText(channel: index, text: text);
        await store.setDelivery(id, const Sent());
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

  @override
  Future<void> transmit(int id, Conversation conversation, String text) async {
    final packetId = switch (conversation) {
      DirectConversation(:final node) => await session.sendText(
        text,
        to: node.meshtasticNum!,
      ),
      ChannelConversation(:final index) => await session.sendText(
        text,
        channel: index,
      ),
    };
    await store.setNativeId(id, packetId);
  }

  @override
  Future<void> close() async {
    await session.sayGoodbye();
    for (final s in _subs) {
      await s.cancel();
    }
    await session.dispose();
    await super.close();
  }
}
