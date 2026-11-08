import 'package:drift/drift.dart';

import '../mesh/model.dart';
import '../mesh/telemetry.dart';
import '../radio/radio_link.dart';
import 'database.steps.dart';

part 'database.g.dart';

/// Radios the app has connected to.
@DataClassName('RadioRow')
class Radios extends Table {
  /// `RadioId.toString()`, e.g. `meshtastic:!a1b2c3d4`.
  TextColumn get id => text()();
  TextColumn get protocol => textEnum<RadioProtocol>()();
  TextColumn get name => text()();

  /// `NodeKey.toString()` of the radio's own node.
  TextColumn get selfKey => text()();
  TextColumn get firmware => text().withDefault(const Constant(''))();
  TextColumn get model => text().withDefault(const Constant(''))();
  IntColumn get maxChannels => integer().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  DateTimeColumn get lastConnected => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Nodes each radio knows, with how they were last heard.
@DataClassName('NodeRow')
class Nodes extends Table {
  TextColumn get radioId => text()();

  /// `NodeKey.toString()`.
  TextColumn get nodeKey => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().withDefault(const Constant(''))();
  TextColumn get kind => textEnum<NodeKind>()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get altitude => integer().nullable()();
  DateTimeColumn get lastHeard => dateTime().nullable()();
  IntColumn get hops => integer().nullable()();
  RealColumn get snr => real().nullable()();
  IntColumn get rssi => integer().nullable()();
  TextColumn get route => textEnum<RouteKind>()();
  BoolColumn get viaMqtt => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get battery => integer().nullable()();
  BoolColumn get canMessage => boolean().withDefault(const Constant(true))();

  /// MeshCore out-path as hex (repeater hash prefixes, in order). Schema v3.
  TextColumn get routeHex => text().nullable()();

