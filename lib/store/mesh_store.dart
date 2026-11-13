import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../mesh/diagnostics.dart';
import '../mesh/identity.dart';
import '../mesh/model.dart';
import '../mesh/places.dart';
import '../mesh/telemetry.dart';
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
  /// [key] is needed if the file is encrypted.
  factory MeshStore.open(File file, {String? key}) => MeshStore(
    MeshDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: key == null ? null : (db) => db.execute("PRAGMA key = '$key'"),
      ),
    ),
  );

  /// An in-memory database, for tests.
  factory MeshStore.memory() =>
      MeshStore(MeshDatabase(NativeDatabase.memory()));

  final MeshDatabase db;
  final _incoming = StreamController<StoredMessage>.broadcast();

  /// Received messages as they are saved (repeats are left out), for
  /// notifications.
  Stream<StoredMessage> get incoming => _incoming.stream;

  Future<void> close() async {
    await _incoming.close();
    await db.close();
  }

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

  /// Every saved radio, as they change.
  Stream<List<Radio>> watchRadios() => db
      .select(db.radios)
      .watch()
      .map((rows) => rows.map(_radio).nonNulls.toList());

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

  /// Every radio's nodes, most recently heard first.
  Stream<List<Node>> watchAllNodes() =>
      (db.select(db.nodes)..orderBy([
            (n) => OrderingTerm(
              expression: n.lastHeard,
              mode: OrderingMode.desc,
              nulls: NullsOrder.last,
            ),
            (n) => OrderingTerm.asc(n.name),
          ]))
          .map(_node)
          .watch()
          .map((rows) => rows.nonNulls.toList());

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

  /// Every radio's channels, by radio then slot.
  Stream<List<Channel>> watchAllChannels() =>
      (db.select(db.channels)..orderBy([
            (c) => OrderingTerm.asc(c.radioId),
            (c) => OrderingTerm.asc(c.slot),
          ]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                if (RadioId.tryParse(r.radioId) case final id?)
                  Channel(
                    radioId: id,
                    index: r.slot,
                    name: r.name,
                    kind: r.kind,
                    isPrimary: r.isPrimary,
                  ),
            ],
          );

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
    final id = await db.into(db.messages).insert(_row(message, dedupe));
    if (!message.outgoing && !_incoming.isClosed) {
      _incoming.add(StoredMessage(id, message));
    }
    return id;
  }

  MessagesCompanion _row(Message message, String? dedupe) {
    final (code, reason, roundTrip) = _deliveryParts(message.delivery);
    final path = message.path;
    return MessagesCompanion.insert(
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
      attempts: Value(message.attempts),
      authenticated: Value(message.authenticated),
      dedupeKey: Value(dedupe),
    );
  }

  /// Adds [restored] messages from an export, skipping any already here.
  /// All or nothing. Returns how many were added.
  ///
  /// Doesn't raise notifications. A conversation with nothing unread stays
  /// that way, so old messages don't show up as new.
  Future<int> restoreMessages(List<Message> restored) => db.transaction(
    () async {
      String content(String conversation, bool out, DateTime sent, String t) =>
          '$conversation|$out|${sent.millisecondsSinceEpoch ~/ 1000}|$t';
      final seen = <String>{};
      final keys = <String>{};
      for (final r in await db.select(db.messages).get()) {
        seen.add(content(r.conversation, r.outgoing, r.sentAt, r.body));
        if (r.dedupeKey != null) keys.add(r.dedupeKey!);
      }
      final unread = await _unreadQuery().get();
      final hadUnread = {for (final r in unread) r.read<String>('c')};
      final touched = <Conversation>{};
      var added = 0;
      for (final m in restored) {
        final dedupe = m.outgoing ? null : dedupeKeyFor(m);
        final fresh = seen.add(
          content(m.conversation.key, m.outgoing, m.sentAt, m.text),
        );
        if (!fresh || (dedupe != null && !keys.add(dedupe))) continue;
        await db.into(db.messages).insert(_row(m, dedupe));
        touched.add(m.conversation);
        added++;
      }
      for (final c in touched) {
        if (!hadUnread.contains(c.key)) await markRead(c);
      }
      return added;
    },
  );

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

  /// Records how many times an outgoing message has been sent.
  Future<void> setAttempts(int id, int attempts) =>
      (db.update(db.messages)..where((m) => m.id.equals(id))).write(
        MessagesCompanion(attempts: Value(attempts)),
      );

  /// One stored message, if it exists.
  Future<StoredMessage?> message(int id) async {
    final row = await (db.select(
      db.messages,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    return row == null ? null : _message(row);
  }

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

  /// The newest [limit] messages of every conversation, newest first,
  /// without reactions; for the timeline.
  Stream<List<StoredMessage>> watchRecentMessages({int limit = 300}) =>
      (db.select(db.messages)
            ..where((m) => m.isReaction.equals(false))
            ..orderBy([
              (m) => OrderingTerm.desc(m.receivedAt),
              (m) => OrderingTerm.desc(m.id),
            ])
            ..limit(limit))
          .map(_message)
          .watch()
          .map((rows) => rows.nonNulls.toList());

  /// Messages containing [query] (ignoring case for plain letters), newest
  /// first. Reactions aren't messages anyone would look for.
  Future<List<StoredMessage>> searchMessages(
    String query, {
    int limit = 100,
  }) async {
    final escaped = query.replaceAllMapped(
      RegExp(r'[\\%_]'),
      (m) => '\\${m[0]}',
    );
    final rows = await db
        .customSelect(
          r"SELECT * FROM messages WHERE is_reaction = 0 "
          r"AND body LIKE ? ESCAPE '\' ORDER BY id DESC LIMIT ?",
          variables: [
            Variable.withString('%$escaped%'),
            Variable.withInt(limit),
          ],
          readsFrom: {db.messages},
        )
        .get();
    return [for (final r in rows) ?_message(db.messages.map(r.data))];
  }

  /// Every message, or those in [only], oldest first, for exporting.
  Future<List<StoredMessage>> allMessages({Conversation? only}) async {
    final query = db.select(db.messages)
      ..orderBy([(m) => OrderingTerm.asc(m.id)]);
    if (only != null) query.where((m) => m.conversation.equals(only.key));
    return [for (final r in await query.get()) ?_message(r)];
  }

  /// Removes one message from this device.
  Future<void> deleteMessage(int id) =>
      (db.delete(db.messages)..where((m) => m.id.equals(id))).go();

  /// Removes every message in [conversation] from this device.
  Future<void> deleteConversation(Conversation conversation) => (db.delete(
    db.messages,
  )..where((m) => m.conversation.equals(conversation.key))).go();

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

  /// A conversation's name: the node's or channel's name.
  Future<String> conversationTitle(Conversation c) async {
    switch (c) {
      case DirectConversation(:final node):
        return (await this.node(c.radioId, node))?.displayName ?? node.short;
      case ChannelConversation(:final index):
        for (final ch in await channels(c.radioId)) {
          if (ch.index == index) return ch.name;
        }
        return '#$index';
    }
  }

  // Places

  /// Saves [items], all or nothing.
  Future<void> addPlaces(List<Place> items) => db.batch(
    (b) => b.insertAll(db.places, [
      for (final p in items)
        PlacesCompanion.insert(
          kind: p.kind.name,
          name: p.name,
          points: jsonEncode([
            for (final x in p.points)
              [x.latitude, x.longitude, if (x.altitude != null) x.altitude],
          ]),
          radiusM: Value(p.radiusM),
          alerts: Value(p.alerts),
        ),
    ]),
  );

  /// Saved places as they change.
  Stream<List<Place>> watchPlaces() =>
      (db.select(db.places)..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch()
          .map((rows) => [for (final r in rows) ?_place(r)]);

  /// Forgets a place.
  Future<void> deletePlace(int id) =>
      (db.delete(db.places)..where((p) => p.id.equals(id))).go();

  Place? _place(PlaceRow r) {
    final kind = PlaceKind.values.asNameMap()[r.kind];
    if (kind == null) return null;
    final points = <GeoPoint>[];
    for (final raw in jsonDecode(r.points) as List<Object?>) {
      final x = (raw! as List<Object?>).cast<num>();
      points.add(
        GeoPoint(
          x[0].toDouble(),
          x[1].toDouble(),
          altitude: x.length > 2 ? x[2].toInt() : null,
        ),
      );
    }
    if (points.isEmpty) return null;
    return Place(
      id: r.id,
      kind: kind,
      name: r.name,
      points: points,
      radiusM: r.radiusM,
      alerts: r.alerts,
    );
  }

  // MeshCore radio contacts

  /// Records that [radio]'s contact list is exactly [keys].
  Future<void> replaceRadioContacts(RadioId radio, Iterable<NodeKey> keys) =>
      db.transaction(() async {
        await (db.delete(
          db.radioContacts,
        )..where((c) => c.radioId.equals(radio.toString()))).go();
        await db.batch(
          (b) => b.insertAll(db.radioContacts, [
            for (final k in keys)
              RadioContactsCompanion.insert(
                radioId: radio.toString(),
                nodeKey: k.toString(),
              ),
          ], mode: InsertMode.insertOrIgnore),
        );
      });

  /// Records that [key] was added to or removed from [radio]'s contacts.
  Future<void> setOnRadio(RadioId radio, NodeKey key, bool onRadio) async {
    if (onRadio) {
      await db
          .into(db.radioContacts)
          .insert(
            RadioContactsCompanion.insert(
              radioId: radio.toString(),
              nodeKey: key.toString(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.delete(db.radioContacts)..where(
            (c) =>
                c.radioId.equals(radio.toString()) &
                c.nodeKey.equals(key.toString()),
          ))
          .go();
    }
  }

  SimpleSelectStatement<$RadioContactsTable, RadioContactRow> _contactsQuery(
    RadioId radio,
  ) =>
      db.select(db.radioContacts)
        ..where((c) => c.radioId.equals(radio.toString()));

  /// The nodes in [radio]'s own contact list.
  Future<Set<NodeKey>> radioContacts(RadioId radio) async => {
    for (final r in await _contactsQuery(radio).get())
      ?NodeKey.tryParse(r.nodeKey),
  };

  /// [radioContacts] for every radio, as they change, as
  /// `radioId|nodeKey` strings.
  Stream<Set<String>> watchAllRadioContacts() => db
      .select(db.radioContacts)
      .watch()
      .map((rows) => {for (final r in rows) '${r.radioId}|${r.nodeKey}'});

  // Read state and mutes

  /// Unread received messages per conversation key (reactions don't count).
  Stream<Map<String, int>> watchUnread() => _unreadQuery().watch().map(
    (rows) => {for (final r in rows) r.read<String>('c'): r.read<int>('n')},
  );

  Selectable<QueryRow> _unreadQuery() => db.customSelect(
    'SELECT m.conversation AS c, COUNT(*) AS n FROM messages m '
    'LEFT JOIN conversation_states s ON s.conversation = m.conversation '
    'WHERE m.outgoing = 0 AND m.is_reaction = 0 '
    'AND m.id > COALESCE(s.last_read_id, 0) '
    'GROUP BY m.conversation',
    readsFrom: {db.messages, db.conversationStates},
  );

  /// Marks everything in [conversation] as read.
  Future<void> markRead(Conversation conversation) => db.customUpdate(
    'INSERT INTO conversation_states (conversation, last_read_id) '
    'VALUES (?1, (SELECT COALESCE(MAX(id), 0) FROM messages '
    'WHERE conversation = ?1)) '
    'ON CONFLICT (conversation) DO UPDATE '
    'SET last_read_id = excluded.last_read_id',
    variables: [Variable.withString(conversation.key)],
    updates: {db.conversationStates},
  );

  /// Marks every conversation as read.
  Future<void> markAllRead() => db.customUpdate(
    'INSERT INTO conversation_states (conversation, last_read_id) '
    'SELECT conversation, MAX(id) FROM messages WHERE true '
    'GROUP BY conversation ON CONFLICT (conversation) DO UPDATE '
    'SET last_read_id = excluded.last_read_id',
    updates: {db.conversationStates},
  );

  /// Mutes [conversation] until [until]; null unmutes it.
  Future<void> setMuted(Conversation conversation, DateTime? until) =>
      db.customUpdate(
        'INSERT INTO conversation_states (conversation, muted_until) '
        'VALUES (?1, ?2) ON CONFLICT (conversation) DO UPDATE '
        'SET muted_until = excluded.muted_until',
        variables: [
          Variable.withString(conversation.key),
          Variable<DateTime>(until),
        ],
        updates: {db.conversationStates},
      );

  /// When each muted conversation's mute ends, by conversation key.
  Stream<Map<String, DateTime>> watchMutes() =>
      (db.select(db.conversationStates)..where((s) => s.mutedUntil.isNotNull()))
          .watch()
          .map((rows) => {for (final r in rows) r.conversation: r.mutedUntil!});

  /// Whether [conversation] is muted at [now].
  Future<bool> isMuted(Conversation conversation, DateTime now) async {
    final row = await (db.select(
      db.conversationStates,
    )..where((s) => s.conversation.equals(conversation.key))).getSingleOrNull();
    final until = row?.mutedUntil;
    return until != null && until.isAfter(now);
  }

  // Preferences

  /// A preference, or null when never set.
  Future<String?> preference(String name) async => (await (db.select(
    db.preferences,
  )..where((p) => p.name.equals(name))).getSingleOrNull())?.value;

  /// Saves a preference.
  Future<void> setPreference(String name, String value) => db
      .into(db.preferences)
      .insertOnConflictUpdate(
        PreferencesCompanion.insert(name: name, value: value),
      );

  /// A preference as it changes.
  Stream<String?> watchPreference(String name) =>
      (db.select(db.preferences)..where((p) => p.name.equals(name)))
          .watchSingleOrNull()
          .map((r) => r?.value);

  // Traces

  /// How many traces are kept for each node on each radio.
  static const tracesKept = 50;

  static String _hopsJson(List<TraceHop> hops) => jsonEncode([
    for (final h in hops) {'label': h.label, 'snr': h.snr},
  ]);

  static List<TraceHop> _hopsOf(String text) => [
    for (final h in jsonDecode(text) as List<Object?>)
      TraceHop(
        (h as Map<String, Object?>)['label'] as String,
        (h['snr'] as num?)?.toDouble(),
      ),
  ];

  /// Saves a finished trace and drops all but the newest [tracesKept] for
  /// that node.
  Future<void> addTrace(RadioId radio, String targetName, TraceResult r) =>
      db.transaction(() async {
        await db
            .into(db.traceRecords)
            .insert(
              TraceRecordsCompanion.insert(
                radioId: radio.toString(),
                nodeKey: r.target.toString(),
                targetName: targetName,
                time: r.time,
                towards: _hopsJson(r.towards),
                back: _hopsJson(r.back),
              ),
            );
        final old = await (_tracesQuery(
          radio,
          r.target,
        )..limit(1 << 31, offset: tracesKept)).get();
        if (old.isEmpty) return;
        await (db.delete(
          db.traceRecords,
        )..where((t) => t.id.isIn(old.map((o) => o.id)))).go();
      });

  SimpleSelectStatement<$TraceRecordsTable, TraceRow> _tracesQuery(
    RadioId radio,
    NodeKey node,
  ) => db.select(db.traceRecords)
    ..where(
      (t) =>
          t.radioId.equals(radio.toString()) &
          t.nodeKey.equals(node.toString()),
    )
    ..orderBy([
      (t) => OrderingTerm.desc(t.time),
      (t) => OrderingTerm.desc(t.id),
    ]);

  /// A node's saved traces, newest first.
  Future<List<SavedTrace>> traces(RadioId radio, NodeKey node) async => [
    for (final r in await _tracesQuery(radio, node).get())
      SavedTrace(
        id: r.id,
        targetName: r.targetName,
        result: TraceResult(
          target: node,
          towards: _hopsOf(r.towards),
          back: _hopsOf(r.back),
          time: r.time,
        ),
      ),
  ];

  /// Deletes a node's saved traces.
  Future<void> clearTraces(RadioId radio, NodeKey node) =>
      (db.delete(db.traceRecords)..where(
            (t) =>
                t.radioId.equals(radio.toString()) &
                t.nodeKey.equals(node.toString()),
          ))
          .go();

  // Telemetry

  /// Saves a reading and drops readings older than [telemetryKeep].
  Future<void> addTelemetry(TelemetryPoint p) async {
    if (p.isEmpty) return;
    await db.transaction(() async {
      await db
          .into(db.telemetryReadings)
          .insert(
            TelemetryReadingsCompanion.insert(
              radioId: p.radioId.toString(),
              nodeKey: p.node.toString(),
              time: p.time,
              batteryLevel: Value(p.batteryLevel),
              voltage: Value(p.voltage),
              channelUtilization: Value(p.channelUtilization),
              airUtilTx: Value(p.airUtilTx),
              uptimeSeconds: Value(p.uptimeSeconds),
              temperature: Value(p.temperature),
              relativeHumidity: Value(p.relativeHumidity),
              barometricPressure: Value(p.barometricPressure),
            ),
          );
      final cutoff = p.time.subtract(telemetryKeep);
      await (db.delete(
        db.telemetryReadings,
      )..where((t) => t.time.isSmallerThanValue(cutoff))).go();
    });
  }

  SimpleSelectStatement<$TelemetryReadingsTable, TelemetryRow> _telemetryQuery(
    RadioId radio,
    NodeKey node,
    DateTime since,
  ) => db.select(db.telemetryReadings)
    ..where(
      (t) =>
          t.radioId.equals(radio.toString()) &
          t.nodeKey.equals(node.toString()) &
          t.time.isBiggerOrEqualValue(since),
    )
    ..orderBy([(t) => OrderingTerm.asc(t.time)]);

  /// A node's readings since [since], oldest first.
  Future<List<TelemetryPoint>> telemetry(
    RadioId radio,
    NodeKey node, {
    required DateTime since,
  }) async => [
    for (final r in await _telemetryQuery(radio, node, since).get())
      _telemetryPoint(radio, node, r),
  ];

  /// [telemetry], updated as readings arrive.
  Stream<List<TelemetryPoint>> watchTelemetry(
    RadioId radio,
    NodeKey node, {
    required DateTime since,
  }) => _telemetryQuery(radio, node, since).watch().map(
    (rows) => [for (final r in rows) _telemetryPoint(radio, node, r)],
  );

  TelemetryPoint _telemetryPoint(RadioId radio, NodeKey node, TelemetryRow r) =>
      TelemetryPoint(
        radioId: radio,
        node: node,
        time: r.time,
        batteryLevel: r.batteryLevel,
        voltage: r.voltage,
        channelUtilization: r.channelUtilization,
        airUtilTx: r.airUtilTx,
        uptimeSeconds: r.uptimeSeconds,
        temperature: r.temperature,
        relativeHumidity: r.relativeHumidity,
        barometricPressure: r.barometricPressure,
      );

  // Verified keys

  /// Records that [node]'s [publicKey] was confirmed.
  Future<void> verify(
    NodeKey node,
    List<int> publicKey,
    VerificationMethod method, {
    DateTime? at,
  }) => db
      .into(db.verifiedKeys)
      .insertOnConflictUpdate(
        VerifiedKeysCompanion.insert(
          nodeKey: node.toString(),
          publicKeyHex: _hex(publicKey),
          verifiedAt: at ?? DateTime.now(),
          method: method.name,
        ),
      );

  /// Forgets a confirmation.
  Future<void> unverify(NodeKey node) => (db.delete(
    db.verifiedKeys,
  )..where((v) => v.nodeKey.equals(node.toString()))).go();

  /// All confirmations, by node.
  Stream<Map<NodeKey, Verification>> watchVerifications() =>
      db.select(db.verifiedKeys).watch().map(_verifications);

  /// One-off version of [watchVerifications].
  Future<Map<NodeKey, Verification>> verifications() async =>
      _verifications(await db.select(db.verifiedKeys).get());

  Map<NodeKey, Verification> _verifications(List<VerifiedKeyRow> rows) => {
    for (final r in rows)
      // The key is also used in the value, so `?key:` doesn't fit here.
      // ignore: use_null_aware_elements
      if (NodeKey.tryParse(r.nodeKey) case final key?)
        key: Verification(
          node: key,
          publicKey: Uint8List.fromList(_unhex(r.publicKeyHex)),
          at: r.verifiedAt,
          method:
              VerificationMethod.values
                  .where((m) => m.name == r.method)
                  .firstOrNull ??
              VerificationMethod.compared,
        ),
  };

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
      ..orderBy([
        (m) => OrderingTerm.desc(m.receivedAt),
        (m) => OrderingTerm.desc(m.id),
      ])
      ..limit(limit);
    return newest.map(_message).map((m) => m!);
  }

  Selectable<ConversationSummary> _conversationsQuery() {
    final query = db.customSelect(
      'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY conversation '
      'ORDER BY received_at DESC, id DESC) AS newest FROM messages) '
      'WHERE newest = 1 ORDER BY received_at DESC, id DESC',
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
    routeHex: Value(n.route.isEmpty ? null : _hex(n.route)),
    // Don't wipe a known key with an empty one from a partial update.
    publicKeyHex: n.publicKey.isEmpty
        ? const Value.absent()
        : Value(_hex(n.publicKey)),
  );

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _unhex(String? h) => h == null || h.length.isOdd
      ? const []
      : [
          for (var i = 0; i < h.length; i += 2)
            int.parse(h.substring(i, i + 2), radix: 16),
        ];

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
      route: _unhex(r.routeHex),
      publicKey: _unhex(r.publicKeyHex),
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
        attempts: r.attempts,
        authenticated: r.authenticated,
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

  /// The stable name of a delivery state, as stored and exported.
  static String deliveryCode(DeliveryState s) => _deliveryParts(s).$1.name;

  /// A delivery state read from an export. A message still waiting when it
  /// was exported will never be sent, so it comes back as failed.
  static DeliveryState deliveryFromExport(
    String? code,
    String? reason, {
    required bool outgoing,
  }) {
    if (!outgoing) return const Received();
    return switch (code) {
      'sent' => const Sent(),
      'sentFlood' => const Sent(flood: true),
      'relayed' => const Relayed(),
      'delivered' => const Delivered(),
      'pending' => const Failed('Not sent before the export'),
      _ => Failed(reason ?? 'Delivery failed'),
    };
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
