import 'package:drift/drift.dart';

import '../mesh/model.dart';
import '../radio/radio_link.dart';

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

  /// Identifies a received message so a repeat isn't stored twice.
  TextColumn get dedupeKey => text().nullable().unique()();
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
@DriftDatabase(tables: [Radios, Nodes, Channels, Messages])
class MeshDatabase extends _$MeshDatabase {
  MeshDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Version 1 is the first schema; later versions add steps here.
    },
  );
}