  /// The node's public key as hex (MeshCore: its identity; Meshtastic: the
  /// key it advertises for encrypted direct messages). Schema v4.
  TextColumn get publicKeyHex => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {radioId, nodeKey};
}

/// Channel slots on each radio. Keys are never stored here.
@DataClassName('ChannelRow')
class Channels extends Table {
  TextColumn get radioId => text()();
  IntColumn get slot => integer()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<ChannelKind>()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {radioId, slot};
}

/// Every message sent or received, with its path facts.
@DataClassName('MessageRow')
@TableIndex(name: 'messages_by_conversation', columns: {#conversation, #id})
@TableIndex(name: 'messages_by_native_id', columns: {#radioId, #nativeId})
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get radioId => text()();

  /// `Conversation.key`.
  TextColumn get conversation => text()();
  BoolColumn get outgoing => boolean()();
  TextColumn get body => text()();
  DateTimeColumn get sentAt => dateTime()();
  DateTimeColumn get receivedAt => dateTime()();

  /// One of [DeliveryCode] names.
  TextColumn get delivery => text()();
  TextColumn get deliveryReason => text().nullable()();
  IntColumn get roundTripMs => integer().nullable()();
  TextColumn get fromKey => text().nullable()();
  TextColumn get senderName => text().nullable()();
  IntColumn get hops => integer().nullable()();
  RealColumn get snr => real().nullable()();
  IntColumn get rssi => integer().nullable()();
  TextColumn get route => textEnum<RouteKind>()();
  BoolColumn get viaMqtt => boolean().withDefault(const Constant(false))();
  IntColumn get nativeId => integer().nullable()();
  IntColumn get replyTo => integer().nullable()();
  BoolColumn get isReaction => boolean().withDefault(const Constant(false))();

  /// Times this outgoing message was sent (retries included). Schema v2.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// The sender is proven by encryption (MeshCore direct messages,
  /// Meshtastic public-key direct messages). Schema v4.
  BoolColumn get authenticated =>
      boolean().withDefault(const Constant(false))();

  /// Identifies a received message so a repeat isn't stored twice.
  TextColumn get dedupeKey => text().nullable().unique()();
}

/// Keys the person has confirmed belong to who they say. Schema v4.
@DataClassName('VerifiedKeyRow')
class VerifiedKeys extends Table {
  /// `NodeKey.toString()`.
  TextColumn get nodeKey => text()();

  /// The public key that was confirmed; a different key later means the
  /// node changed (re-flashed, or someone else) and needs checking again.
  TextColumn get publicKeyHex => text()();
  DateTimeColumn get verifiedAt => dateTime()();

  /// How: `qr` (scanned their code) or `compared` (fingerprints compared).
  TextColumn get method => text()();

  @override
  Set<Column<Object>> get primaryKey => {nodeKey};
}

/// Telemetry readings from nodes, kept for [telemetryKeep]. Schema v5.
@DataClassName('TelemetryRow')
@TableIndex(name: 'telemetry_by_node', columns: {#radioId, #nodeKey, #time})
class TelemetryReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get radioId => text()();

  /// `NodeKey.toString()`.
  TextColumn get nodeKey => text()();
  DateTimeColumn get time => dateTime()();
  IntColumn get batteryLevel => integer().nullable()();
  RealColumn get voltage => real().nullable()();
  RealColumn get channelUtilization => real().nullable()();
  RealColumn get airUtilTx => real().nullable()();
  IntColumn get uptimeSeconds => integer().nullable()();
  RealColumn get temperature => real().nullable()();
  RealColumn get relativeHumidity => real().nullable()();
  RealColumn get barometricPressure => real().nullable()();
}

/// What the person has read and muted, per conversation. Schema v6.
@DataClassName('ConversationStateRow')
class ConversationStates extends Table {
  /// `Conversation.key`.
  TextColumn get conversation => text()();

  /// Messages up to and including this ID have been read.
  IntColumn get lastReadId => integer().withDefault(const Constant(0))();

  /// No notifications until then; null when not muted.
  DateTimeColumn get mutedUntil => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {conversation};
}

/// App preferences as text, by name. Schema v6.
@DataClassName('PreferenceRow')
class Preferences extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

/// How delivery states are stored.
enum DeliveryCode {
  pending,
  sent,
  sentFlood,
  relayed,
  delivered,
  failed,
  received,
}

/// The app's SQLite database.
///
/// Schema changes bump [schemaVersion] and add a step to [migration]; each
/// version's schema is saved in `drift_schemas/` and tested.
@DriftDatabase(
  tables: [
    Radios,
    Nodes,
    Channels,
    Messages,
    VerifiedKeys,
    TelemetryReadings,
    ConversationStates,
    Preferences,
  ],
)
class MeshDatabase extends _$MeshDatabase {
  MeshDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        // v2: count send attempts per message.
        await m.addColumn(schema.messages, schema.messages.attempts);
      },
      from2To3: (m, schema) async {
        // v3: MeshCore route bytes on nodes, for drawing paths on the map.
        await m.addColumn(schema.nodes, schema.nodes.routeHex);
      },
      from3To4: (m, schema) async {
        // v4: public keys, verified keys and authenticated messages.
        await m.addColumn(schema.nodes, schema.nodes.publicKeyHex);
        await m.addColumn(schema.messages, schema.messages.authenticated);
        await m.createTable(schema.verifiedKeys);
      },
      from4To5: (m, schema) async {
        // v5: telemetry history.
        await m.createTable(schema.telemetryReadings);
        await m.createIndex(schema.telemetryByNode);
      },
      from5To6: (m, schema) async {
        // v6: read state, mutes and preferences. Everything already stored
        // counts as read, so an upgrade doesn't show old messages as new.
        await m.createTable(schema.conversationStates);
        await m.createTable(schema.preferences);
        await customStatement(
          'INSERT INTO conversation_states (conversation, last_read_id) '
          'SELECT conversation, MAX(id) FROM messages GROUP BY conversation',
        );
      },
    ),
  );
}
