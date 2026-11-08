// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RadiosTable extends Radios with TableInfo<$RadiosTable, RadioRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RadiosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RadioProtocol, String> protocol =
      GeneratedColumn<String>(
        'protocol',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RadioProtocol>($RadiosTable.$converterprotocol);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _selfKeyMeta = const VerificationMeta(
    'selfKey',
  );
  @override
  late final GeneratedColumn<String> selfKey = GeneratedColumn<String>(
    'self_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firmwareMeta = const VerificationMeta(
    'firmware',
  );
  @override
  late final GeneratedColumn<String> firmware = GeneratedColumn<String>(
    'firmware',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _maxChannelsMeta = const VerificationMeta(
    'maxChannels',
  );
  @override
  late final GeneratedColumn<int> maxChannels = GeneratedColumn<int>(
    'max_channels',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastConnectedMeta = const VerificationMeta(
    'lastConnected',
  );
  @override
  late final GeneratedColumn<DateTime> lastConnected =
      GeneratedColumn<DateTime>(
        'last_connected',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    protocol,
    name,
    selfKey,
    firmware,
    model,
    maxChannels,
    latitude,
    longitude,
    lastConnected,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'radios';
  @override
  VerificationContext validateIntegrity(
    Insertable<RadioRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('self_key')) {
      context.handle(
        _selfKeyMeta,
        selfKey.isAcceptableOrUnknown(data['self_key']!, _selfKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_selfKeyMeta);
    }
    if (data.containsKey('firmware')) {
      context.handle(
        _firmwareMeta,
        firmware.isAcceptableOrUnknown(data['firmware']!, _firmwareMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('max_channels')) {
      context.handle(
        _maxChannelsMeta,
        maxChannels.isAcceptableOrUnknown(
          data['max_channels']!,
          _maxChannelsMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('last_connected')) {
      context.handle(
        _lastConnectedMeta,
        lastConnected.isAcceptableOrUnknown(
          data['last_connected']!,
          _lastConnectedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RadioRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RadioRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      protocol: $RadiosTable.$converterprotocol.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}protocol'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      selfKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}self_key'],
      )!,
      firmware: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}firmware'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      maxChannels: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_channels'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      lastConnected: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_connected'],
      ),
    );
  }

  @override
  $RadiosTable createAlias(String alias) {
    return $RadiosTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RadioProtocol, String, String> $converterprotocol =
      const EnumNameConverter<RadioProtocol>(RadioProtocol.values);
}

class RadioRow extends DataClass implements Insertable<RadioRow> {
  /// `RadioId.toString()`, e.g. `meshtastic:!a1b2c3d4`.
  final String id;
  final RadioProtocol protocol;
  final String name;

  /// `NodeKey.toString()` of the radio's own node.
  final String selfKey;
  final String firmware;
  final String model;
  final int? maxChannels;
  final double? latitude;
  final double? longitude;
  final DateTime? lastConnected;
  const RadioRow({
    required this.id,
    required this.protocol,
    required this.name,
    required this.selfKey,
    required this.firmware,
    required this.model,
    this.maxChannels,
    this.latitude,
    this.longitude,
    this.lastConnected,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['protocol'] = Variable<String>(
        $RadiosTable.$converterprotocol.toSql(protocol),
      );
    }
    map['name'] = Variable<String>(name);
    map['self_key'] = Variable<String>(selfKey);
    map['firmware'] = Variable<String>(firmware);
    map['model'] = Variable<String>(model);
    if (!nullToAbsent || maxChannels != null) {
      map['max_channels'] = Variable<int>(maxChannels);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || lastConnected != null) {
      map['last_connected'] = Variable<DateTime>(lastConnected);
    }
    return map;
  }

  RadiosCompanion toCompanion(bool nullToAbsent) {
    return RadiosCompanion(
      id: Value(id),
      protocol: Value(protocol),
      name: Value(name),
      selfKey: Value(selfKey),
      firmware: Value(firmware),
      model: Value(model),
      maxChannels: maxChannels == null && nullToAbsent
          ? const Value.absent()
          : Value(maxChannels),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      lastConnected: lastConnected == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnected),
    );
  }

  factory RadioRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RadioRow(
      id: serializer.fromJson<String>(json['id']),
      protocol: $RadiosTable.$converterprotocol.fromJson(
        serializer.fromJson<String>(json['protocol']),
      ),
      name: serializer.fromJson<String>(json['name']),
      selfKey: serializer.fromJson<String>(json['selfKey']),
      firmware: serializer.fromJson<String>(json['firmware']),
      model: serializer.fromJson<String>(json['model']),
      maxChannels: serializer.fromJson<int?>(json['maxChannels']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      lastConnected: serializer.fromJson<DateTime?>(json['lastConnected']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'protocol': serializer.toJson<String>(
        $RadiosTable.$converterprotocol.toJson(protocol),
      ),
      'name': serializer.toJson<String>(name),
      'selfKey': serializer.toJson<String>(selfKey),
      'firmware': serializer.toJson<String>(firmware),
      'model': serializer.toJson<String>(model),
      'maxChannels': serializer.toJson<int?>(maxChannels),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'lastConnected': serializer.toJson<DateTime?>(lastConnected),
    };
  }

  RadioRow copyWith({
    String? id,
    RadioProtocol? protocol,
    String? name,
    String? selfKey,
    String? firmware,
    String? model,
    Value<int?> maxChannels = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<DateTime?> lastConnected = const Value.absent(),
  }) => RadioRow(
    id: id ?? this.id,
    protocol: protocol ?? this.protocol,
    name: name ?? this.name,
    selfKey: selfKey ?? this.selfKey,
    firmware: firmware ?? this.firmware,
    model: model ?? this.model,
    maxChannels: maxChannels.present ? maxChannels.value : this.maxChannels,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    lastConnected: lastConnected.present
        ? lastConnected.value
        : this.lastConnected,
  );
  RadioRow copyWithCompanion(RadiosCompanion data) {
    return RadioRow(
      id: data.id.present ? data.id.value : this.id,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      name: data.name.present ? data.name.value : this.name,
      selfKey: data.selfKey.present ? data.selfKey.value : this.selfKey,
      firmware: data.firmware.present ? data.firmware.value : this.firmware,
      model: data.model.present ? data.model.value : this.model,
      maxChannels: data.maxChannels.present
          ? data.maxChannels.value
          : this.maxChannels,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      lastConnected: data.lastConnected.present
          ? data.lastConnected.value
          : this.lastConnected,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RadioRow(')
          ..write('id: $id, ')
          ..write('protocol: $protocol, ')
          ..write('name: $name, ')
          ..write('selfKey: $selfKey, ')
          ..write('firmware: $firmware, ')
          ..write('model: $model, ')
          ..write('maxChannels: $maxChannels, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('lastConnected: $lastConnected')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    protocol,
    name,
    selfKey,
    firmware,
    model,
    maxChannels,
    latitude,
    longitude,
    lastConnected,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RadioRow &&
          other.id == this.id &&
          other.protocol == this.protocol &&
          other.name == this.name &&
          other.selfKey == this.selfKey &&
          other.firmware == this.firmware &&
          other.model == this.model &&
          other.maxChannels == this.maxChannels &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.lastConnected == this.lastConnected);
}

class RadiosCompanion extends UpdateCompanion<RadioRow> {
  final Value<String> id;
  final Value<RadioProtocol> protocol;
  final Value<String> name;
  final Value<String> selfKey;
  final Value<String> firmware;
  final Value<String> model;
  final Value<int?> maxChannels;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<DateTime?> lastConnected;
  final Value<int> rowid;
  const RadiosCompanion({
    this.id = const Value.absent(),
    this.protocol = const Value.absent(),
    this.name = const Value.absent(),
    this.selfKey = const Value.absent(),
    this.firmware = const Value.absent(),
    this.model = const Value.absent(),
    this.maxChannels = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.lastConnected = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RadiosCompanion.insert({
    required String id,
    required RadioProtocol protocol,
    required String name,
    required String selfKey,
    this.firmware = const Value.absent(),
    this.model = const Value.absent(),
    this.maxChannels = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.lastConnected = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       protocol = Value(protocol),
       name = Value(name),
       selfKey = Value(selfKey);
  static Insertable<RadioRow> custom({
    Expression<String>? id,
    Expression<String>? protocol,
    Expression<String>? name,
    Expression<String>? selfKey,
    Expression<String>? firmware,
    Expression<String>? model,
    Expression<int>? maxChannels,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<DateTime>? lastConnected,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (protocol != null) 'protocol': protocol,
      if (name != null) 'name': name,
      if (selfKey != null) 'self_key': selfKey,
      if (firmware != null) 'firmware': firmware,
      if (model != null) 'model': model,
      if (maxChannels != null) 'max_channels': maxChannels,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (lastConnected != null) 'last_connected': lastConnected,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RadiosCompanion copyWith({
    Value<String>? id,
    Value<RadioProtocol>? protocol,
    Value<String>? name,
    Value<String>? selfKey,
    Value<String>? firmware,
    Value<String>? model,
    Value<int?>? maxChannels,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<DateTime?>? lastConnected,
    Value<int>? rowid,
  }) {
    return RadiosCompanion(
      id: id ?? this.id,
      protocol: protocol ?? this.protocol,
      name: name ?? this.name,
      selfKey: selfKey ?? this.selfKey,
      firmware: firmware ?? this.firmware,
      model: model ?? this.model,
      maxChannels: maxChannels ?? this.maxChannels,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      lastConnected: lastConnected ?? this.lastConnected,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(
        $RadiosTable.$converterprotocol.toSql(protocol.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (selfKey.present) {
      map['self_key'] = Variable<String>(selfKey.value);
    }
    if (firmware.present) {
      map['firmware'] = Variable<String>(firmware.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (maxChannels.present) {
      map['max_channels'] = Variable<int>(maxChannels.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (lastConnected.present) {
      map['last_connected'] = Variable<DateTime>(lastConnected.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RadiosCompanion(')
          ..write('id: $id, ')
          ..write('protocol: $protocol, ')
          ..write('name: $name, ')
          ..write('selfKey: $selfKey, ')
          ..write('firmware: $firmware, ')
          ..write('model: $model, ')
          ..write('maxChannels: $maxChannels, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('lastConnected: $lastConnected, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NodesTable extends Nodes with TableInfo<$NodesTable, NodeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _radioIdMeta = const VerificationMeta(
    'radioId',
  );
  @override
  late final GeneratedColumn<String> radioId = GeneratedColumn<String>(
    'radio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeKeyMeta = const VerificationMeta(
    'nodeKey',
  );
  @override
  late final GeneratedColumn<String> nodeKey = GeneratedColumn<String>(
    'node_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shortNameMeta = const VerificationMeta(
    'shortName',
  );
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
    'short_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<NodeKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<NodeKind>($NodesTable.$converterkind);
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _altitudeMeta = const VerificationMeta(
    'altitude',
  );
  @override
  late final GeneratedColumn<int> altitude = GeneratedColumn<int>(
    'altitude',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastHeardMeta = const VerificationMeta(
    'lastHeard',
  );
  @override
  late final GeneratedColumn<DateTime> lastHeard = GeneratedColumn<DateTime>(
    'last_heard',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hopsMeta = const VerificationMeta('hops');
  @override
  late final GeneratedColumn<int> hops = GeneratedColumn<int>(
    'hops',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snrMeta = const VerificationMeta('snr');
  @override
  late final GeneratedColumn<double> snr = GeneratedColumn<double>(
    'snr',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
  @override
  late final GeneratedColumn<int> rssi = GeneratedColumn<int>(
    'rssi',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RouteKind, String> route =
      GeneratedColumn<String>(
        'route',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RouteKind>($NodesTable.$converterroute);
  static const VerificationMeta _viaMqttMeta = const VerificationMeta(
    'viaMqtt',
  );
  @override
  late final GeneratedColumn<bool> viaMqtt = GeneratedColumn<bool>(
    'via_mqtt',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("via_mqtt" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _batteryMeta = const VerificationMeta(
    'battery',
  );
  @override
  late final GeneratedColumn<int> battery = GeneratedColumn<int>(
    'battery',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canMessageMeta = const VerificationMeta(
    'canMessage',
  );
  @override
  late final GeneratedColumn<bool> canMessage = GeneratedColumn<bool>(
    'can_message',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_message" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _routeHexMeta = const VerificationMeta(
    'routeHex',
  );
  @override
  late final GeneratedColumn<String> routeHex = GeneratedColumn<String>(
    'route_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyHexMeta = const VerificationMeta(
    'publicKeyHex',
  );
  @override
  late final GeneratedColumn<String> publicKeyHex = GeneratedColumn<String>(
    'public_key_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    radioId,
    nodeKey,
    name,
    shortName,
    kind,
    latitude,
    longitude,
    altitude,
    lastHeard,
    hops,
    snr,
    rssi,
    route,
    viaMqtt,
    favorite,
    battery,
    canMessage,
    routeHex,
    publicKeyHex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NodeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('radio_id')) {
      context.handle(
        _radioIdMeta,
        radioId.isAcceptableOrUnknown(data['radio_id']!, _radioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_radioIdMeta);
    }
    if (data.containsKey('node_key')) {
      context.handle(
        _nodeKeyMeta,
        nodeKey.isAcceptableOrUnknown(data['node_key']!, _nodeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeKeyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('short_name')) {
      context.handle(
        _shortNameMeta,
        shortName.isAcceptableOrUnknown(data['short_name']!, _shortNameMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('altitude')) {
      context.handle(
        _altitudeMeta,
        altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta),
      );
    }
    if (data.containsKey('last_heard')) {
      context.handle(
        _lastHeardMeta,
        lastHeard.isAcceptableOrUnknown(data['last_heard']!, _lastHeardMeta),
      );
    }
    if (data.containsKey('hops')) {
      context.handle(
        _hopsMeta,
        hops.isAcceptableOrUnknown(data['hops']!, _hopsMeta),
      );
    }
    if (data.containsKey('snr')) {
      context.handle(
        _snrMeta,
        snr.isAcceptableOrUnknown(data['snr']!, _snrMeta),
      );
    }
    if (data.containsKey('rssi')) {
      context.handle(
        _rssiMeta,
        rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta),
      );
    }
    if (data.containsKey('via_mqtt')) {
      context.handle(
        _viaMqttMeta,
        viaMqtt.isAcceptableOrUnknown(data['via_mqtt']!, _viaMqttMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('battery')) {
      context.handle(
        _batteryMeta,
        battery.isAcceptableOrUnknown(data['battery']!, _batteryMeta),
      );
    }
    if (data.containsKey('can_message')) {
      context.handle(
        _canMessageMeta,
        canMessage.isAcceptableOrUnknown(data['can_message']!, _canMessageMeta),
      );
    }
    if (data.containsKey('route_hex')) {
      context.handle(
        _routeHexMeta,
        routeHex.isAcceptableOrUnknown(data['route_hex']!, _routeHexMeta),
      );
    }
    if (data.containsKey('public_key_hex')) {
      context.handle(
        _publicKeyHexMeta,
        publicKeyHex.isAcceptableOrUnknown(
          data['public_key_hex']!,
          _publicKeyHexMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {radioId, nodeKey};
  @override
  NodeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NodeRow(
      radioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}radio_id'],
      )!,
      nodeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      shortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}short_name'],
      )!,
      kind: $NodesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      altitude: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}altitude'],
      ),
      lastHeard: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_heard'],
      ),
      hops: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hops'],
      ),
      snr: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}snr'],
      ),
      rssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi'],
      ),
      route: $NodesTable.$converterroute.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}route'],
        )!,
      ),
      viaMqtt: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}via_mqtt'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      battery: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery'],
      ),
      canMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_message'],
      )!,
      routeHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_hex'],
      ),
      publicKeyHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key_hex'],
      ),
    );
  }

  @override
  $NodesTable createAlias(String alias) {
    return $NodesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<NodeKind, String, String> $converterkind =
      const EnumNameConverter<NodeKind>(NodeKind.values);
  static JsonTypeConverter2<RouteKind, String, String> $converterroute =
      const EnumNameConverter<RouteKind>(RouteKind.values);
}

class NodeRow extends DataClass implements Insertable<NodeRow> {
  final String radioId;

  /// `NodeKey.toString()`.
  final String nodeKey;
  final String name;
  final String shortName;
  final NodeKind kind;
  final double? latitude;
  final double? longitude;
  final int? altitude;
  final DateTime? lastHeard;
  final int? hops;
  final double? snr;
  final int? rssi;
  final RouteKind route;
  final bool viaMqtt;
  final bool favorite;
  final int? battery;
  final bool canMessage;

  /// MeshCore out-path as hex (repeater hash prefixes, in order). Schema v3.
  final String? routeHex;

  /// The node's public key as hex (MeshCore: its identity; Meshtastic: the
  /// key it advertises for encrypted direct messages). Schema v4.
  final String? publicKeyHex;
  const NodeRow({
    required this.radioId,
    required this.nodeKey,
    required this.name,
    required this.shortName,
    required this.kind,
    this.latitude,
    this.longitude,
    this.altitude,
    this.lastHeard,
    this.hops,
    this.snr,
    this.rssi,
    required this.route,
    required this.viaMqtt,
    required this.favorite,
    this.battery,
    required this.canMessage,
    this.routeHex,
    this.publicKeyHex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['radio_id'] = Variable<String>(radioId);
    map['node_key'] = Variable<String>(nodeKey);
    map['name'] = Variable<String>(name);
    map['short_name'] = Variable<String>(shortName);
    {
      map['kind'] = Variable<String>($NodesTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<int>(altitude);
    }
    if (!nullToAbsent || lastHeard != null) {
      map['last_heard'] = Variable<DateTime>(lastHeard);
    }
    if (!nullToAbsent || hops != null) {
      map['hops'] = Variable<int>(hops);
    }
    if (!nullToAbsent || snr != null) {
      map['snr'] = Variable<double>(snr);
    }
    if (!nullToAbsent || rssi != null) {
      map['rssi'] = Variable<int>(rssi);
    }
    {
      map['route'] = Variable<String>($NodesTable.$converterroute.toSql(route));
    }
    map['via_mqtt'] = Variable<bool>(viaMqtt);
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || battery != null) {
      map['battery'] = Variable<int>(battery);
    }
    map['can_message'] = Variable<bool>(canMessage);
    if (!nullToAbsent || routeHex != null) {
      map['route_hex'] = Variable<String>(routeHex);
    }
    if (!nullToAbsent || publicKeyHex != null) {
      map['public_key_hex'] = Variable<String>(publicKeyHex);
    }
    return map;
  }

  NodesCompanion toCompanion(bool nullToAbsent) {
    return NodesCompanion(
      radioId: Value(radioId),
      nodeKey: Value(nodeKey),
      name: Value(name),
      shortName: Value(shortName),
      kind: Value(kind),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      lastHeard: lastHeard == null && nullToAbsent
          ? const Value.absent()
          : Value(lastHeard),
      hops: hops == null && nullToAbsent ? const Value.absent() : Value(hops),
      snr: snr == null && nullToAbsent ? const Value.absent() : Value(snr),
      rssi: rssi == null && nullToAbsent ? const Value.absent() : Value(rssi),
      route: Value(route),
      viaMqtt: Value(viaMqtt),
      favorite: Value(favorite),
      battery: battery == null && nullToAbsent
          ? const Value.absent()
          : Value(battery),
      canMessage: Value(canMessage),
      routeHex: routeHex == null && nullToAbsent
          ? const Value.absent()
          : Value(routeHex),
      publicKeyHex: publicKeyHex == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKeyHex),
    );
  }

  factory NodeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NodeRow(
      radioId: serializer.fromJson<String>(json['radioId']),
      nodeKey: serializer.fromJson<String>(json['nodeKey']),
      name: serializer.fromJson<String>(json['name']),
      shortName: serializer.fromJson<String>(json['shortName']),
      kind: $NodesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      altitude: serializer.fromJson<int?>(json['altitude']),
      lastHeard: serializer.fromJson<DateTime?>(json['lastHeard']),
      hops: serializer.fromJson<int?>(json['hops']),
      snr: serializer.fromJson<double?>(json['snr']),
      rssi: serializer.fromJson<int?>(json['rssi']),
      route: $NodesTable.$converterroute.fromJson(
        serializer.fromJson<String>(json['route']),
      ),
      viaMqtt: serializer.fromJson<bool>(json['viaMqtt']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      battery: serializer.fromJson<int?>(json['battery']),
      canMessage: serializer.fromJson<bool>(json['canMessage']),
      routeHex: serializer.fromJson<String?>(json['routeHex']),
      publicKeyHex: serializer.fromJson<String?>(json['publicKeyHex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'radioId': serializer.toJson<String>(radioId),
      'nodeKey': serializer.toJson<String>(nodeKey),
      'name': serializer.toJson<String>(name),
      'shortName': serializer.toJson<String>(shortName),
      'kind': serializer.toJson<String>(
        $NodesTable.$converterkind.toJson(kind),
      ),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'altitude': serializer.toJson<int?>(altitude),
      'lastHeard': serializer.toJson<DateTime?>(lastHeard),
      'hops': serializer.toJson<int?>(hops),
      'snr': serializer.toJson<double?>(snr),
      'rssi': serializer.toJson<int?>(rssi),
      'route': serializer.toJson<String>(
        $NodesTable.$converterroute.toJson(route),
      ),
      'viaMqtt': serializer.toJson<bool>(viaMqtt),
      'favorite': serializer.toJson<bool>(favorite),
      'battery': serializer.toJson<int?>(battery),
      'canMessage': serializer.toJson<bool>(canMessage),
      'routeHex': serializer.toJson<String?>(routeHex),
      'publicKeyHex': serializer.toJson<String?>(publicKeyHex),
    };
  }

  NodeRow copyWith({
    String? radioId,
    String? nodeKey,
    String? name,
    String? shortName,
    NodeKind? kind,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<int?> altitude = const Value.absent(),
    Value<DateTime?> lastHeard = const Value.absent(),
    Value<int?> hops = const Value.absent(),
    Value<double?> snr = const Value.absent(),
    Value<int?> rssi = const Value.absent(),
    RouteKind? route,
    bool? viaMqtt,
    bool? favorite,
    Value<int?> battery = const Value.absent(),
    bool? canMessage,
    Value<String?> routeHex = const Value.absent(),
    Value<String?> publicKeyHex = const Value.absent(),
  }) => NodeRow(
    radioId: radioId ?? this.radioId,
    nodeKey: nodeKey ?? this.nodeKey,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    kind: kind ?? this.kind,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    altitude: altitude.present ? altitude.value : this.altitude,
    lastHeard: lastHeard.present ? lastHeard.value : this.lastHeard,
    hops: hops.present ? hops.value : this.hops,
    snr: snr.present ? snr.value : this.snr,
    rssi: rssi.present ? rssi.value : this.rssi,
    route: route ?? this.route,
    viaMqtt: viaMqtt ?? this.viaMqtt,
    favorite: favorite ?? this.favorite,
    battery: battery.present ? battery.value : this.battery,
    canMessage: canMessage ?? this.canMessage,
    routeHex: routeHex.present ? routeHex.value : this.routeHex,
    publicKeyHex: publicKeyHex.present ? publicKeyHex.value : this.publicKeyHex,
  );
  NodeRow copyWithCompanion(NodesCompanion data) {
    return NodeRow(
      radioId: data.radioId.present ? data.radioId.value : this.radioId,
      nodeKey: data.nodeKey.present ? data.nodeKey.value : this.nodeKey,
      name: data.name.present ? data.name.value : this.name,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      kind: data.kind.present ? data.kind.value : this.kind,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      lastHeard: data.lastHeard.present ? data.lastHeard.value : this.lastHeard,
      hops: data.hops.present ? data.hops.value : this.hops,
      snr: data.snr.present ? data.snr.value : this.snr,
      rssi: data.rssi.present ? data.rssi.value : this.rssi,
      route: data.route.present ? data.route.value : this.route,
      viaMqtt: data.viaMqtt.present ? data.viaMqtt.value : this.viaMqtt,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      battery: data.battery.present ? data.battery.value : this.battery,
      canMessage: data.canMessage.present
          ? data.canMessage.value
          : this.canMessage,
      routeHex: data.routeHex.present ? data.routeHex.value : this.routeHex,
      publicKeyHex: data.publicKeyHex.present
          ? data.publicKeyHex.value
          : this.publicKeyHex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NodeRow(')
          ..write('radioId: $radioId, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('kind: $kind, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('lastHeard: $lastHeard, ')
          ..write('hops: $hops, ')
          ..write('snr: $snr, ')
          ..write('rssi: $rssi, ')
          ..write('route: $route, ')
          ..write('viaMqtt: $viaMqtt, ')
          ..write('favorite: $favorite, ')
          ..write('battery: $battery, ')
          ..write('canMessage: $canMessage, ')
          ..write('routeHex: $routeHex, ')
          ..write('publicKeyHex: $publicKeyHex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    radioId,
    nodeKey,
    name,
    shortName,
    kind,
    latitude,
    longitude,
    altitude,
    lastHeard,
    hops,
    snr,
    rssi,
    route,
    viaMqtt,
    favorite,
    battery,
    canMessage,
    routeHex,
    publicKeyHex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeRow &&
          other.radioId == this.radioId &&
          other.nodeKey == this.nodeKey &&
          other.name == this.name &&
          other.shortName == this.shortName &&
          other.kind == this.kind &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitude == this.altitude &&
          other.lastHeard == this.lastHeard &&
          other.hops == this.hops &&
          other.snr == this.snr &&
          other.rssi == this.rssi &&
          other.route == this.route &&
          other.viaMqtt == this.viaMqtt &&
          other.favorite == this.favorite &&
          other.battery == this.battery &&
          other.canMessage == this.canMessage &&
          other.routeHex == this.routeHex &&
          other.publicKeyHex == this.publicKeyHex);
}

class NodesCompanion extends UpdateCompanion<NodeRow> {
  final Value<String> radioId;
  final Value<String> nodeKey;
  final Value<String> name;
  final Value<String> shortName;
  final Value<NodeKind> kind;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<int?> altitude;
  final Value<DateTime?> lastHeard;
  final Value<int?> hops;
  final Value<double?> snr;
  final Value<int?> rssi;
  final Value<RouteKind> route;
  final Value<bool> viaMqtt;
  final Value<bool> favorite;
  final Value<int?> battery;
  final Value<bool> canMessage;
  final Value<String?> routeHex;
  final Value<String?> publicKeyHex;
  final Value<int> rowid;
  const NodesCompanion({
    this.radioId = const Value.absent(),
    this.nodeKey = const Value.absent(),
    this.name = const Value.absent(),
    this.shortName = const Value.absent(),
    this.kind = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.lastHeard = const Value.absent(),
    this.hops = const Value.absent(),
    this.snr = const Value.absent(),
    this.rssi = const Value.absent(),
    this.route = const Value.absent(),
    this.viaMqtt = const Value.absent(),
    this.favorite = const Value.absent(),
    this.battery = const Value.absent(),
    this.canMessage = const Value.absent(),
    this.routeHex = const Value.absent(),
    this.publicKeyHex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NodesCompanion.insert({
    required String radioId,
    required String nodeKey,
    required String name,
    this.shortName = const Value.absent(),
    required NodeKind kind,
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.lastHeard = const Value.absent(),
    this.hops = const Value.absent(),
    this.snr = const Value.absent(),
    this.rssi = const Value.absent(),
    required RouteKind route,
    this.viaMqtt = const Value.absent(),
    this.favorite = const Value.absent(),
    this.battery = const Value.absent(),
    this.canMessage = const Value.absent(),
    this.routeHex = const Value.absent(),
    this.publicKeyHex = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : radioId = Value(radioId),
       nodeKey = Value(nodeKey),
       name = Value(name),
       kind = Value(kind),
       route = Value(route);
  static Insertable<NodeRow> custom({
    Expression<String>? radioId,
    Expression<String>? nodeKey,
    Expression<String>? name,
    Expression<String>? shortName,
    Expression<String>? kind,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? altitude,
    Expression<DateTime>? lastHeard,
    Expression<int>? hops,
    Expression<double>? snr,
    Expression<int>? rssi,
    Expression<String>? route,
    Expression<bool>? viaMqtt,
    Expression<bool>? favorite,
    Expression<int>? battery,
    Expression<bool>? canMessage,
    Expression<String>? routeHex,
    Expression<String>? publicKeyHex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (radioId != null) 'radio_id': radioId,
      if (nodeKey != null) 'node_key': nodeKey,
      if (name != null) 'name': name,
      if (shortName != null) 'short_name': shortName,
      if (kind != null) 'kind': kind,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (lastHeard != null) 'last_heard': lastHeard,
      if (hops != null) 'hops': hops,
      if (snr != null) 'snr': snr,
      if (rssi != null) 'rssi': rssi,
      if (route != null) 'route': route,
      if (viaMqtt != null) 'via_mqtt': viaMqtt,
      if (favorite != null) 'favorite': favorite,
      if (battery != null) 'battery': battery,
      if (canMessage != null) 'can_message': canMessage,
      if (routeHex != null) 'route_hex': routeHex,
      if (publicKeyHex != null) 'public_key_hex': publicKeyHex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NodesCompanion copyWith({
    Value<String>? radioId,
    Value<String>? nodeKey,
    Value<String>? name,
    Value<String>? shortName,
    Value<NodeKind>? kind,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<int?>? altitude,
    Value<DateTime?>? lastHeard,
    Value<int?>? hops,
    Value<double?>? snr,
    Value<int?>? rssi,
    Value<RouteKind>? route,
    Value<bool>? viaMqtt,
    Value<bool>? favorite,
    Value<int?>? battery,
    Value<bool>? canMessage,
    Value<String?>? routeHex,
    Value<String?>? publicKeyHex,
    Value<int>? rowid,
  }) {
    return NodesCompanion(
      radioId: radioId ?? this.radioId,
      nodeKey: nodeKey ?? this.nodeKey,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      kind: kind ?? this.kind,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      lastHeard: lastHeard ?? this.lastHeard,
      hops: hops ?? this.hops,
      snr: snr ?? this.snr,
      rssi: rssi ?? this.rssi,
      route: route ?? this.route,
      viaMqtt: viaMqtt ?? this.viaMqtt,
      favorite: favorite ?? this.favorite,
      battery: battery ?? this.battery,
      canMessage: canMessage ?? this.canMessage,
      routeHex: routeHex ?? this.routeHex,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (radioId.present) {
      map['radio_id'] = Variable<String>(radioId.value);
    }
    if (nodeKey.present) {
      map['node_key'] = Variable<String>(nodeKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $NodesTable.$converterkind.toSql(kind.value),
      );
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<int>(altitude.value);
    }
    if (lastHeard.present) {
      map['last_heard'] = Variable<DateTime>(lastHeard.value);
    }
    if (hops.present) {
      map['hops'] = Variable<int>(hops.value);
    }
    if (snr.present) {
      map['snr'] = Variable<double>(snr.value);
    }
    if (rssi.present) {
      map['rssi'] = Variable<int>(rssi.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(
        $NodesTable.$converterroute.toSql(route.value),
      );
    }
    if (viaMqtt.present) {
      map['via_mqtt'] = Variable<bool>(viaMqtt.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (battery.present) {
      map['battery'] = Variable<int>(battery.value);
    }
    if (canMessage.present) {
      map['can_message'] = Variable<bool>(canMessage.value);
    }
    if (routeHex.present) {
      map['route_hex'] = Variable<String>(routeHex.value);
    }
    if (publicKeyHex.present) {
      map['public_key_hex'] = Variable<String>(publicKeyHex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodesCompanion(')
          ..write('radioId: $radioId, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('name: $name, ')
          ..write('shortName: $shortName, ')
          ..write('kind: $kind, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('lastHeard: $lastHeard, ')
          ..write('hops: $hops, ')
          ..write('snr: $snr, ')
          ..write('rssi: $rssi, ')
          ..write('route: $route, ')
          ..write('viaMqtt: $viaMqtt, ')
          ..write('favorite: $favorite, ')
          ..write('battery: $battery, ')
          ..write('canMessage: $canMessage, ')
          ..write('routeHex: $routeHex, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels
    with TableInfo<$ChannelsTable, ChannelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _radioIdMeta = const VerificationMeta(
    'radioId',
  );
  @override
  late final GeneratedColumn<String> radioId = GeneratedColumn<String>(
    'radio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChannelKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ChannelKind>($ChannelsTable.$converterkind);
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [radioId, slot, name, kind, isPrimary];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChannelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('radio_id')) {
      context.handle(
        _radioIdMeta,
        radioId.isAcceptableOrUnknown(data['radio_id']!, _radioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_radioIdMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {radioId, slot};
  @override
  ChannelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelRow(
      radioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}radio_id'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: $ChannelsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChannelKind, String, String> $converterkind =
      const EnumNameConverter<ChannelKind>(ChannelKind.values);
}

class ChannelRow extends DataClass implements Insertable<ChannelRow> {
  final String radioId;
  final int slot;
  final String name;
  final ChannelKind kind;
  final bool isPrimary;
  const ChannelRow({
    required this.radioId,
    required this.slot,
    required this.name,
    required this.kind,
    required this.isPrimary,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['radio_id'] = Variable<String>(radioId);
    map['slot'] = Variable<int>(slot);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<String>($ChannelsTable.$converterkind.toSql(kind));
    }
    map['is_primary'] = Variable<bool>(isPrimary);
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      radioId: Value(radioId),
      slot: Value(slot),
      name: Value(name),
      kind: Value(kind),
      isPrimary: Value(isPrimary),
    );
  }

  factory ChannelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelRow(
      radioId: serializer.fromJson<String>(json['radioId']),
      slot: serializer.fromJson<int>(json['slot']),
      name: serializer.fromJson<String>(json['name']),
      kind: $ChannelsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'radioId': serializer.toJson<String>(radioId),
      'slot': serializer.toJson<int>(slot),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(
        $ChannelsTable.$converterkind.toJson(kind),
      ),
      'isPrimary': serializer.toJson<bool>(isPrimary),
    };
  }

  ChannelRow copyWith({
    String? radioId,
    int? slot,
    String? name,
    ChannelKind? kind,
    bool? isPrimary,
  }) => ChannelRow(
    radioId: radioId ?? this.radioId,
    slot: slot ?? this.slot,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    isPrimary: isPrimary ?? this.isPrimary,
  );
  ChannelRow copyWithCompanion(ChannelsCompanion data) {
    return ChannelRow(
      radioId: data.radioId.present ? data.radioId.value : this.radioId,
      slot: data.slot.present ? data.slot.value : this.slot,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelRow(')
          ..write('radioId: $radioId, ')
          ..write('slot: $slot, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('isPrimary: $isPrimary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(radioId, slot, name, kind, isPrimary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelRow &&
          other.radioId == this.radioId &&
          other.slot == this.slot &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.isPrimary == this.isPrimary);
}

class ChannelsCompanion extends UpdateCompanion<ChannelRow> {
  final Value<String> radioId;
  final Value<int> slot;
  final Value<String> name;
  final Value<ChannelKind> kind;
  final Value<bool> isPrimary;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.radioId = const Value.absent(),
    this.slot = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required String radioId,
    required int slot,
    required String name,
    required ChannelKind kind,
    this.isPrimary = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : radioId = Value(radioId),
       slot = Value(slot),
       name = Value(name),
       kind = Value(kind);
  static Insertable<ChannelRow> custom({
    Expression<String>? radioId,
    Expression<int>? slot,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<bool>? isPrimary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (radioId != null) 'radio_id': radioId,
      if (slot != null) 'slot': slot,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<String>? radioId,
    Value<int>? slot,
    Value<String>? name,
    Value<ChannelKind>? kind,
    Value<bool>? isPrimary,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      radioId: radioId ?? this.radioId,
      slot: slot ?? this.slot,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      isPrimary: isPrimary ?? this.isPrimary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (radioId.present) {
      map['radio_id'] = Variable<String>(radioId.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $ChannelsTable.$converterkind.toSql(kind.value),
      );
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('radioId: $radioId, ')
          ..write('slot: $slot, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _radioIdMeta = const VerificationMeta(
    'radioId',
  );
  @override
  late final GeneratedColumn<String> radioId = GeneratedColumn<String>(
    'radio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationMeta = const VerificationMeta(
    'conversation',
  );
  @override
  late final GeneratedColumn<String> conversation = GeneratedColumn<String>(
    'conversation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outgoingMeta = const VerificationMeta(
    'outgoing',
  );
  @override
  late final GeneratedColumn<bool> outgoing = GeneratedColumn<bool>(
    'outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveryMeta = const VerificationMeta(
    'delivery',
  );
  @override
  late final GeneratedColumn<String> delivery = GeneratedColumn<String>(
    'delivery',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveryReasonMeta = const VerificationMeta(
    'deliveryReason',
  );
  @override
  late final GeneratedColumn<String> deliveryReason = GeneratedColumn<String>(
    'delivery_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roundTripMsMeta = const VerificationMeta(
    'roundTripMs',
  );
  @override
  late final GeneratedColumn<int> roundTripMs = GeneratedColumn<int>(
    'round_trip_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fromKeyMeta = const VerificationMeta(
    'fromKey',
  );
  @override
  late final GeneratedColumn<String> fromKey = GeneratedColumn<String>(
    'from_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hopsMeta = const VerificationMeta('hops');
  @override
  late final GeneratedColumn<int> hops = GeneratedColumn<int>(
    'hops',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snrMeta = const VerificationMeta('snr');
  @override
  late final GeneratedColumn<double> snr = GeneratedColumn<double>(
    'snr',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
  @override
  late final GeneratedColumn<int> rssi = GeneratedColumn<int>(
    'rssi',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RouteKind, String> route =
      GeneratedColumn<String>(
        'route',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RouteKind>($MessagesTable.$converterroute);
  static const VerificationMeta _viaMqttMeta = const VerificationMeta(
    'viaMqtt',
  );
  @override
  late final GeneratedColumn<bool> viaMqtt = GeneratedColumn<bool>(
    'via_mqtt',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("via_mqtt" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nativeIdMeta = const VerificationMeta(
    'nativeId',
  );
  @override
  late final GeneratedColumn<int> nativeId = GeneratedColumn<int>(
    'native_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToMeta = const VerificationMeta(
    'replyTo',
  );
  @override
  late final GeneratedColumn<int> replyTo = GeneratedColumn<int>(
    'reply_to',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isReactionMeta = const VerificationMeta(
    'isReaction',
  );
  @override
  late final GeneratedColumn<bool> isReaction = GeneratedColumn<bool>(
    'is_reaction',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_reaction" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _authenticatedMeta = const VerificationMeta(
    'authenticated',
  );
  @override
  late final GeneratedColumn<bool> authenticated = GeneratedColumn<bool>(
    'authenticated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("authenticated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dedupeKeyMeta = const VerificationMeta(
    'dedupeKey',
  );
  @override
  late final GeneratedColumn<String> dedupeKey = GeneratedColumn<String>(
    'dedupe_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    radioId,
    conversation,
    outgoing,
    body,
    sentAt,
    receivedAt,
    delivery,
    deliveryReason,
    roundTripMs,
    fromKey,
    senderName,
    hops,
    snr,
    rssi,
    route,
    viaMqtt,
    nativeId,
    replyTo,
    isReaction,
    attempts,
    authenticated,
    dedupeKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('radio_id')) {
      context.handle(
        _radioIdMeta,
        radioId.isAcceptableOrUnknown(data['radio_id']!, _radioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_radioIdMeta);
    }
    if (data.containsKey('conversation')) {
      context.handle(
        _conversationMeta,
        conversation.isAcceptableOrUnknown(
          data['conversation']!,
          _conversationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationMeta);
    }
    if (data.containsKey('outgoing')) {
      context.handle(
        _outgoingMeta,
        outgoing.isAcceptableOrUnknown(data['outgoing']!, _outgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_outgoingMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    } else if (isInserting) {
      context.missing(_sentAtMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('delivery')) {
      context.handle(
        _deliveryMeta,
        delivery.isAcceptableOrUnknown(data['delivery']!, _deliveryMeta),
      );
    } else if (isInserting) {
      context.missing(_deliveryMeta);
    }
    if (data.containsKey('delivery_reason')) {
      context.handle(
        _deliveryReasonMeta,
        deliveryReason.isAcceptableOrUnknown(
          data['delivery_reason']!,
          _deliveryReasonMeta,
        ),
      );
    }
    if (data.containsKey('round_trip_ms')) {
      context.handle(
        _roundTripMsMeta,
        roundTripMs.isAcceptableOrUnknown(
          data['round_trip_ms']!,
          _roundTripMsMeta,
        ),
      );
    }
    if (data.containsKey('from_key')) {
      context.handle(
        _fromKeyMeta,
        fromKey.isAcceptableOrUnknown(data['from_key']!, _fromKeyMeta),
      );
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    }
    if (data.containsKey('hops')) {
      context.handle(
        _hopsMeta,
        hops.isAcceptableOrUnknown(data['hops']!, _hopsMeta),
      );
    }
    if (data.containsKey('snr')) {
      context.handle(
        _snrMeta,
        snr.isAcceptableOrUnknown(data['snr']!, _snrMeta),
      );
    }
    if (data.containsKey('rssi')) {
      context.handle(
        _rssiMeta,
        rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta),
      );
    }
    if (data.containsKey('via_mqtt')) {
      context.handle(
        _viaMqttMeta,
        viaMqtt.isAcceptableOrUnknown(data['via_mqtt']!, _viaMqttMeta),
      );
    }
    if (data.containsKey('native_id')) {
      context.handle(
        _nativeIdMeta,
        nativeId.isAcceptableOrUnknown(data['native_id']!, _nativeIdMeta),
      );
    }
    if (data.containsKey('reply_to')) {
      context.handle(
        _replyToMeta,
        replyTo.isAcceptableOrUnknown(data['reply_to']!, _replyToMeta),
      );
    }
    if (data.containsKey('is_reaction')) {
      context.handle(
        _isReactionMeta,
        isReaction.isAcceptableOrUnknown(data['is_reaction']!, _isReactionMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('authenticated')) {
      context.handle(
        _authenticatedMeta,
        authenticated.isAcceptableOrUnknown(
          data['authenticated']!,
          _authenticatedMeta,
        ),
      );
    }
    if (data.containsKey('dedupe_key')) {
      context.handle(
        _dedupeKeyMeta,
        dedupeKey.isAcceptableOrUnknown(data['dedupe_key']!, _dedupeKeyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      radioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}radio_id'],
      )!,
      conversation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation'],
      )!,
      outgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}outgoing'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
      delivery: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery'],
      )!,
      deliveryReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_reason'],
      ),
      roundTripMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}round_trip_ms'],
      ),
      fromKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_key'],
      ),
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      ),
      hops: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hops'],
      ),
      snr: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}snr'],
      ),
      rssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi'],
      ),
      route: $MessagesTable.$converterroute.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}route'],
        )!,
      ),
      viaMqtt: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}via_mqtt'],
      )!,
      nativeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}native_id'],
      ),
      replyTo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reply_to'],
      ),
      isReaction: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_reaction'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      authenticated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}authenticated'],
      )!,
      dedupeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dedupe_key'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RouteKind, String, String> $converterroute =
      const EnumNameConverter<RouteKind>(RouteKind.values);
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final int id;
  final String radioId;

  /// `Conversation.key`.
  final String conversation;
  final bool outgoing;
  final String body;
  final DateTime sentAt;
  final DateTime receivedAt;

  /// One of [DeliveryCode] names.
  final String delivery;
  final String? deliveryReason;
  final int? roundTripMs;
  final String? fromKey;
  final String? senderName;
  final int? hops;
  final double? snr;
  final int? rssi;
  final RouteKind route;
  final bool viaMqtt;
  final int? nativeId;
  final int? replyTo;
  final bool isReaction;

  /// Times this outgoing message was sent (retries included). Schema v2.
  final int attempts;

  /// The sender is proven by encryption (MeshCore direct messages,
  /// Meshtastic public-key direct messages). Schema v4.
  final bool authenticated;

  /// Identifies a received message so a repeat isn't stored twice.
  final String? dedupeKey;
  const MessageRow({
    required this.id,
    required this.radioId,
    required this.conversation,
    required this.outgoing,
    required this.body,
    required this.sentAt,
    required this.receivedAt,
    required this.delivery,
    this.deliveryReason,
    this.roundTripMs,
    this.fromKey,
    this.senderName,
    this.hops,
    this.snr,
    this.rssi,
    required this.route,
    required this.viaMqtt,
    this.nativeId,
    this.replyTo,
    required this.isReaction,
    required this.attempts,
    required this.authenticated,
    this.dedupeKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['radio_id'] = Variable<String>(radioId);
    map['conversation'] = Variable<String>(conversation);
    map['outgoing'] = Variable<bool>(outgoing);
    map['body'] = Variable<String>(body);
    map['sent_at'] = Variable<DateTime>(sentAt);
    map['received_at'] = Variable<DateTime>(receivedAt);
    map['delivery'] = Variable<String>(delivery);
    if (!nullToAbsent || deliveryReason != null) {
      map['delivery_reason'] = Variable<String>(deliveryReason);
    }
    if (!nullToAbsent || roundTripMs != null) {
      map['round_trip_ms'] = Variable<int>(roundTripMs);
    }
    if (!nullToAbsent || fromKey != null) {
      map['from_key'] = Variable<String>(fromKey);
    }
    if (!nullToAbsent || senderName != null) {
      map['sender_name'] = Variable<String>(senderName);
    }
    if (!nullToAbsent || hops != null) {
      map['hops'] = Variable<int>(hops);
    }
    if (!nullToAbsent || snr != null) {
      map['snr'] = Variable<double>(snr);
    }
    if (!nullToAbsent || rssi != null) {
      map['rssi'] = Variable<int>(rssi);
    }
    {
      map['route'] = Variable<String>(
        $MessagesTable.$converterroute.toSql(route),
      );
    }
    map['via_mqtt'] = Variable<bool>(viaMqtt);
    if (!nullToAbsent || nativeId != null) {
      map['native_id'] = Variable<int>(nativeId);
    }
    if (!nullToAbsent || replyTo != null) {
      map['reply_to'] = Variable<int>(replyTo);
    }
    map['is_reaction'] = Variable<bool>(isReaction);
    map['attempts'] = Variable<int>(attempts);
    map['authenticated'] = Variable<bool>(authenticated);
    if (!nullToAbsent || dedupeKey != null) {
      map['dedupe_key'] = Variable<String>(dedupeKey);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      radioId: Value(radioId),
      conversation: Value(conversation),
      outgoing: Value(outgoing),
      body: Value(body),
      sentAt: Value(sentAt),
      receivedAt: Value(receivedAt),
      delivery: Value(delivery),
      deliveryReason: deliveryReason == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryReason),
      roundTripMs: roundTripMs == null && nullToAbsent
          ? const Value.absent()
          : Value(roundTripMs),
      fromKey: fromKey == null && nullToAbsent
          ? const Value.absent()
          : Value(fromKey),
      senderName: senderName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderName),
      hops: hops == null && nullToAbsent ? const Value.absent() : Value(hops),
      snr: snr == null && nullToAbsent ? const Value.absent() : Value(snr),
      rssi: rssi == null && nullToAbsent ? const Value.absent() : Value(rssi),
      route: Value(route),
      viaMqtt: Value(viaMqtt),
      nativeId: nativeId == null && nullToAbsent
          ? const Value.absent()
          : Value(nativeId),
      replyTo: replyTo == null && nullToAbsent
          ? const Value.absent()
          : Value(replyTo),
      isReaction: Value(isReaction),
      attempts: Value(attempts),
      authenticated: Value(authenticated),
      dedupeKey: dedupeKey == null && nullToAbsent
          ? const Value.absent()
          : Value(dedupeKey),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      id: serializer.fromJson<int>(json['id']),
      radioId: serializer.fromJson<String>(json['radioId']),
      conversation: serializer.fromJson<String>(json['conversation']),
      outgoing: serializer.fromJson<bool>(json['outgoing']),
      body: serializer.fromJson<String>(json['body']),
      sentAt: serializer.fromJson<DateTime>(json['sentAt']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      delivery: serializer.fromJson<String>(json['delivery']),
      deliveryReason: serializer.fromJson<String?>(json['deliveryReason']),
      roundTripMs: serializer.fromJson<int?>(json['roundTripMs']),
      fromKey: serializer.fromJson<String?>(json['fromKey']),
      senderName: serializer.fromJson<String?>(json['senderName']),
      hops: serializer.fromJson<int?>(json['hops']),
      snr: serializer.fromJson<double?>(json['snr']),
      rssi: serializer.fromJson<int?>(json['rssi']),
      route: $MessagesTable.$converterroute.fromJson(
        serializer.fromJson<String>(json['route']),
      ),
      viaMqtt: serializer.fromJson<bool>(json['viaMqtt']),
      nativeId: serializer.fromJson<int?>(json['nativeId']),
      replyTo: serializer.fromJson<int?>(json['replyTo']),
      isReaction: serializer.fromJson<bool>(json['isReaction']),
      attempts: serializer.fromJson<int>(json['attempts']),
      authenticated: serializer.fromJson<bool>(json['authenticated']),
      dedupeKey: serializer.fromJson<String?>(json['dedupeKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'radioId': serializer.toJson<String>(radioId),
      'conversation': serializer.toJson<String>(conversation),
      'outgoing': serializer.toJson<bool>(outgoing),
      'body': serializer.toJson<String>(body),
      'sentAt': serializer.toJson<DateTime>(sentAt),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'delivery': serializer.toJson<String>(delivery),
      'deliveryReason': serializer.toJson<String?>(deliveryReason),
      'roundTripMs': serializer.toJson<int?>(roundTripMs),
      'fromKey': serializer.toJson<String?>(fromKey),
      'senderName': serializer.toJson<String?>(senderName),
      'hops': serializer.toJson<int?>(hops),
      'snr': serializer.toJson<double?>(snr),
      'rssi': serializer.toJson<int?>(rssi),
      'route': serializer.toJson<String>(
        $MessagesTable.$converterroute.toJson(route),
      ),
      'viaMqtt': serializer.toJson<bool>(viaMqtt),
      'nativeId': serializer.toJson<int?>(nativeId),
      'replyTo': serializer.toJson<int?>(replyTo),
      'isReaction': serializer.toJson<bool>(isReaction),
      'attempts': serializer.toJson<int>(attempts),
      'authenticated': serializer.toJson<bool>(authenticated),
      'dedupeKey': serializer.toJson<String?>(dedupeKey),
    };
  }

  MessageRow copyWith({
    int? id,
    String? radioId,
    String? conversation,
    bool? outgoing,
    String? body,
    DateTime? sentAt,
    DateTime? receivedAt,
    String? delivery,
    Value<String?> deliveryReason = const Value.absent(),
    Value<int?> roundTripMs = const Value.absent(),
    Value<String?> fromKey = const Value.absent(),
    Value<String?> senderName = const Value.absent(),
    Value<int?> hops = const Value.absent(),
    Value<double?> snr = const Value.absent(),
    Value<int?> rssi = const Value.absent(),
    RouteKind? route,
    bool? viaMqtt,
    Value<int?> nativeId = const Value.absent(),
    Value<int?> replyTo = const Value.absent(),
    bool? isReaction,
    int? attempts,
    bool? authenticated,
    Value<String?> dedupeKey = const Value.absent(),
  }) => MessageRow(
    id: id ?? this.id,
    radioId: radioId ?? this.radioId,
    conversation: conversation ?? this.conversation,
    outgoing: outgoing ?? this.outgoing,
    body: body ?? this.body,
    sentAt: sentAt ?? this.sentAt,
    receivedAt: receivedAt ?? this.receivedAt,
    delivery: delivery ?? this.delivery,
    deliveryReason: deliveryReason.present
        ? deliveryReason.value
        : this.deliveryReason,
    roundTripMs: roundTripMs.present ? roundTripMs.value : this.roundTripMs,
    fromKey: fromKey.present ? fromKey.value : this.fromKey,
    senderName: senderName.present ? senderName.value : this.senderName,
    hops: hops.present ? hops.value : this.hops,
    snr: snr.present ? snr.value : this.snr,
    rssi: rssi.present ? rssi.value : this.rssi,
    route: route ?? this.route,
    viaMqtt: viaMqtt ?? this.viaMqtt,
    nativeId: nativeId.present ? nativeId.value : this.nativeId,
    replyTo: replyTo.present ? replyTo.value : this.replyTo,
    isReaction: isReaction ?? this.isReaction,
    attempts: attempts ?? this.attempts,
    authenticated: authenticated ?? this.authenticated,
    dedupeKey: dedupeKey.present ? dedupeKey.value : this.dedupeKey,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      id: data.id.present ? data.id.value : this.id,
      radioId: data.radioId.present ? data.radioId.value : this.radioId,
      conversation: data.conversation.present
          ? data.conversation.value
          : this.conversation,
      outgoing: data.outgoing.present ? data.outgoing.value : this.outgoing,
      body: data.body.present ? data.body.value : this.body,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      delivery: data.delivery.present ? data.delivery.value : this.delivery,
      deliveryReason: data.deliveryReason.present
          ? data.deliveryReason.value
          : this.deliveryReason,
      roundTripMs: data.roundTripMs.present
          ? data.roundTripMs.value
          : this.roundTripMs,
      fromKey: data.fromKey.present ? data.fromKey.value : this.fromKey,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      hops: data.hops.present ? data.hops.value : this.hops,
      snr: data.snr.present ? data.snr.value : this.snr,
      rssi: data.rssi.present ? data.rssi.value : this.rssi,
      route: data.route.present ? data.route.value : this.route,
      viaMqtt: data.viaMqtt.present ? data.viaMqtt.value : this.viaMqtt,
      nativeId: data.nativeId.present ? data.nativeId.value : this.nativeId,
      replyTo: data.replyTo.present ? data.replyTo.value : this.replyTo,
      isReaction: data.isReaction.present
          ? data.isReaction.value
          : this.isReaction,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      authenticated: data.authenticated.present
          ? data.authenticated.value
          : this.authenticated,
      dedupeKey: data.dedupeKey.present ? data.dedupeKey.value : this.dedupeKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('id: $id, ')
          ..write('radioId: $radioId, ')
          ..write('conversation: $conversation, ')
          ..write('outgoing: $outgoing, ')
          ..write('body: $body, ')
          ..write('sentAt: $sentAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('delivery: $delivery, ')
          ..write('deliveryReason: $deliveryReason, ')
          ..write('roundTripMs: $roundTripMs, ')
          ..write('fromKey: $fromKey, ')
          ..write('senderName: $senderName, ')
          ..write('hops: $hops, ')
          ..write('snr: $snr, ')
          ..write('rssi: $rssi, ')
          ..write('route: $route, ')
          ..write('viaMqtt: $viaMqtt, ')
          ..write('nativeId: $nativeId, ')
          ..write('replyTo: $replyTo, ')
          ..write('isReaction: $isReaction, ')
          ..write('attempts: $attempts, ')
          ..write('authenticated: $authenticated, ')
          ..write('dedupeKey: $dedupeKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    radioId,
    conversation,
    outgoing,
    body,
    sentAt,
    receivedAt,
    delivery,
    deliveryReason,
    roundTripMs,
    fromKey,
    senderName,
    hops,
    snr,
    rssi,
    route,
    viaMqtt,
    nativeId,
    replyTo,
    isReaction,
    attempts,
    authenticated,
    dedupeKey,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.id == this.id &&
          other.radioId == this.radioId &&
          other.conversation == this.conversation &&
          other.outgoing == this.outgoing &&
          other.body == this.body &&
          other.sentAt == this.sentAt &&
          other.receivedAt == this.receivedAt &&
          other.delivery == this.delivery &&
          other.deliveryReason == this.deliveryReason &&
          other.roundTripMs == this.roundTripMs &&
          other.fromKey == this.fromKey &&
          other.senderName == this.senderName &&
          other.hops == this.hops &&
          other.snr == this.snr &&
          other.rssi == this.rssi &&
          other.route == this.route &&
          other.viaMqtt == this.viaMqtt &&
          other.nativeId == this.nativeId &&
          other.replyTo == this.replyTo &&
          other.isReaction == this.isReaction &&
          other.attempts == this.attempts &&
          other.authenticated == this.authenticated &&
          other.dedupeKey == this.dedupeKey);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<int> id;
  final Value<String> radioId;
  final Value<String> conversation;
  final Value<bool> outgoing;
  final Value<String> body;
  final Value<DateTime> sentAt;
  final Value<DateTime> receivedAt;
  final Value<String> delivery;
  final Value<String?> deliveryReason;
  final Value<int?> roundTripMs;
  final Value<String?> fromKey;
  final Value<String?> senderName;
  final Value<int?> hops;
  final Value<double?> snr;
  final Value<int?> rssi;
  final Value<RouteKind> route;
  final Value<bool> viaMqtt;
  final Value<int?> nativeId;
  final Value<int?> replyTo;
  final Value<bool> isReaction;
  final Value<int> attempts;
  final Value<bool> authenticated;
  final Value<String?> dedupeKey;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.radioId = const Value.absent(),
    this.conversation = const Value.absent(),
    this.outgoing = const Value.absent(),
    this.body = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.delivery = const Value.absent(),
    this.deliveryReason = const Value.absent(),
    this.roundTripMs = const Value.absent(),
    this.fromKey = const Value.absent(),
    this.senderName = const Value.absent(),
    this.hops = const Value.absent(),
    this.snr = const Value.absent(),
    this.rssi = const Value.absent(),
    this.route = const Value.absent(),
    this.viaMqtt = const Value.absent(),
    this.nativeId = const Value.absent(),
    this.replyTo = const Value.absent(),
    this.isReaction = const Value.absent(),
    this.attempts = const Value.absent(),
    this.authenticated = const Value.absent(),
    this.dedupeKey = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required String radioId,
    required String conversation,
    required bool outgoing,
    required String body,
    required DateTime sentAt,
    required DateTime receivedAt,
    required String delivery,
    this.deliveryReason = const Value.absent(),
    this.roundTripMs = const Value.absent(),
    this.fromKey = const Value.absent(),
    this.senderName = const Value.absent(),
    this.hops = const Value.absent(),
    this.snr = const Value.absent(),
    this.rssi = const Value.absent(),
    required RouteKind route,
    this.viaMqtt = const Value.absent(),
    this.nativeId = const Value.absent(),
    this.replyTo = const Value.absent(),
    this.isReaction = const Value.absent(),
    this.attempts = const Value.absent(),
    this.authenticated = const Value.absent(),
    this.dedupeKey = const Value.absent(),
  }) : radioId = Value(radioId),
       conversation = Value(conversation),
       outgoing = Value(outgoing),
       body = Value(body),
       sentAt = Value(sentAt),
       receivedAt = Value(receivedAt),
       delivery = Value(delivery),
       route = Value(route);
  static Insertable<MessageRow> custom({
    Expression<int>? id,
    Expression<String>? radioId,
    Expression<String>? conversation,
    Expression<bool>? outgoing,
    Expression<String>? body,
    Expression<DateTime>? sentAt,
    Expression<DateTime>? receivedAt,
    Expression<String>? delivery,
    Expression<String>? deliveryReason,
    Expression<int>? roundTripMs,
    Expression<String>? fromKey,
    Expression<String>? senderName,
    Expression<int>? hops,
    Expression<double>? snr,
    Expression<int>? rssi,
    Expression<String>? route,
    Expression<bool>? viaMqtt,
    Expression<int>? nativeId,
    Expression<int>? replyTo,
    Expression<bool>? isReaction,
    Expression<int>? attempts,
    Expression<bool>? authenticated,
    Expression<String>? dedupeKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (radioId != null) 'radio_id': radioId,
      if (conversation != null) 'conversation': conversation,
      if (outgoing != null) 'outgoing': outgoing,
      if (body != null) 'body': body,
      if (sentAt != null) 'sent_at': sentAt,
      if (receivedAt != null) 'received_at': receivedAt,
      if (delivery != null) 'delivery': delivery,
      if (deliveryReason != null) 'delivery_reason': deliveryReason,
      if (roundTripMs != null) 'round_trip_ms': roundTripMs,
      if (fromKey != null) 'from_key': fromKey,
      if (senderName != null) 'sender_name': senderName,
      if (hops != null) 'hops': hops,
      if (snr != null) 'snr': snr,
      if (rssi != null) 'rssi': rssi,
      if (route != null) 'route': route,
      if (viaMqtt != null) 'via_mqtt': viaMqtt,
      if (nativeId != null) 'native_id': nativeId,
      if (replyTo != null) 'reply_to': replyTo,
      if (isReaction != null) 'is_reaction': isReaction,
      if (attempts != null) 'attempts': attempts,
      if (authenticated != null) 'authenticated': authenticated,
      if (dedupeKey != null) 'dedupe_key': dedupeKey,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? radioId,
    Value<String>? conversation,
    Value<bool>? outgoing,
    Value<String>? body,
    Value<DateTime>? sentAt,
    Value<DateTime>? receivedAt,
    Value<String>? delivery,
    Value<String?>? deliveryReason,
    Value<int?>? roundTripMs,
    Value<String?>? fromKey,
    Value<String?>? senderName,
    Value<int?>? hops,
    Value<double?>? snr,
    Value<int?>? rssi,
    Value<RouteKind>? route,
    Value<bool>? viaMqtt,
    Value<int?>? nativeId,
    Value<int?>? replyTo,
    Value<bool>? isReaction,
    Value<int>? attempts,
    Value<bool>? authenticated,
    Value<String?>? dedupeKey,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      radioId: radioId ?? this.radioId,
      conversation: conversation ?? this.conversation,
      outgoing: outgoing ?? this.outgoing,
      body: body ?? this.body,
      sentAt: sentAt ?? this.sentAt,
      receivedAt: receivedAt ?? this.receivedAt,
      delivery: delivery ?? this.delivery,
      deliveryReason: deliveryReason ?? this.deliveryReason,
      roundTripMs: roundTripMs ?? this.roundTripMs,
      fromKey: fromKey ?? this.fromKey,
      senderName: senderName ?? this.senderName,
      hops: hops ?? this.hops,
      snr: snr ?? this.snr,
      rssi: rssi ?? this.rssi,
      route: route ?? this.route,
      viaMqtt: viaMqtt ?? this.viaMqtt,
      nativeId: nativeId ?? this.nativeId,
      replyTo: replyTo ?? this.replyTo,
      isReaction: isReaction ?? this.isReaction,
      attempts: attempts ?? this.attempts,
      authenticated: authenticated ?? this.authenticated,
      dedupeKey: dedupeKey ?? this.dedupeKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (radioId.present) {
      map['radio_id'] = Variable<String>(radioId.value);
    }
    if (conversation.present) {
      map['conversation'] = Variable<String>(conversation.value);
    }
    if (outgoing.present) {
      map['outgoing'] = Variable<bool>(outgoing.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (delivery.present) {
      map['delivery'] = Variable<String>(delivery.value);
    }
    if (deliveryReason.present) {
      map['delivery_reason'] = Variable<String>(deliveryReason.value);
    }
    if (roundTripMs.present) {
      map['round_trip_ms'] = Variable<int>(roundTripMs.value);
    }
    if (fromKey.present) {
      map['from_key'] = Variable<String>(fromKey.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (hops.present) {
      map['hops'] = Variable<int>(hops.value);
    }
    if (snr.present) {
      map['snr'] = Variable<double>(snr.value);
    }
    if (rssi.present) {
      map['rssi'] = Variable<int>(rssi.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(
        $MessagesTable.$converterroute.toSql(route.value),
      );
    }
    if (viaMqtt.present) {
      map['via_mqtt'] = Variable<bool>(viaMqtt.value);
    }
    if (nativeId.present) {
      map['native_id'] = Variable<int>(nativeId.value);
    }
    if (replyTo.present) {
      map['reply_to'] = Variable<int>(replyTo.value);
    }
    if (isReaction.present) {
      map['is_reaction'] = Variable<bool>(isReaction.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (authenticated.present) {
      map['authenticated'] = Variable<bool>(authenticated.value);
    }
    if (dedupeKey.present) {
      map['dedupe_key'] = Variable<String>(dedupeKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('radioId: $radioId, ')
          ..write('conversation: $conversation, ')
          ..write('outgoing: $outgoing, ')
          ..write('body: $body, ')
          ..write('sentAt: $sentAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('delivery: $delivery, ')
          ..write('deliveryReason: $deliveryReason, ')
          ..write('roundTripMs: $roundTripMs, ')
          ..write('fromKey: $fromKey, ')
          ..write('senderName: $senderName, ')
          ..write('hops: $hops, ')
          ..write('snr: $snr, ')
          ..write('rssi: $rssi, ')
          ..write('route: $route, ')
          ..write('viaMqtt: $viaMqtt, ')
          ..write('nativeId: $nativeId, ')
          ..write('replyTo: $replyTo, ')
          ..write('isReaction: $isReaction, ')
          ..write('attempts: $attempts, ')
          ..write('authenticated: $authenticated, ')
          ..write('dedupeKey: $dedupeKey')
          ..write(')'))
        .toString();
  }
}

class $VerifiedKeysTable extends VerifiedKeys
    with TableInfo<$VerifiedKeysTable, VerifiedKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VerifiedKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nodeKeyMeta = const VerificationMeta(
    'nodeKey',
  );
  @override
  late final GeneratedColumn<String> nodeKey = GeneratedColumn<String>(
    'node_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicKeyHexMeta = const VerificationMeta(
    'publicKeyHex',
  );
  @override
  late final GeneratedColumn<String> publicKeyHex = GeneratedColumn<String>(
    'public_key_hex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> verifiedAt = GeneratedColumn<DateTime>(
    'verified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    nodeKey,
    publicKeyHex,
    verifiedAt,
    method,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'verified_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<VerifiedKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('node_key')) {
      context.handle(
        _nodeKeyMeta,
        nodeKey.isAcceptableOrUnknown(data['node_key']!, _nodeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeKeyMeta);
    }
    if (data.containsKey('public_key_hex')) {
      context.handle(
        _publicKeyHexMeta,
        publicKeyHex.isAcceptableOrUnknown(
          data['public_key_hex']!,
          _publicKeyHexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_publicKeyHexMeta);
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_verifiedAtMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {nodeKey};
  @override
  VerifiedKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VerifiedKeyRow(
      nodeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_key'],
      )!,
      publicKeyHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key_hex'],
      )!,
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}verified_at'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
    );
  }

  @override
  $VerifiedKeysTable createAlias(String alias) {
    return $VerifiedKeysTable(attachedDatabase, alias);
  }
}

class VerifiedKeyRow extends DataClass implements Insertable<VerifiedKeyRow> {
  /// `NodeKey.toString()`.
  final String nodeKey;

  /// The public key that was confirmed; a different key later means the
  /// node changed (re-flashed, or someone else) and needs checking again.
  final String publicKeyHex;
  final DateTime verifiedAt;

  /// How: `qr` (scanned their code) or `compared` (fingerprints compared).
  final String method;
  const VerifiedKeyRow({
    required this.nodeKey,
    required this.publicKeyHex,
    required this.verifiedAt,
    required this.method,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['node_key'] = Variable<String>(nodeKey);
    map['public_key_hex'] = Variable<String>(publicKeyHex);
    map['verified_at'] = Variable<DateTime>(verifiedAt);
    map['method'] = Variable<String>(method);
    return map;
  }

  VerifiedKeysCompanion toCompanion(bool nullToAbsent) {
    return VerifiedKeysCompanion(
      nodeKey: Value(nodeKey),
      publicKeyHex: Value(publicKeyHex),
      verifiedAt: Value(verifiedAt),
      method: Value(method),
    );
  }

  factory VerifiedKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VerifiedKeyRow(
      nodeKey: serializer.fromJson<String>(json['nodeKey']),
      publicKeyHex: serializer.fromJson<String>(json['publicKeyHex']),
      verifiedAt: serializer.fromJson<DateTime>(json['verifiedAt']),
      method: serializer.fromJson<String>(json['method']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'nodeKey': serializer.toJson<String>(nodeKey),
      'publicKeyHex': serializer.toJson<String>(publicKeyHex),
      'verifiedAt': serializer.toJson<DateTime>(verifiedAt),
      'method': serializer.toJson<String>(method),
    };
  }

  VerifiedKeyRow copyWith({
    String? nodeKey,
    String? publicKeyHex,
    DateTime? verifiedAt,
    String? method,
  }) => VerifiedKeyRow(
    nodeKey: nodeKey ?? this.nodeKey,
    publicKeyHex: publicKeyHex ?? this.publicKeyHex,
    verifiedAt: verifiedAt ?? this.verifiedAt,
    method: method ?? this.method,
  );
  VerifiedKeyRow copyWithCompanion(VerifiedKeysCompanion data) {
    return VerifiedKeyRow(
      nodeKey: data.nodeKey.present ? data.nodeKey.value : this.nodeKey,
      publicKeyHex: data.publicKeyHex.present
          ? data.publicKeyHex.value
          : this.publicKeyHex,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
      method: data.method.present ? data.method.value : this.method,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VerifiedKeyRow(')
          ..write('nodeKey: $nodeKey, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('method: $method')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(nodeKey, publicKeyHex, verifiedAt, method);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VerifiedKeyRow &&
          other.nodeKey == this.nodeKey &&
          other.publicKeyHex == this.publicKeyHex &&
          other.verifiedAt == this.verifiedAt &&
          other.method == this.method);
}

class VerifiedKeysCompanion extends UpdateCompanion<VerifiedKeyRow> {
  final Value<String> nodeKey;
  final Value<String> publicKeyHex;
  final Value<DateTime> verifiedAt;
  final Value<String> method;
  final Value<int> rowid;
  const VerifiedKeysCompanion({
    this.nodeKey = const Value.absent(),
    this.publicKeyHex = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.method = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VerifiedKeysCompanion.insert({
    required String nodeKey,
    required String publicKeyHex,
    required DateTime verifiedAt,
    required String method,
    this.rowid = const Value.absent(),
  }) : nodeKey = Value(nodeKey),
       publicKeyHex = Value(publicKeyHex),
       verifiedAt = Value(verifiedAt),
       method = Value(method);
  static Insertable<VerifiedKeyRow> custom({
    Expression<String>? nodeKey,
    Expression<String>? publicKeyHex,
    Expression<DateTime>? verifiedAt,
    Expression<String>? method,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (nodeKey != null) 'node_key': nodeKey,
      if (publicKeyHex != null) 'public_key_hex': publicKeyHex,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (method != null) 'method': method,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VerifiedKeysCompanion copyWith({
    Value<String>? nodeKey,
    Value<String>? publicKeyHex,
    Value<DateTime>? verifiedAt,
    Value<String>? method,
    Value<int>? rowid,
  }) {
    return VerifiedKeysCompanion(
      nodeKey: nodeKey ?? this.nodeKey,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      method: method ?? this.method,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (nodeKey.present) {
      map['node_key'] = Variable<String>(nodeKey.value);
    }
    if (publicKeyHex.present) {
      map['public_key_hex'] = Variable<String>(publicKeyHex.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<DateTime>(verifiedAt.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VerifiedKeysCompanion(')
          ..write('nodeKey: $nodeKey, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('method: $method, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TelemetryReadingsTable extends TelemetryReadings
    with TableInfo<$TelemetryReadingsTable, TelemetryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TelemetryReadingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _radioIdMeta = const VerificationMeta(
    'radioId',
  );
  @override
  late final GeneratedColumn<String> radioId = GeneratedColumn<String>(
    'radio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeKeyMeta = const VerificationMeta(
    'nodeKey',
  );
  @override
  late final GeneratedColumn<String> nodeKey = GeneratedColumn<String>(
    'node_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<DateTime> time = GeneratedColumn<DateTime>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batteryLevelMeta = const VerificationMeta(
    'batteryLevel',
  );
  @override
  late final GeneratedColumn<int> batteryLevel = GeneratedColumn<int>(
    'battery_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voltageMeta = const VerificationMeta(
    'voltage',
  );
  @override
  late final GeneratedColumn<double> voltage = GeneratedColumn<double>(
    'voltage',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _channelUtilizationMeta =
      const VerificationMeta('channelUtilization');
  @override
  late final GeneratedColumn<double> channelUtilization =
      GeneratedColumn<double>(
        'channel_utilization',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _airUtilTxMeta = const VerificationMeta(
    'airUtilTx',
  );
  @override
  late final GeneratedColumn<double> airUtilTx = GeneratedColumn<double>(
    'air_util_tx',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uptimeSecondsMeta = const VerificationMeta(
    'uptimeSeconds',
  );
  @override
  late final GeneratedColumn<int> uptimeSeconds = GeneratedColumn<int>(
    'uptime_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
    'temperature',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relativeHumidityMeta = const VerificationMeta(
    'relativeHumidity',
  );
  @override
  late final GeneratedColumn<double> relativeHumidity = GeneratedColumn<double>(
    'relative_humidity',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barometricPressureMeta =
      const VerificationMeta('barometricPressure');
  @override
  late final GeneratedColumn<double> barometricPressure =
      GeneratedColumn<double>(
        'barometric_pressure',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    radioId,
    nodeKey,
    time,
    batteryLevel,
    voltage,
    channelUtilization,
    airUtilTx,
    uptimeSeconds,
    temperature,
    relativeHumidity,
    barometricPressure,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'telemetry_readings';
  @override
  VerificationContext validateIntegrity(
    Insertable<TelemetryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('radio_id')) {
      context.handle(
        _radioIdMeta,
        radioId.isAcceptableOrUnknown(data['radio_id']!, _radioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_radioIdMeta);
    }
    if (data.containsKey('node_key')) {
      context.handle(
        _nodeKeyMeta,
        nodeKey.isAcceptableOrUnknown(data['node_key']!, _nodeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeKeyMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('battery_level')) {
      context.handle(
        _batteryLevelMeta,
        batteryLevel.isAcceptableOrUnknown(
          data['battery_level']!,
          _batteryLevelMeta,
        ),
      );
    }
    if (data.containsKey('voltage')) {
      context.handle(
        _voltageMeta,
        voltage.isAcceptableOrUnknown(data['voltage']!, _voltageMeta),
      );
    }
    if (data.containsKey('channel_utilization')) {
      context.handle(
        _channelUtilizationMeta,
        channelUtilization.isAcceptableOrUnknown(
          data['channel_utilization']!,
          _channelUtilizationMeta,
        ),
      );
    }
    if (data.containsKey('air_util_tx')) {
      context.handle(
        _airUtilTxMeta,
        airUtilTx.isAcceptableOrUnknown(data['air_util_tx']!, _airUtilTxMeta),
      );
    }
    if (data.containsKey('uptime_seconds')) {
      context.handle(
        _uptimeSecondsMeta,
        uptimeSeconds.isAcceptableOrUnknown(
          data['uptime_seconds']!,
          _uptimeSecondsMeta,
        ),
      );
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    }
    if (data.containsKey('relative_humidity')) {
      context.handle(
        _relativeHumidityMeta,
        relativeHumidity.isAcceptableOrUnknown(
          data['relative_humidity']!,
          _relativeHumidityMeta,
        ),
      );
    }
    if (data.containsKey('barometric_pressure')) {
      context.handle(
        _barometricPressureMeta,
        barometricPressure.isAcceptableOrUnknown(
          data['barometric_pressure']!,
          _barometricPressureMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TelemetryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TelemetryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      radioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}radio_id'],
      )!,
      nodeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_key'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time'],
      )!,
      batteryLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_level'],
      ),
      voltage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}voltage'],
      ),
      channelUtilization: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}channel_utilization'],
      ),
      airUtilTx: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}air_util_tx'],
      ),
      uptimeSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uptime_seconds'],
      ),
      temperature: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}temperature'],
      ),
      relativeHumidity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}relative_humidity'],
      ),
      barometricPressure: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}barometric_pressure'],
      ),
    );
  }

  @override
  $TelemetryReadingsTable createAlias(String alias) {
    return $TelemetryReadingsTable(attachedDatabase, alias);
  }
}

class TelemetryRow extends DataClass implements Insertable<TelemetryRow> {
  final int id;
  final String radioId;

  /// `NodeKey.toString()`.
  final String nodeKey;
  final DateTime time;
  final int? batteryLevel;
  final double? voltage;
  final double? channelUtilization;
  final double? airUtilTx;
  final int? uptimeSeconds;
  final double? temperature;
  final double? relativeHumidity;
  final double? barometricPressure;
  const TelemetryRow({
    required this.id,
    required this.radioId,
    required this.nodeKey,
    required this.time,
    this.batteryLevel,
    this.voltage,
    this.channelUtilization,
    this.airUtilTx,
    this.uptimeSeconds,
    this.temperature,
    this.relativeHumidity,
    this.barometricPressure,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['radio_id'] = Variable<String>(radioId);
    map['node_key'] = Variable<String>(nodeKey);
    map['time'] = Variable<DateTime>(time);
    if (!nullToAbsent || batteryLevel != null) {
      map['battery_level'] = Variable<int>(batteryLevel);
    }
    if (!nullToAbsent || voltage != null) {
      map['voltage'] = Variable<double>(voltage);
    }
    if (!nullToAbsent || channelUtilization != null) {
      map['channel_utilization'] = Variable<double>(channelUtilization);
    }
    if (!nullToAbsent || airUtilTx != null) {
      map['air_util_tx'] = Variable<double>(airUtilTx);
    }
    if (!nullToAbsent || uptimeSeconds != null) {
      map['uptime_seconds'] = Variable<int>(uptimeSeconds);
    }
    if (!nullToAbsent || temperature != null) {
      map['temperature'] = Variable<double>(temperature);
    }
    if (!nullToAbsent || relativeHumidity != null) {
      map['relative_humidity'] = Variable<double>(relativeHumidity);
    }
    if (!nullToAbsent || barometricPressure != null) {
      map['barometric_pressure'] = Variable<double>(barometricPressure);
    }
    return map;
  }

  TelemetryReadingsCompanion toCompanion(bool nullToAbsent) {
    return TelemetryReadingsCompanion(
      id: Value(id),
      radioId: Value(radioId),
      nodeKey: Value(nodeKey),
      time: Value(time),
      batteryLevel: batteryLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryLevel),
      voltage: voltage == null && nullToAbsent
          ? const Value.absent()
          : Value(voltage),
      channelUtilization: channelUtilization == null && nullToAbsent
          ? const Value.absent()
          : Value(channelUtilization),
      airUtilTx: airUtilTx == null && nullToAbsent
          ? const Value.absent()
          : Value(airUtilTx),
      uptimeSeconds: uptimeSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(uptimeSeconds),
      temperature: temperature == null && nullToAbsent
          ? const Value.absent()
          : Value(temperature),
      relativeHumidity: relativeHumidity == null && nullToAbsent
          ? const Value.absent()
          : Value(relativeHumidity),
      barometricPressure: barometricPressure == null && nullToAbsent
          ? const Value.absent()
          : Value(barometricPressure),
    );
  }

  factory TelemetryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TelemetryRow(
      id: serializer.fromJson<int>(json['id']),
      radioId: serializer.fromJson<String>(json['radioId']),
      nodeKey: serializer.fromJson<String>(json['nodeKey']),
      time: serializer.fromJson<DateTime>(json['time']),
      batteryLevel: serializer.fromJson<int?>(json['batteryLevel']),
      voltage: serializer.fromJson<double?>(json['voltage']),
      channelUtilization: serializer.fromJson<double?>(
        json['channelUtilization'],
      ),
      airUtilTx: serializer.fromJson<double?>(json['airUtilTx']),
      uptimeSeconds: serializer.fromJson<int?>(json['uptimeSeconds']),
      temperature: serializer.fromJson<double?>(json['temperature']),
      relativeHumidity: serializer.fromJson<double?>(json['relativeHumidity']),
      barometricPressure: serializer.fromJson<double?>(
        json['barometricPressure'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'radioId': serializer.toJson<String>(radioId),
      'nodeKey': serializer.toJson<String>(nodeKey),
      'time': serializer.toJson<DateTime>(time),
      'batteryLevel': serializer.toJson<int?>(batteryLevel),
      'voltage': serializer.toJson<double?>(voltage),
      'channelUtilization': serializer.toJson<double?>(channelUtilization),
      'airUtilTx': serializer.toJson<double?>(airUtilTx),
      'uptimeSeconds': serializer.toJson<int?>(uptimeSeconds),
      'temperature': serializer.toJson<double?>(temperature),
      'relativeHumidity': serializer.toJson<double?>(relativeHumidity),
      'barometricPressure': serializer.toJson<double?>(barometricPressure),
    };
  }

  TelemetryRow copyWith({
    int? id,
    String? radioId,
    String? nodeKey,
    DateTime? time,
    Value<int?> batteryLevel = const Value.absent(),
    Value<double?> voltage = const Value.absent(),
    Value<double?> channelUtilization = const Value.absent(),
    Value<double?> airUtilTx = const Value.absent(),
    Value<int?> uptimeSeconds = const Value.absent(),
    Value<double?> temperature = const Value.absent(),
    Value<double?> relativeHumidity = const Value.absent(),
    Value<double?> barometricPressure = const Value.absent(),
  }) => TelemetryRow(
    id: id ?? this.id,
    radioId: radioId ?? this.radioId,
    nodeKey: nodeKey ?? this.nodeKey,
    time: time ?? this.time,
    batteryLevel: batteryLevel.present ? batteryLevel.value : this.batteryLevel,
    voltage: voltage.present ? voltage.value : this.voltage,
    channelUtilization: channelUtilization.present
        ? channelUtilization.value
        : this.channelUtilization,
    airUtilTx: airUtilTx.present ? airUtilTx.value : this.airUtilTx,
    uptimeSeconds: uptimeSeconds.present
        ? uptimeSeconds.value
        : this.uptimeSeconds,
    temperature: temperature.present ? temperature.value : this.temperature,
    relativeHumidity: relativeHumidity.present
        ? relativeHumidity.value
        : this.relativeHumidity,
    barometricPressure: barometricPressure.present
        ? barometricPressure.value
        : this.barometricPressure,
  );
  TelemetryRow copyWithCompanion(TelemetryReadingsCompanion data) {
    return TelemetryRow(
      id: data.id.present ? data.id.value : this.id,
      radioId: data.radioId.present ? data.radioId.value : this.radioId,
      nodeKey: data.nodeKey.present ? data.nodeKey.value : this.nodeKey,
      time: data.time.present ? data.time.value : this.time,
      batteryLevel: data.batteryLevel.present
          ? data.batteryLevel.value
          : this.batteryLevel,
      voltage: data.voltage.present ? data.voltage.value : this.voltage,
      channelUtilization: data.channelUtilization.present
          ? data.channelUtilization.value
          : this.channelUtilization,
      airUtilTx: data.airUtilTx.present ? data.airUtilTx.value : this.airUtilTx,
      uptimeSeconds: data.uptimeSeconds.present
          ? data.uptimeSeconds.value
          : this.uptimeSeconds,
      temperature: data.temperature.present
          ? data.temperature.value
          : this.temperature,
      relativeHumidity: data.relativeHumidity.present
          ? data.relativeHumidity.value
          : this.relativeHumidity,
      barometricPressure: data.barometricPressure.present
          ? data.barometricPressure.value
          : this.barometricPressure,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TelemetryRow(')
          ..write('id: $id, ')
          ..write('radioId: $radioId, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('time: $time, ')
          ..write('batteryLevel: $batteryLevel, ')
          ..write('voltage: $voltage, ')
          ..write('channelUtilization: $channelUtilization, ')
          ..write('airUtilTx: $airUtilTx, ')
          ..write('uptimeSeconds: $uptimeSeconds, ')
          ..write('temperature: $temperature, ')
          ..write('relativeHumidity: $relativeHumidity, ')
          ..write('barometricPressure: $barometricPressure')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    radioId,
    nodeKey,
    time,
    batteryLevel,
    voltage,
    channelUtilization,
    airUtilTx,
    uptimeSeconds,
    temperature,
    relativeHumidity,
    barometricPressure,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TelemetryRow &&
          other.id == this.id &&
          other.radioId == this.radioId &&
          other.nodeKey == this.nodeKey &&
          other.time == this.time &&
          other.batteryLevel == this.batteryLevel &&
          other.voltage == this.voltage &&
          other.channelUtilization == this.channelUtilization &&
          other.airUtilTx == this.airUtilTx &&
          other.uptimeSeconds == this.uptimeSeconds &&
          other.temperature == this.temperature &&
          other.relativeHumidity == this.relativeHumidity &&
          other.barometricPressure == this.barometricPressure);
}

class TelemetryReadingsCompanion extends UpdateCompanion<TelemetryRow> {
  final Value<int> id;
  final Value<String> radioId;
  final Value<String> nodeKey;
  final Value<DateTime> time;
  final Value<int?> batteryLevel;
  final Value<double?> voltage;
  final Value<double?> channelUtilization;
  final Value<double?> airUtilTx;
  final Value<int?> uptimeSeconds;
  final Value<double?> temperature;
  final Value<double?> relativeHumidity;
  final Value<double?> barometricPressure;
  const TelemetryReadingsCompanion({
    this.id = const Value.absent(),
    this.radioId = const Value.absent(),
    this.nodeKey = const Value.absent(),
    this.time = const Value.absent(),
    this.batteryLevel = const Value.absent(),
    this.voltage = const Value.absent(),
    this.channelUtilization = const Value.absent(),
    this.airUtilTx = const Value.absent(),
    this.uptimeSeconds = const Value.absent(),
    this.temperature = const Value.absent(),
    this.relativeHumidity = const Value.absent(),
    this.barometricPressure = const Value.absent(),
  });
  TelemetryReadingsCompanion.insert({
    this.id = const Value.absent(),
    required String radioId,
    required String nodeKey,
    required DateTime time,
    this.batteryLevel = const Value.absent(),
    this.voltage = const Value.absent(),
    this.channelUtilization = const Value.absent(),
    this.airUtilTx = const Value.absent(),
    this.uptimeSeconds = const Value.absent(),
    this.temperature = const Value.absent(),
    this.relativeHumidity = const Value.absent(),
    this.barometricPressure = const Value.absent(),
  }) : radioId = Value(radioId),
       nodeKey = Value(nodeKey),
       time = Value(time);
  static Insertable<TelemetryRow> custom({
    Expression<int>? id,
    Expression<String>? radioId,
    Expression<String>? nodeKey,
    Expression<DateTime>? time,
    Expression<int>? batteryLevel,
    Expression<double>? voltage,
    Expression<double>? channelUtilization,
    Expression<double>? airUtilTx,
    Expression<int>? uptimeSeconds,
    Expression<double>? temperature,
    Expression<double>? relativeHumidity,
    Expression<double>? barometricPressure,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (radioId != null) 'radio_id': radioId,
      if (nodeKey != null) 'node_key': nodeKey,
      if (time != null) 'time': time,
      if (batteryLevel != null) 'battery_level': batteryLevel,
      if (voltage != null) 'voltage': voltage,
      if (channelUtilization != null) 'channel_utilization': channelUtilization,
      if (airUtilTx != null) 'air_util_tx': airUtilTx,
      if (uptimeSeconds != null) 'uptime_seconds': uptimeSeconds,
      if (temperature != null) 'temperature': temperature,
      if (relativeHumidity != null) 'relative_humidity': relativeHumidity,
      if (barometricPressure != null) 'barometric_pressure': barometricPressure,
    });
  }

  TelemetryReadingsCompanion copyWith({
    Value<int>? id,
    Value<String>? radioId,
    Value<String>? nodeKey,
    Value<DateTime>? time,
    Value<int?>? batteryLevel,
    Value<double?>? voltage,
    Value<double?>? channelUtilization,
    Value<double?>? airUtilTx,
    Value<int?>? uptimeSeconds,
    Value<double?>? temperature,
    Value<double?>? relativeHumidity,
    Value<double?>? barometricPressure,
  }) {
    return TelemetryReadingsCompanion(
      id: id ?? this.id,
      radioId: radioId ?? this.radioId,
      nodeKey: nodeKey ?? this.nodeKey,
      time: time ?? this.time,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      voltage: voltage ?? this.voltage,
      channelUtilization: channelUtilization ?? this.channelUtilization,
      airUtilTx: airUtilTx ?? this.airUtilTx,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
      temperature: temperature ?? this.temperature,
      relativeHumidity: relativeHumidity ?? this.relativeHumidity,
      barometricPressure: barometricPressure ?? this.barometricPressure,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (radioId.present) {
      map['radio_id'] = Variable<String>(radioId.value);
    }
    if (nodeKey.present) {
      map['node_key'] = Variable<String>(nodeKey.value);
    }
    if (time.present) {
      map['time'] = Variable<DateTime>(time.value);
    }
    if (batteryLevel.present) {
      map['battery_level'] = Variable<int>(batteryLevel.value);
    }
    if (voltage.present) {
      map['voltage'] = Variable<double>(voltage.value);
    }
    if (channelUtilization.present) {
      map['channel_utilization'] = Variable<double>(channelUtilization.value);
    }
    if (airUtilTx.present) {
      map['air_util_tx'] = Variable<double>(airUtilTx.value);
    }
    if (uptimeSeconds.present) {
      map['uptime_seconds'] = Variable<int>(uptimeSeconds.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (relativeHumidity.present) {
      map['relative_humidity'] = Variable<double>(relativeHumidity.value);
    }
    if (barometricPressure.present) {
      map['barometric_pressure'] = Variable<double>(barometricPressure.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TelemetryReadingsCompanion(')
          ..write('id: $id, ')
          ..write('radioId: $radioId, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('time: $time, ')
          ..write('batteryLevel: $batteryLevel, ')
          ..write('voltage: $voltage, ')
          ..write('channelUtilization: $channelUtilization, ')
          ..write('airUtilTx: $airUtilTx, ')
          ..write('uptimeSeconds: $uptimeSeconds, ')
          ..write('temperature: $temperature, ')
          ..write('relativeHumidity: $relativeHumidity, ')
          ..write('barometricPressure: $barometricPressure')
          ..write(')'))
        .toString();
  }
}

abstract class _$MeshDatabase extends GeneratedDatabase {
  _$MeshDatabase(QueryExecutor e) : super(e);
  $MeshDatabaseManager get managers => $MeshDatabaseManager(this);
  late final $RadiosTable radios = $RadiosTable(this);
  late final $NodesTable nodes = $NodesTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $VerifiedKeysTable verifiedKeys = $VerifiedKeysTable(this);
  late final $TelemetryReadingsTable telemetryReadings =
      $TelemetryReadingsTable(this);
  late final Index messagesByConversation = Index(
    'messages_by_conversation',
    'CREATE INDEX messages_by_conversation ON messages (conversation, id)',
  );
  late final Index messagesByNativeId = Index(
    'messages_by_native_id',
    'CREATE INDEX messages_by_native_id ON messages (radio_id, native_id)',
  );
  late final Index telemetryByNode = Index(
    'telemetry_by_node',
    'CREATE INDEX telemetry_by_node ON telemetry_readings (radio_id, node_key, time)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    radios,
    nodes,
    channels,
    messages,
    verifiedKeys,
    telemetryReadings,
    messagesByConversation,
    messagesByNativeId,
    telemetryByNode,
  ];
}

typedef $$RadiosTableCreateCompanionBuilder =
    RadiosCompanion Function({
      required String id,
      required RadioProtocol protocol,
      required String name,
      required String selfKey,
      Value<String> firmware,
      Value<String> model,
      Value<int?> maxChannels,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<DateTime?> lastConnected,
      Value<int> rowid,
    });
typedef $$RadiosTableUpdateCompanionBuilder =
    RadiosCompanion Function({
      Value<String> id,
      Value<RadioProtocol> protocol,
      Value<String> name,
      Value<String> selfKey,
      Value<String> firmware,
      Value<String> model,
      Value<int?> maxChannels,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<DateTime?> lastConnected,
      Value<int> rowid,
    });

class $$RadiosTableFilterComposer
    extends Composer<_$MeshDatabase, $RadiosTable> {
  $$RadiosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RadioProtocol, RadioProtocol, String>
  get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selfKey => $composableBuilder(
    column: $table.selfKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firmware => $composableBuilder(
    column: $table.firmware,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxChannels => $composableBuilder(
    column: $table.maxChannels,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastConnected => $composableBuilder(
    column: $table.lastConnected,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RadiosTableOrderingComposer
    extends Composer<_$MeshDatabase, $RadiosTable> {
  $$RadiosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selfKey => $composableBuilder(
    column: $table.selfKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firmware => $composableBuilder(
    column: $table.firmware,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxChannels => $composableBuilder(
    column: $table.maxChannels,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastConnected => $composableBuilder(
    column: $table.lastConnected,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RadiosTableAnnotationComposer
    extends Composer<_$MeshDatabase, $RadiosTable> {
  $$RadiosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RadioProtocol, String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get selfKey =>
      $composableBuilder(column: $table.selfKey, builder: (column) => column);

  GeneratedColumn<String> get firmware =>
      $composableBuilder(column: $table.firmware, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get maxChannels => $composableBuilder(
    column: $table.maxChannels,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConnected => $composableBuilder(
    column: $table.lastConnected,
    builder: (column) => column,
  );
}

class $$RadiosTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $RadiosTable,
          RadioRow,
          $$RadiosTableFilterComposer,
          $$RadiosTableOrderingComposer,
          $$RadiosTableAnnotationComposer,
          $$RadiosTableCreateCompanionBuilder,
          $$RadiosTableUpdateCompanionBuilder,
          (RadioRow, BaseReferences<_$MeshDatabase, $RadiosTable, RadioRow>),
          RadioRow,
          PrefetchHooks Function()
        > {
  $$RadiosTableTableManager(_$MeshDatabase db, $RadiosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RadiosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RadiosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RadiosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<RadioProtocol> protocol = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> selfKey = const Value.absent(),
                Value<String> firmware = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int?> maxChannels = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<DateTime?> lastConnected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RadiosCompanion(
                id: id,
                protocol: protocol,
                name: name,
                selfKey: selfKey,
                firmware: firmware,
                model: model,
                maxChannels: maxChannels,
                latitude: latitude,
                longitude: longitude,
                lastConnected: lastConnected,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required RadioProtocol protocol,
                required String name,
                required String selfKey,
                Value<String> firmware = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int?> maxChannels = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<DateTime?> lastConnected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RadiosCompanion.insert(
                id: id,
                protocol: protocol,
                name: name,
                selfKey: selfKey,
                firmware: firmware,
                model: model,
                maxChannels: maxChannels,
                latitude: latitude,
                longitude: longitude,
                lastConnected: lastConnected,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RadiosTable, RadioRow>(table),
                  BaseReferences<_$MeshDatabase, $RadiosTable, RadioRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RadiosTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $RadiosTable,
      RadioRow,
      $$RadiosTableFilterComposer,
      $$RadiosTableOrderingComposer,
      $$RadiosTableAnnotationComposer,
      $$RadiosTableCreateCompanionBuilder,
      $$RadiosTableUpdateCompanionBuilder,
      (RadioRow, BaseReferences<_$MeshDatabase, $RadiosTable, RadioRow>),
      RadioRow,
      PrefetchHooks Function()
    >;
typedef $$NodesTableCreateCompanionBuilder =
    NodesCompanion Function({
      required String radioId,
      required String nodeKey,
      required String name,
      Value<String> shortName,
      required NodeKind kind,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int?> altitude,
      Value<DateTime?> lastHeard,
      Value<int?> hops,
      Value<double?> snr,
      Value<int?> rssi,
      required RouteKind route,
      Value<bool> viaMqtt,
      Value<bool> favorite,
      Value<int?> battery,
      Value<bool> canMessage,
      Value<String?> routeHex,
      Value<String?> publicKeyHex,
      Value<int> rowid,
    });
typedef $$NodesTableUpdateCompanionBuilder =
    NodesCompanion Function({
      Value<String> radioId,
      Value<String> nodeKey,
      Value<String> name,
      Value<String> shortName,
      Value<NodeKind> kind,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int?> altitude,
      Value<DateTime?> lastHeard,
      Value<int?> hops,
      Value<double?> snr,
      Value<int?> rssi,
      Value<RouteKind> route,
      Value<bool> viaMqtt,
      Value<bool> favorite,
      Value<int?> battery,
      Value<bool> canMessage,
      Value<String?> routeHex,
      Value<String?> publicKeyHex,
      Value<int> rowid,
    });

class $$NodesTableFilterComposer extends Composer<_$MeshDatabase, $NodesTable> {
  $$NodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<NodeKind, NodeKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastHeard => $composableBuilder(
    column: $table.lastHeard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hops => $composableBuilder(
    column: $table.hops,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get snr => $composableBuilder(
    column: $table.snr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RouteKind, RouteKind, String> get route =>
      $composableBuilder(
        column: $table.route,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get viaMqtt => $composableBuilder(
    column: $table.viaMqtt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get battery => $composableBuilder(
    column: $table.battery,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canMessage => $composableBuilder(
    column: $table.canMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeHex => $composableBuilder(
    column: $table.routeHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NodesTableOrderingComposer
    extends Composer<_$MeshDatabase, $NodesTable> {
  $$NodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastHeard => $composableBuilder(
    column: $table.lastHeard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hops => $composableBuilder(
    column: $table.hops,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get snr => $composableBuilder(
    column: $table.snr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get viaMqtt => $composableBuilder(
    column: $table.viaMqtt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get battery => $composableBuilder(
    column: $table.battery,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canMessage => $composableBuilder(
    column: $table.canMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeHex => $composableBuilder(
    column: $table.routeHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NodesTableAnnotationComposer
    extends Composer<_$MeshDatabase, $NodesTable> {
  $$NodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get radioId =>
      $composableBuilder(column: $table.radioId, builder: (column) => column);

  GeneratedColumn<String> get nodeKey =>
      $composableBuilder(column: $table.nodeKey, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumnWithTypeConverter<NodeKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get altitude =>
      $composableBuilder(column: $table.altitude, builder: (column) => column);

  GeneratedColumn<DateTime> get lastHeard =>
      $composableBuilder(column: $table.lastHeard, builder: (column) => column);

  GeneratedColumn<int> get hops =>
      $composableBuilder(column: $table.hops, builder: (column) => column);

  GeneratedColumn<double> get snr =>
      $composableBuilder(column: $table.snr, builder: (column) => column);

  GeneratedColumn<int> get rssi =>
      $composableBuilder(column: $table.rssi, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RouteKind, String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<bool> get viaMqtt =>
      $composableBuilder(column: $table.viaMqtt, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get battery =>
      $composableBuilder(column: $table.battery, builder: (column) => column);

  GeneratedColumn<bool> get canMessage => $composableBuilder(
    column: $table.canMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get routeHex =>
      $composableBuilder(column: $table.routeHex, builder: (column) => column);

  GeneratedColumn<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => column,
  );
}

class $$NodesTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $NodesTable,
          NodeRow,
          $$NodesTableFilterComposer,
          $$NodesTableOrderingComposer,
          $$NodesTableAnnotationComposer,
          $$NodesTableCreateCompanionBuilder,
          $$NodesTableUpdateCompanionBuilder,
          (NodeRow, BaseReferences<_$MeshDatabase, $NodesTable, NodeRow>),
          NodeRow,
          PrefetchHooks Function()
        > {
  $$NodesTableTableManager(_$MeshDatabase db, $NodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> radioId = const Value.absent(),
                Value<String> nodeKey = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> shortName = const Value.absent(),
                Value<NodeKind> kind = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int?> altitude = const Value.absent(),
                Value<DateTime?> lastHeard = const Value.absent(),
                Value<int?> hops = const Value.absent(),
                Value<double?> snr = const Value.absent(),
                Value<int?> rssi = const Value.absent(),
                Value<RouteKind> route = const Value.absent(),
                Value<bool> viaMqtt = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> battery = const Value.absent(),
                Value<bool> canMessage = const Value.absent(),
                Value<String?> routeHex = const Value.absent(),
                Value<String?> publicKeyHex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodesCompanion(
                radioId: radioId,
                nodeKey: nodeKey,
                name: name,
                shortName: shortName,
                kind: kind,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                lastHeard: lastHeard,
                hops: hops,
                snr: snr,
                rssi: rssi,
                route: route,
                viaMqtt: viaMqtt,
                favorite: favorite,
                battery: battery,
                canMessage: canMessage,
                routeHex: routeHex,
                publicKeyHex: publicKeyHex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String radioId,
                required String nodeKey,
                required String name,
                Value<String> shortName = const Value.absent(),
                required NodeKind kind,
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int?> altitude = const Value.absent(),
                Value<DateTime?> lastHeard = const Value.absent(),
                Value<int?> hops = const Value.absent(),
                Value<double?> snr = const Value.absent(),
                Value<int?> rssi = const Value.absent(),
                required RouteKind route,
                Value<bool> viaMqtt = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> battery = const Value.absent(),
                Value<bool> canMessage = const Value.absent(),
                Value<String?> routeHex = const Value.absent(),
                Value<String?> publicKeyHex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodesCompanion.insert(
                radioId: radioId,
                nodeKey: nodeKey,
                name: name,
                shortName: shortName,
                kind: kind,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                lastHeard: lastHeard,
                hops: hops,
                snr: snr,
                rssi: rssi,
                route: route,
                viaMqtt: viaMqtt,
                favorite: favorite,
                battery: battery,
                canMessage: canMessage,
                routeHex: routeHex,
                publicKeyHex: publicKeyHex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NodesTable, NodeRow>(table),
                  BaseReferences<_$MeshDatabase, $NodesTable, NodeRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NodesTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $NodesTable,
      NodeRow,
      $$NodesTableFilterComposer,
      $$NodesTableOrderingComposer,
      $$NodesTableAnnotationComposer,
      $$NodesTableCreateCompanionBuilder,
      $$NodesTableUpdateCompanionBuilder,
      (NodeRow, BaseReferences<_$MeshDatabase, $NodesTable, NodeRow>),
      NodeRow,
      PrefetchHooks Function()
    >;
typedef $$ChannelsTableCreateCompanionBuilder =
    ChannelsCompanion Function({
      required String radioId,
      required int slot,
      required String name,
      required ChannelKind kind,
      Value<bool> isPrimary,
      Value<int> rowid,
    });
typedef $$ChannelsTableUpdateCompanionBuilder =
    ChannelsCompanion Function({
      Value<String> radioId,
      Value<int> slot,
      Value<String> name,
      Value<ChannelKind> kind,
      Value<bool> isPrimary,
      Value<int> rowid,
    });

class $$ChannelsTableFilterComposer
    extends Composer<_$MeshDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChannelKind, ChannelKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$MeshDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$MeshDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get radioId =>
      $composableBuilder(column: $table.radioId, builder: (column) => column);

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChannelKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);
}

class $$ChannelsTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $ChannelsTable,
          ChannelRow,
          $$ChannelsTableFilterComposer,
          $$ChannelsTableOrderingComposer,
          $$ChannelsTableAnnotationComposer,
          $$ChannelsTableCreateCompanionBuilder,
          $$ChannelsTableUpdateCompanionBuilder,
          (
            ChannelRow,
            BaseReferences<_$MeshDatabase, $ChannelsTable, ChannelRow>,
          ),
          ChannelRow,
          PrefetchHooks Function()
        > {
  $$ChannelsTableTableManager(_$MeshDatabase db, $ChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> radioId = const Value.absent(),
                Value<int> slot = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<ChannelKind> kind = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion(
                radioId: radioId,
                slot: slot,
                name: name,
                kind: kind,
                isPrimary: isPrimary,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String radioId,
                required int slot,
                required String name,
                required ChannelKind kind,
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion.insert(
                radioId: radioId,
                slot: slot,
                name: name,
                kind: kind,
                isPrimary: isPrimary,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChannelsTable, ChannelRow>(table),
                  BaseReferences<_$MeshDatabase, $ChannelsTable, ChannelRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $ChannelsTable,
      ChannelRow,
      $$ChannelsTableFilterComposer,
      $$ChannelsTableOrderingComposer,
      $$ChannelsTableAnnotationComposer,
      $$ChannelsTableCreateCompanionBuilder,
      $$ChannelsTableUpdateCompanionBuilder,
      (ChannelRow, BaseReferences<_$MeshDatabase, $ChannelsTable, ChannelRow>),
      ChannelRow,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> id,
      required String radioId,
      required String conversation,
      required bool outgoing,
      required String body,
      required DateTime sentAt,
      required DateTime receivedAt,
      required String delivery,
      Value<String?> deliveryReason,
      Value<int?> roundTripMs,
      Value<String?> fromKey,
      Value<String?> senderName,
      Value<int?> hops,
      Value<double?> snr,
      Value<int?> rssi,
      required RouteKind route,
      Value<bool> viaMqtt,
      Value<int?> nativeId,
      Value<int?> replyTo,
      Value<bool> isReaction,
      Value<int> attempts,
      Value<bool> authenticated,
      Value<String?> dedupeKey,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> id,
      Value<String> radioId,
      Value<String> conversation,
      Value<bool> outgoing,
      Value<String> body,
      Value<DateTime> sentAt,
      Value<DateTime> receivedAt,
      Value<String> delivery,
      Value<String?> deliveryReason,
      Value<int?> roundTripMs,
      Value<String?> fromKey,
      Value<String?> senderName,
      Value<int?> hops,
      Value<double?> snr,
      Value<int?> rssi,
      Value<RouteKind> route,
      Value<bool> viaMqtt,
      Value<int?> nativeId,
      Value<int?> replyTo,
      Value<bool> isReaction,
      Value<int> attempts,
      Value<bool> authenticated,
      Value<String?> dedupeKey,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$MeshDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversation => $composableBuilder(
    column: $table.conversation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get outgoing => $composableBuilder(
    column: $table.outgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get delivery => $composableBuilder(
    column: $table.delivery,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryReason => $composableBuilder(
    column: $table.deliveryReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get roundTripMs => $composableBuilder(
    column: $table.roundTripMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromKey => $composableBuilder(
    column: $table.fromKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hops => $composableBuilder(
    column: $table.hops,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get snr => $composableBuilder(
    column: $table.snr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RouteKind, RouteKind, String> get route =>
      $composableBuilder(
        column: $table.route,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get viaMqtt => $composableBuilder(
    column: $table.viaMqtt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nativeId => $composableBuilder(
    column: $table.nativeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get replyTo => $composableBuilder(
    column: $table.replyTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isReaction => $composableBuilder(
    column: $table.isReaction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get authenticated => $composableBuilder(
    column: $table.authenticated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$MeshDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversation => $composableBuilder(
    column: $table.conversation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get outgoing => $composableBuilder(
    column: $table.outgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get delivery => $composableBuilder(
    column: $table.delivery,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryReason => $composableBuilder(
    column: $table.deliveryReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get roundTripMs => $composableBuilder(
    column: $table.roundTripMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromKey => $composableBuilder(
    column: $table.fromKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hops => $composableBuilder(
    column: $table.hops,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get snr => $composableBuilder(
    column: $table.snr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get viaMqtt => $composableBuilder(
    column: $table.viaMqtt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nativeId => $composableBuilder(
    column: $table.nativeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get replyTo => $composableBuilder(
    column: $table.replyTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isReaction => $composableBuilder(
    column: $table.isReaction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get authenticated => $composableBuilder(
    column: $table.authenticated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$MeshDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get radioId =>
      $composableBuilder(column: $table.radioId, builder: (column) => column);

  GeneratedColumn<String> get conversation => $composableBuilder(
    column: $table.conversation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get outgoing =>
      $composableBuilder(column: $table.outgoing, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get delivery =>
      $composableBuilder(column: $table.delivery, builder: (column) => column);

  GeneratedColumn<String> get deliveryReason => $composableBuilder(
    column: $table.deliveryReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get roundTripMs => $composableBuilder(
    column: $table.roundTripMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fromKey =>
      $composableBuilder(column: $table.fromKey, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hops =>
      $composableBuilder(column: $table.hops, builder: (column) => column);

  GeneratedColumn<double> get snr =>
      $composableBuilder(column: $table.snr, builder: (column) => column);

  GeneratedColumn<int> get rssi =>
      $composableBuilder(column: $table.rssi, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RouteKind, String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<bool> get viaMqtt =>
      $composableBuilder(column: $table.viaMqtt, builder: (column) => column);

  GeneratedColumn<int> get nativeId =>
      $composableBuilder(column: $table.nativeId, builder: (column) => column);

  GeneratedColumn<int> get replyTo =>
      $composableBuilder(column: $table.replyTo, builder: (column) => column);

  GeneratedColumn<bool> get isReaction => $composableBuilder(
    column: $table.isReaction,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<bool> get authenticated => $composableBuilder(
    column: $table.authenticated,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dedupeKey =>
      $composableBuilder(column: $table.dedupeKey, builder: (column) => column);
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $MessagesTable,
          MessageRow,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (
            MessageRow,
            BaseReferences<_$MeshDatabase, $MessagesTable, MessageRow>,
          ),
          MessageRow,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$MeshDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> radioId = const Value.absent(),
                Value<String> conversation = const Value.absent(),
                Value<bool> outgoing = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> sentAt = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<String> delivery = const Value.absent(),
                Value<String?> deliveryReason = const Value.absent(),
                Value<int?> roundTripMs = const Value.absent(),
                Value<String?> fromKey = const Value.absent(),
                Value<String?> senderName = const Value.absent(),
                Value<int?> hops = const Value.absent(),
                Value<double?> snr = const Value.absent(),
                Value<int?> rssi = const Value.absent(),
                Value<RouteKind> route = const Value.absent(),
                Value<bool> viaMqtt = const Value.absent(),
                Value<int?> nativeId = const Value.absent(),
                Value<int?> replyTo = const Value.absent(),
                Value<bool> isReaction = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<bool> authenticated = const Value.absent(),
                Value<String?> dedupeKey = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                radioId: radioId,
                conversation: conversation,
                outgoing: outgoing,
                body: body,
                sentAt: sentAt,
                receivedAt: receivedAt,
                delivery: delivery,
                deliveryReason: deliveryReason,
                roundTripMs: roundTripMs,
                fromKey: fromKey,
                senderName: senderName,
                hops: hops,
                snr: snr,
                rssi: rssi,
                route: route,
                viaMqtt: viaMqtt,
                nativeId: nativeId,
                replyTo: replyTo,
                isReaction: isReaction,
                attempts: attempts,
                authenticated: authenticated,
                dedupeKey: dedupeKey,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String radioId,
                required String conversation,
                required bool outgoing,
                required String body,
                required DateTime sentAt,
                required DateTime receivedAt,
                required String delivery,
                Value<String?> deliveryReason = const Value.absent(),
                Value<int?> roundTripMs = const Value.absent(),
                Value<String?> fromKey = const Value.absent(),
                Value<String?> senderName = const Value.absent(),
                Value<int?> hops = const Value.absent(),
                Value<double?> snr = const Value.absent(),
                Value<int?> rssi = const Value.absent(),
                required RouteKind route,
                Value<bool> viaMqtt = const Value.absent(),
                Value<int?> nativeId = const Value.absent(),
                Value<int?> replyTo = const Value.absent(),
                Value<bool> isReaction = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<bool> authenticated = const Value.absent(),
                Value<String?> dedupeKey = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                radioId: radioId,
                conversation: conversation,
                outgoing: outgoing,
                body: body,
                sentAt: sentAt,
                receivedAt: receivedAt,
                delivery: delivery,
                deliveryReason: deliveryReason,
                roundTripMs: roundTripMs,
                fromKey: fromKey,
                senderName: senderName,
                hops: hops,
                snr: snr,
                rssi: rssi,
                route: route,
                viaMqtt: viaMqtt,
                nativeId: nativeId,
                replyTo: replyTo,
                isReaction: isReaction,
                attempts: attempts,
                authenticated: authenticated,
                dedupeKey: dedupeKey,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, MessageRow>(table),
                  BaseReferences<_$MeshDatabase, $MessagesTable, MessageRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $MessagesTable,
      MessageRow,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (MessageRow, BaseReferences<_$MeshDatabase, $MessagesTable, MessageRow>),
      MessageRow,
      PrefetchHooks Function()
    >;
typedef $$VerifiedKeysTableCreateCompanionBuilder =
    VerifiedKeysCompanion Function({
      required String nodeKey,
      required String publicKeyHex,
      required DateTime verifiedAt,
      required String method,
      Value<int> rowid,
    });
typedef $$VerifiedKeysTableUpdateCompanionBuilder =
    VerifiedKeysCompanion Function({
      Value<String> nodeKey,
      Value<String> publicKeyHex,
      Value<DateTime> verifiedAt,
      Value<String> method,
      Value<int> rowid,
    });

class $$VerifiedKeysTableFilterComposer
    extends Composer<_$MeshDatabase, $VerifiedKeysTable> {
  $$VerifiedKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VerifiedKeysTableOrderingComposer
    extends Composer<_$MeshDatabase, $VerifiedKeysTable> {
  $$VerifiedKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VerifiedKeysTableAnnotationComposer
    extends Composer<_$MeshDatabase, $VerifiedKeysTable> {
  $$VerifiedKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get nodeKey =>
      $composableBuilder(column: $table.nodeKey, builder: (column) => column);

  GeneratedColumn<String> get publicKeyHex => $composableBuilder(
    column: $table.publicKeyHex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);
}

class $$VerifiedKeysTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $VerifiedKeysTable,
          VerifiedKeyRow,
          $$VerifiedKeysTableFilterComposer,
          $$VerifiedKeysTableOrderingComposer,
          $$VerifiedKeysTableAnnotationComposer,
          $$VerifiedKeysTableCreateCompanionBuilder,
          $$VerifiedKeysTableUpdateCompanionBuilder,
          (
            VerifiedKeyRow,
            BaseReferences<_$MeshDatabase, $VerifiedKeysTable, VerifiedKeyRow>,
          ),
          VerifiedKeyRow,
          PrefetchHooks Function()
        > {
  $$VerifiedKeysTableTableManager(_$MeshDatabase db, $VerifiedKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VerifiedKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VerifiedKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VerifiedKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> nodeKey = const Value.absent(),
                Value<String> publicKeyHex = const Value.absent(),
                Value<DateTime> verifiedAt = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VerifiedKeysCompanion(
                nodeKey: nodeKey,
                publicKeyHex: publicKeyHex,
                verifiedAt: verifiedAt,
                method: method,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String nodeKey,
                required String publicKeyHex,
                required DateTime verifiedAt,
                required String method,
                Value<int> rowid = const Value.absent(),
              }) => VerifiedKeysCompanion.insert(
                nodeKey: nodeKey,
                publicKeyHex: publicKeyHex,
                verifiedAt: verifiedAt,
                method: method,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VerifiedKeysTable, VerifiedKeyRow>(table),
                  BaseReferences<
                    _$MeshDatabase,
                    $VerifiedKeysTable,
                    VerifiedKeyRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VerifiedKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $VerifiedKeysTable,
      VerifiedKeyRow,
      $$VerifiedKeysTableFilterComposer,
      $$VerifiedKeysTableOrderingComposer,
      $$VerifiedKeysTableAnnotationComposer,
      $$VerifiedKeysTableCreateCompanionBuilder,
      $$VerifiedKeysTableUpdateCompanionBuilder,
      (
        VerifiedKeyRow,
        BaseReferences<_$MeshDatabase, $VerifiedKeysTable, VerifiedKeyRow>,
      ),
      VerifiedKeyRow,
      PrefetchHooks Function()
    >;
typedef $$TelemetryReadingsTableCreateCompanionBuilder =
    TelemetryReadingsCompanion Function({
      Value<int> id,
      required String radioId,
      required String nodeKey,
      required DateTime time,
      Value<int?> batteryLevel,
      Value<double?> voltage,
      Value<double?> channelUtilization,
      Value<double?> airUtilTx,
      Value<int?> uptimeSeconds,
      Value<double?> temperature,
      Value<double?> relativeHumidity,
      Value<double?> barometricPressure,
    });
typedef $$TelemetryReadingsTableUpdateCompanionBuilder =
    TelemetryReadingsCompanion Function({
      Value<int> id,
      Value<String> radioId,
      Value<String> nodeKey,
      Value<DateTime> time,
      Value<int?> batteryLevel,
      Value<double?> voltage,
      Value<double?> channelUtilization,
      Value<double?> airUtilTx,
      Value<int?> uptimeSeconds,
      Value<double?> temperature,
      Value<double?> relativeHumidity,
      Value<double?> barometricPressure,
    });

class $$TelemetryReadingsTableFilterComposer
    extends Composer<_$MeshDatabase, $TelemetryReadingsTable> {
  $$TelemetryReadingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batteryLevel => $composableBuilder(
    column: $table.batteryLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get voltage => $composableBuilder(
    column: $table.voltage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get channelUtilization => $composableBuilder(
    column: $table.channelUtilization,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get airUtilTx => $composableBuilder(
    column: $table.airUtilTx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uptimeSeconds => $composableBuilder(
    column: $table.uptimeSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get relativeHumidity => $composableBuilder(
    column: $table.relativeHumidity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get barometricPressure => $composableBuilder(
    column: $table.barometricPressure,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TelemetryReadingsTableOrderingComposer
    extends Composer<_$MeshDatabase, $TelemetryReadingsTable> {
  $$TelemetryReadingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get radioId => $composableBuilder(
    column: $table.radioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batteryLevel => $composableBuilder(
    column: $table.batteryLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get voltage => $composableBuilder(
    column: $table.voltage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get channelUtilization => $composableBuilder(
    column: $table.channelUtilization,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get airUtilTx => $composableBuilder(
    column: $table.airUtilTx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uptimeSeconds => $composableBuilder(
    column: $table.uptimeSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get relativeHumidity => $composableBuilder(
    column: $table.relativeHumidity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get barometricPressure => $composableBuilder(
    column: $table.barometricPressure,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TelemetryReadingsTableAnnotationComposer
    extends Composer<_$MeshDatabase, $TelemetryReadingsTable> {
  $$TelemetryReadingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get radioId =>
      $composableBuilder(column: $table.radioId, builder: (column) => column);

  GeneratedColumn<String> get nodeKey =>
      $composableBuilder(column: $table.nodeKey, builder: (column) => column);

  GeneratedColumn<DateTime> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<int> get batteryLevel => $composableBuilder(
    column: $table.batteryLevel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get voltage =>
      $composableBuilder(column: $table.voltage, builder: (column) => column);

  GeneratedColumn<double> get channelUtilization => $composableBuilder(
    column: $table.channelUtilization,
    builder: (column) => column,
  );

  GeneratedColumn<double> get airUtilTx =>
      $composableBuilder(column: $table.airUtilTx, builder: (column) => column);

  GeneratedColumn<int> get uptimeSeconds => $composableBuilder(
    column: $table.uptimeSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<double> get relativeHumidity => $composableBuilder(
    column: $table.relativeHumidity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get barometricPressure => $composableBuilder(
    column: $table.barometricPressure,
    builder: (column) => column,
  );
}

class $$TelemetryReadingsTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $TelemetryReadingsTable,
          TelemetryRow,
          $$TelemetryReadingsTableFilterComposer,
          $$TelemetryReadingsTableOrderingComposer,
          $$TelemetryReadingsTableAnnotationComposer,
          $$TelemetryReadingsTableCreateCompanionBuilder,
          $$TelemetryReadingsTableUpdateCompanionBuilder,
          (
            TelemetryRow,
            BaseReferences<
              _$MeshDatabase,
              $TelemetryReadingsTable,
              TelemetryRow
            >,
          ),
          TelemetryRow,
          PrefetchHooks Function()
        > {
  $$TelemetryReadingsTableTableManager(
    _$MeshDatabase db,
    $TelemetryReadingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TelemetryReadingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TelemetryReadingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TelemetryReadingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> radioId = const Value.absent(),
                Value<String> nodeKey = const Value.absent(),
                Value<DateTime> time = const Value.absent(),
                Value<int?> batteryLevel = const Value.absent(),
                Value<double?> voltage = const Value.absent(),
                Value<double?> channelUtilization = const Value.absent(),
                Value<double?> airUtilTx = const Value.absent(),
                Value<int?> uptimeSeconds = const Value.absent(),
                Value<double?> temperature = const Value.absent(),
                Value<double?> relativeHumidity = const Value.absent(),
                Value<double?> barometricPressure = const Value.absent(),
              }) => TelemetryReadingsCompanion(
                id: id,
                radioId: radioId,
                nodeKey: nodeKey,
                time: time,
                batteryLevel: batteryLevel,
                voltage: voltage,
                channelUtilization: channelUtilization,
                airUtilTx: airUtilTx,
                uptimeSeconds: uptimeSeconds,
                temperature: temperature,
                relativeHumidity: relativeHumidity,
                barometricPressure: barometricPressure,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String radioId,
                required String nodeKey,
                required DateTime time,
                Value<int?> batteryLevel = const Value.absent(),
                Value<double?> voltage = const Value.absent(),
                Value<double?> channelUtilization = const Value.absent(),
                Value<double?> airUtilTx = const Value.absent(),
                Value<int?> uptimeSeconds = const Value.absent(),
                Value<double?> temperature = const Value.absent(),
                Value<double?> relativeHumidity = const Value.absent(),
                Value<double?> barometricPressure = const Value.absent(),
              }) => TelemetryReadingsCompanion.insert(
                id: id,
                radioId: radioId,
                nodeKey: nodeKey,
                time: time,
                batteryLevel: batteryLevel,
                voltage: voltage,
                channelUtilization: channelUtilization,
                airUtilTx: airUtilTx,
                uptimeSeconds: uptimeSeconds,
                temperature: temperature,
                relativeHumidity: relativeHumidity,
                barometricPressure: barometricPressure,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TelemetryReadingsTable, TelemetryRow>(table),
                  BaseReferences<
                    _$MeshDatabase,
                    $TelemetryReadingsTable,
                    TelemetryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TelemetryReadingsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $TelemetryReadingsTable,
      TelemetryRow,
      $$TelemetryReadingsTableFilterComposer,
      $$TelemetryReadingsTableOrderingComposer,
      $$TelemetryReadingsTableAnnotationComposer,
      $$TelemetryReadingsTableCreateCompanionBuilder,
      $$TelemetryReadingsTableUpdateCompanionBuilder,
      (
        TelemetryRow,
        BaseReferences<_$MeshDatabase, $TelemetryReadingsTable, TelemetryRow>,
      ),
      TelemetryRow,
      PrefetchHooks Function()
    >;

class $MeshDatabaseManager {
  final _$MeshDatabase _db;
  $MeshDatabaseManager(this._db);
  $$RadiosTableTableManager get radios =>
      $$RadiosTableTableManager(_db, _db.radios);
  $$NodesTableTableManager get nodes =>
      $$NodesTableTableManager(_db, _db.nodes);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$VerifiedKeysTableTableManager get verifiedKeys =>
      $$VerifiedKeysTableTableManager(_db, _db.verifiedKeys);
  $$TelemetryReadingsTableTableManager get telemetryReadings =>
      $$TelemetryReadingsTableTableManager(_db, _db.telemetryReadings);
}
