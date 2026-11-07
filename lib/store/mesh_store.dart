import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../mesh/model.dart';
import 'database.dart';

/// A message as stored, with its database ID.
class StoredMessage {
  const StoredMessage(this.id, this.message);

  final int id;
  final Message message;
}

/// The newest message in each conversation, for the inbox.
class ConversationSummary {
  const ConversationSummary(this.conversation, this.last);

  final Conversation conversation;
  final StoredMessage last;
}

/// Saves and reads the shared mesh model.
///
/// Every row carries the radio it belongs to, and every message keeps its
/// path facts (hops, SNR, RSSI, route, via MQTT).
class MeshStore {
  MeshStore(this.db);

  /// Opens (or creates) the database file at [file], off the UI thread.
  factory MeshStore.open(File file) =>
      MeshStore(MeshDatabase(NativeDatabase.createInBackground(file)));

  /// An in-memory database, for tests.
  factory MeshStore.memory() =>
      MeshStore(MeshDatabase(NativeDatabase.memory()));

  final MeshDatabase db;

  Future<void> close() => db.close();

  // Radios

  /// Saves [radio]; [connectedAt] records when it was last connected.
  Future<void> upsertRadio(Radio radio, {DateTime? connectedAt}) => db
      .into(db.radios)
      .insertOnConflictUpdate(
        RadiosCompanion.insert(
          id: radio.id.toString(),
          protocol: radio.protocol,
          name: radio.name,
          selfKey: radio.self.toString(),
          firmware: Value(radio.firmware),
          model: Value(radio.model),
          maxChannels: Value(radio.maxChannels),
          latitude: Value(radio.position?.latitude),
          longitude: Value(radio.position?.longitude),
          lastConnected: connectedAt == null
              ? const Value.absent()
              : Value(connectedAt),
        ),
      );

  /// Every saved radio, most recently connected first.
  Future<List<Radio>> radios() async {
    final rows =
        await (db.select(db.radios)..orderBy([
              (r) => OrderingTerm(
                expression: r.lastConnected,
                mode: OrderingMode.desc,
                nulls: NullsOrder.last,
              ),
            ]))
            .get();
    return rows.map(_radio).nonNulls.toList();
  }

  // Nodes

  /// Saves or replaces [node].
  Future<void> upsertNode(Node node) =>
      db.into(db.nodes).insertOnConflictUpdate(_nodeCompanion(node));

  /// Saves many nodes in one transaction (the start-up sync).
  Future<void> upsertNodes(Iterable<Node> nodes) => db.batch((b) {
    b.insertAllOnConflictUpdate(db.nodes, nodes.map(_nodeCompanion).toList());
  });

  /// The nodes [radio] knows, most recently heard first.
  Future<List<Node>> nodes(RadioId radio) => _nodesQuery(radio).get();

  /// Live version of [nodes].
  Stream<List<Node>> watchNodes(RadioId radio) => _nodesQuery(radio).watch();

  /// One node, if saved.
  Future<Node?> node(RadioId radio, NodeKey key) async {
    final row =
        await (db.select(db.nodes)..where(
              (n) =>
                  n.radioId.equals(radio.toString()) &
                  n.nodeKey.equals(key.toString()),
            ))
            .getSingleOrNull();
    return row == null ? null : _node(row);
  }

  /// The MeshCore node whose key starts with [prefixHex], if exactly one
  /// does (direct messages name the sender by a 6-byte prefix).
  Future<NodeKey?> meshCoreNodeByPrefix(RadioId radio, String prefixHex) async {
    final pattern = 'meshcore:${prefixHex.toLowerCase()}%';
    final rows =
        await (db.select(db.nodes)
              ..where(
                (n) =>
                    n.radioId.equals(radio.toString()) &
                    n.nodeKey.like(pattern),
              )
              ..limit(2))
            .get();
    return rows.length == 1 ? NodeKey.tryParse(rows.single.nodeKey) : null;
  }

  /// Forgets a node.
  Future<void> removeNode(RadioId radio, NodeKey key) =>
      (db.delete(db.nodes)..where(
            (n) =>
                n.radioId.equals(radio.toString()) &
                n.nodeKey.equals(key.toString()),
          ))
          .go();

  // Channels

  /// Replaces [radio]'s channel list with [channels].
  Future<void> replaceChannels(RadioId radio, Iterable<Channel> channels) =>
      db.transaction(() async {
        await (db.delete(
          db.channels,
        )..where((c) => c.radioId.equals(radio.toString()))).go();
        await db.batch((b) {
          b.insertAll(db.channels, [
            for (final c in channels)
              ChannelsCompanion.insert(
                radioId: radio.toString(),
                slot: c.index,
                name: c.name,
                kind: c.kind,
                isPrimary: Value(c.isPrimary),
              ),
          ]);
        });
      });

  /// [radio]'s channels in slot order.
  Future<List<Channel>> channels(RadioId radio) => _channelsQuery(radio).get();

  /// Live version of [channels].
  Stream<List<Channel>> watchChannels(RadioId radio) =>
      _channelsQuery(radio).watch();

  // Messages

  /// Saves [message] and returns its ID, or null if this received message
  /// was already saved.
  Future<int?> addMessage(Message message) async {
    final dedupe = message.outgoing ? null : dedupeKeyFor(message);
    if (dedupe != null) {
      final existing =
          await (db.select(db.messages)
                ..where((m) => m.dedupeKey.equals(dedupe))
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) return null;
    }
    final (code, reason, roundTrip) = _deliveryParts(message.delivery);
    final path = message.path;
    return db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            radioId: message.radioId.toString(),
            conversation: message.conversation.key,
            outgoing: message.outgoing,
            body: message.text,
            sentAt: message.sentAt,
            receivedAt: message.receivedAt,
            delivery: code.name,
            deliveryReason: Value(reason),
            roundTripMs: Value(roundTrip),
            fromKey: Value(message.from?.toString()),
            senderName: Value(message.senderName),
            hops: Value(path.hops),
            snr: Value(path.snr),
            rssi: Value(path.rssi),
            route: path.route,
            viaMqtt: Value(path.viaMqtt),
            nativeId: Value(message.nativeId),
            replyTo: Value(message.replyTo),
            isReaction: Value(message.isReaction),
            dedupeKey: Value(dedupe),
          ),
        );
  }

  /// Moves message [id] to [state], unless that would go backwards (a
  /// delivered message never returns to "sent" or "failed").
  Future<bool> setDelivery(int id, DeliveryState state) async {
    final row = await (db.select(
      db.messages,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row == null || !_isProgress(row.delivery, state)) return false;
    await _writeDelivery(db.messages.id.equals(id), state);
    return true;
  }

  /// Like [setDelivery], for the outgoing message on [radio] whose protocol
  /// ID (MeshCore ack code or Meshtastic packet ID) is [nativeId].
  Future<bool> setDeliveryByNativeId(
    RadioId radio,
    int nativeId,
    DeliveryState state,
  ) async {
    final row =
        await (db.select(db.messages)
              ..where(
                (m) =>
                    m.radioId.equals(radio.toString()) &
                    m.nativeId.equals(nativeId) &
                    m.outgoing.equals(true),
              )
              ..orderBy([(m) => OrderingTerm.desc(m.id)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return false;
    return setDelivery(row.id, state);
  }

  /// Sets the protocol ID of an outgoing message once the radio assigns it.
  Future<void> setNativeId(int id, int nativeId) =>
      (db.update(db.messages)..where((m) => m.id.equals(id))).write(
        MessagesCompanion(nativeId: Value(nativeId)),
      );

  /// Messages in [conversation], oldest first; the newest [limit] of them.
  Future<List<StoredMessage>> messages(
    Conversation conversation, {
    int limit = 200,
  }) async =>
      (await _messagesQuery(conversation, limit).get()).reversed.toList();

  /// Live version of [messages].
  Stream<List<StoredMessage>> watchMessages(
    Conversation conversation, {
    int limit = 200,
  }) => _messagesQuery(
    conversation,
    limit,
  ).watch().map((rows) => rows.reversed.toList());

  /// The newest message of every conversation, newest first.
  Stream<List<ConversationSummary>> watchConversations() =>
      _conversationsQuery().watch();

  /// One-off version of [watchConversations].
  Future<List<ConversationSummary>> conversations() =>
      _conversationsQuery().get();

  /// The dedupe key for a received message.
  ///
  /// Meshtastic packet IDs are unique per sender; otherwise sender, the
  /// sender's clock and the text identify a repeat.
  static String dedupeKeyFor(Message m) {
    final who = m.from?.toString() ?? m.senderName ?? '?';
    if (m.nativeId != null && m.from != null) {
      return '${m.radioId}|$who|#${m.nativeId}';
    }
    final secs = m.sentAt.millisecondsSinceEpoch ~/ 1000;
    return '${m.conversation.key}|$who|$secs|${m.text.hashCode}';
  }

  // Internals

  Selectable<Node> _nodesQuery(RadioId radio) =>
      (db.select(db.nodes)
            ..where((n) => n.radioId.equals(radio.toString()))
            ..orderBy([
              (n) => OrderingTerm(
                expression: n.lastHeard,
                mode: OrderingMode.desc,
                nulls: NullsOrder.last,
              ),
              (n) => OrderingTerm.asc(n.name),
            ]))
          .map(_node)
          .map((n) => n!);

  Selectable<Channel> _channelsQuery(RadioId radio) =>
      (db.select(db.channels)
            ..where((c) => c.radioId.equals(radio.toString()))
            ..orderBy([(c) => OrderingTerm.asc(c.slot)]))
          .map(
            (r) => Channel(
              radioId: radio,
              index: r.slot,
              name: r.name,
              kind: r.kind,
              isPrimary: r.isPrimary,
            ),
          );

  Selectable<StoredMessage> _messagesQuery(
    Conversation conversation,
    int limit,
  ) {
    final newest = db.select(db.messages)
      ..where((m) => m.conversation.equals(conversation.key))
      ..orderBy([(m) => OrderingTerm.desc(m.id)])
      ..limit(limit);
    return newest.map(_message).map((m) => m!);
  }

  Selectable<ConversationSummary> _conversationsQuery() {
    final query = db.customSelect(
      'SELECT m.* FROM messages m '
      'JOIN (SELECT conversation, MAX(id) AS id FROM messages '
      'GROUP BY conversation) latest ON m.id = latest.id '
      'ORDER BY m.id DESC',
      readsFrom: {db.messages},
    );
    return query.asyncMap((row) async {
      final data = await db.messages.mapFromRow(row);
      final stored = _message(data)!;
      return ConversationSummary(stored.message.conversation, stored);
    });
  }

  Radio? _radio(RadioRow r) {
    final id = RadioId.tryParse(r.id);
    final self = NodeKey.tryParse(r.selfKey);
    if (id == null || self == null) return null;
    return Radio(
      id: id,
      name: r.name,
      self: self,
      firmware: r.firmware,
      model: r.model,
      maxChannels: r.maxChannels,
      position: r.latitude == null || r.longitude == null
          ? null
          : GeoPoint(r.latitude!, r.longitude!),
    );
  }

  NodesCompanion _nodeCompanion(Node n) => NodesCompanion.insert(
    radioId: n.radioId.toString(),
    nodeKey: n.key.toString(),
    name: n.name,
    shortName: Value(n.shortName),
    kind: n.kind,
    latitude: Value(n.position?.latitude),
    longitude: Value(n.position?.longitude),
    altitude: Value(n.position?.altitude),
    lastHeard: Value(n.lastHeard),
    hops: Value(n.path.hops),
    snr: Value(n.path.snr),
    rssi: Value(n.path.rssi),
    route: n.path.route,
    viaMqtt: Value(n.path.viaMqtt),
    favorite: Value(n.isFavorite),
    battery: Value(n.batteryPercent),
    canMessage: Value(n.canMessage),
  );

  Node? _node(NodeRow r) {
    final radio = RadioId.tryParse(r.radioId);
    final key = NodeKey.tryParse(r.nodeKey);
    if (radio == null || key == null) return null;
    return Node(
      key: key,
      radioId: radio,
      name: r.name,
      shortName: r.shortName,
      kind: r.kind,
      position: r.latitude == null || r.longitude == null
          ? null
          : GeoPoint(r.latitude!, r.longitude!, altitude: r.altitude),
      lastHeard: r.lastHeard,
      path: PathFacts(
        hops: r.hops,
        snr: r.snr,
        rssi: r.rssi,
        route: r.route,
        viaMqtt: r.viaMqtt,
      ),
      isFavorite: r.favorite,
      batteryPercent: r.battery,
      canMessage: r.canMessage,
    );
  }

  StoredMessage? _message(MessageRow r) {
    final conversation = Conversation.tryParse(r.conversation);
    if (conversation == null) return null;
    return StoredMessage(
      r.id,
      Message(
        conversation: conversation,
        text: r.body,
        outgoing: r.outgoing,
        sentAt: r.sentAt,
        receivedAt: r.receivedAt,
        delivery: _deliveryFrom(r),
        from: r.fromKey == null ? null : NodeKey.tryParse(r.fromKey!),
        senderName: r.senderName,
        path: PathFacts(
          hops: r.hops,
          snr: r.snr,
          rssi: r.rssi,
          route: r.route,
          viaMqtt: r.viaMqtt,
        ),
        nativeId: r.nativeId,
        replyTo: r.replyTo,
        isReaction: r.isReaction,
      ),
    );
  }

  Future<void> _writeDelivery(Expression<bool> where, DeliveryState state) {
    final (code, reason, roundTrip) = _deliveryParts(state);
    return (db.update(db.messages)..where((_) => where)).write(
      MessagesCompanion(
        delivery: Value(code.name),
        deliveryReason: Value(reason),
        roundTripMs: Value(roundTrip),
      ),
    );
  }

  static (DeliveryCode, String?, int?) _deliveryParts(DeliveryState s) =>
      switch (s) {
        Pending() => (DeliveryCode.pending, null, null),
        Sent(flood: true) => (DeliveryCode.sentFlood, null, null),
        Sent() => (DeliveryCode.sent, null, null),
        Relayed() => (DeliveryCode.relayed, null, null),
        Delivered(:final roundTrip) => (
          DeliveryCode.delivered,
          null,
          roundTrip?.inMilliseconds,
        ),
        Failed(:final reason) => (DeliveryCode.failed, reason, null),
        Received() => (DeliveryCode.received, null, null),
      };

  static DeliveryState _deliveryFrom(MessageRow r) {
    final code = DeliveryCode.values
        .where((c) => c.name == r.delivery)
        .firstOrNull;
    return switch (code) {
      DeliveryCode.pending => const Pending(),
      DeliveryCode.sent => const Sent(),
      DeliveryCode.sentFlood => const Sent(flood: true),
      DeliveryCode.relayed => const Relayed(),
      DeliveryCode.delivered => Delivered(
        roundTrip: r.roundTripMs == null
            ? null
            : Duration(milliseconds: r.roundTripMs!),
      ),
      DeliveryCode.failed => Failed(r.deliveryReason ?? 'Delivery failed'),
      DeliveryCode.received || null => const Received(),
    };
  }

  static int _rank(String code) => switch (code) {
    'pending' => 0,
    'sent' || 'sentFlood' => 1,
    'relayed' => 2,
    'delivered' => 4,
    _ => -1,
  };

  /// Delivery only moves forward; a failure can't undo a delivery, and a
  /// retry (back to pending/sent) can follow a failure.
  static bool _isProgress(String current, DeliveryState next) {
    if (current == 'received' || next is Received) return false;
    if (current == 'delivered') return false;
    if (next is Failed) return true;
    if (current == 'failed') return next is Pending || next is Sent;
    final nextCode = _deliveryParts(next).$1.name;
    return _rank(nextCode) > _rank(current);
  }
}
