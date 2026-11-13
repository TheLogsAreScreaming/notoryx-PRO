import 'dart:convert';
import 'dart:typed_data';

import 'protobuf.dart';

// Field numbers follow meshtastic/protobufs v2.8.2 (mesh.proto,
// channel.proto, portnums.proto, telemetry.proto), which are GPL-3.0.

/// Node number meaning "everyone".
const broadcastNode = 0xffffffff;

/// Largest `Data.payload` (DATA_PAYLOAD_LEN in mesh.proto).
const meshtasticMaxPayload = 233;

/// Application port numbers this app uses.
abstract final class PortNum {
  static const textMessage = 1;
  static const position = 3;
  static const nodeInfo = 4;
  static const routing = 5;
  static const admin = 6;
  static const telemetry = 67;
  static const traceroute = 70;
}

/// Why a packet wasn't delivered (`Routing.Error`).
enum RoutingError {
  none(0, 'Delivered'),
  noRoute(1, 'No route to the node'),
  gotNak(2, 'The node refused it'),
  timeout(3, 'Timed out'),
  noInterface(4, 'No radio interface'),
  maxRetransmit(5, 'No acknowledgement after retries'),
  noChannel(6, 'Channel not found'),
  tooLarge(7, 'Message too large'),
  noResponse(8, 'No response'),
  dutyCycleLimit(9, 'Radio duty-cycle limit reached'),
  badRequest(32, 'Bad request'),
  notAuthorized(33, 'Not authorized'),
  pkiFailed(34, 'Encryption to the node failed'),
  pkiUnknownPubkey(35, "The node's key is unknown"),
  adminBadSessionKey(36, 'Admin session expired'),
  adminPublicKeyUnauthorized(37, 'Admin key not authorized'),
  rateLimitExceeded(38, 'Sending too fast'),
  pkiSendFailPublicKey(39, "Couldn't encrypt to the node"),
  unknown(-1, 'Delivery failed');

  const RoutingError(this.code, this.message);

  final int code;

  /// Text to show people.
  final String message;

  static RoutingError of(int code) => values.firstWhere(
    (e) => e.code == code && e != unknown,
    orElse: () => unknown,
  );
}

/// `Data`: the decoded payload of a packet.
class DataPayload {
  const DataPayload({
    required this.portnum,
    required this.payload,
    this.wantResponse = false,
    this.dest = 0,
    this.source = 0,
    this.requestId = 0,
    this.replyId = 0,
    this.emoji = 0,
  });

  final int portnum;
  final Uint8List payload;
  final bool wantResponse;
  final int dest;
  final int source;

  /// For replies (including acks): the ID of the packet answered.
  final int requestId;

  /// For text replies: the message being replied to.
  final int replyId;

  /// Non-zero when the text is a single-emoji reaction.
  final int emoji;

  static DataPayload decode(Uint8List data) {
    var portnum = 0;
    var payload = Uint8List(0);
    var wantResponse = false;
    var dest = 0, source = 0, requestId = 0, replyId = 0, emoji = 0;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          portnum = f.asInt;
        case 2:
          payload = f.asBytes;
        case 3:
          wantResponse = f.asBool;
        case 4:
          dest = f.asInt;
        case 5:
          source = f.asInt;
        case 6:
          requestId = f.asInt;
        case 7:
          replyId = f.asInt;
        case 8:
          emoji = f.asInt;
      }
    }
    return DataPayload(
      portnum: portnum,
      payload: payload,
      wantResponse: wantResponse,
      dest: dest,
      source: source,
      requestId: requestId,
      replyId: replyId,
      emoji: emoji,
    );
  }

  Uint8List encode() {
    final w = ProtoWriter()
      ..uint(1, portnum)
      ..bytes(2, payload)
      ..boolean(3, wantResponse)
      ..fixed32(4, dest)
      ..fixed32(5, source)
      ..fixed32(6, requestId)
      ..fixed32(7, replyId)
      ..fixed32(8, emoji);
    return w.toBytes();
  }
}

/// `MeshPacket`, with the routing facts the app shows for each message.
class MeshPacket {
  const MeshPacket({
    required this.from,
    required this.to,
    required this.id,
    this.channel = 0,
    this.decoded,
    this.encrypted,
    this.rxTime,
    this.rxSnr,
    this.rxRssi,
    this.hopLimit = 0,
    this.hopStart = 0,
    this.wantAck = false,
    this.viaMqtt = false,
    this.pkiEncrypted = false,
    this.relayNode = 0,
  });

  final int from;
  final int to;
  final int id;

  /// Channel index (or, for encrypted packets, the channel hash).
  final int channel;
  final DataPayload? decoded;
  final Uint8List? encrypted;

  /// When the node received it, Unix seconds.
  final int? rxTime;
  final double? rxSnr;
  final int? rxRssi;
  final int hopLimit;
  final int hopStart;
  final bool wantAck;

  /// Arrived through an MQTT gateway rather than only over LoRa.
  final bool viaMqtt;

  /// A direct message encrypted to this node's public key.
  final bool pkiEncrypted;

  /// Last byte of the node that relayed it to us.
  final int relayNode;

  /// Hops taken, when the sender's firmware reports `hop_start`.
  int? get hopsTaken =>
      hopStart > 0 && hopStart >= hopLimit ? hopStart - hopLimit : null;

  bool get isBroadcast => to == broadcastNode;

  static MeshPacket decode(Uint8List data) {
    var from = 0, to = 0, id = 0, channel = 0;
    DataPayload? decoded;
    Uint8List? encrypted;
    int? rxTime;
    double? rxSnr;
    int? rxRssi;
    var hopLimit = 0, hopStart = 0, relayNode = 0;
    var wantAck = false, viaMqtt = false, pki = false;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          from = f.asInt;
        case 2:
          to = f.asInt;
        case 3:
          channel = f.asInt;
        case 4:
          decoded = DataPayload.decode(f.asBytes);
        case 5:
          encrypted = f.asBytes;
        case 6:
          id = f.asInt;
        case 7:
          rxTime = f.asInt;
        case 8:
          rxSnr = f.asFloat;
        case 9:
          hopLimit = f.asInt;
        case 10:
          wantAck = f.asBool;
        case 12:
          rxRssi = f.asInt32;
        case 14:
          viaMqtt = f.asBool;
        case 15:
          hopStart = f.asInt;
        case 17:
          pki = f.asBool;
        case 19:
          relayNode = f.asInt;
      }
    }
    return MeshPacket(
      from: from,
      to: to,
      id: id,
      channel: channel,
      decoded: decoded,
      encrypted: encrypted,
      rxTime: rxTime,
      rxSnr: rxSnr,
      rxRssi: rxRssi,
      hopLimit: hopLimit,
      hopStart: hopStart,
      wantAck: wantAck,
      viaMqtt: viaMqtt,
      pkiEncrypted: pki,
      relayNode: relayNode,
    );
  }

  /// Encodes a packet to send. `from` is left for the node to fill in, and
  /// `hop_limit` for it to set from its own settings.
  Uint8List encode() {
    final w = ProtoWriter()
      ..fixed32(2, to, always: true)
      ..uint(3, channel);
    if (decoded != null) w.bytes(4, decoded!.encode(), always: true);
    w
      ..fixed32(6, id)
      ..uint(9, hopLimit)
      ..boolean(10, wantAck)
      ..boolean(17, pkiEncrypted);
    return w.toBytes();
  }
}

/// `MyNodeInfo`: which node this radio is.
class MyNodeInfo {
  const MyNodeInfo({
    required this.nodeNum,
    this.rebootCount = 0,
    this.minAppVersion = 0,
    this.pioEnv = '',
    this.nodeDbCount = 0,
  });

  final int nodeNum;
  final int rebootCount;
  final int minAppVersion;
  final String pioEnv;
  final int nodeDbCount;

  static MyNodeInfo decode(Uint8List data) {
    var num = 0, reboots = 0, minApp = 0, count = 0;
    var env = '';
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          num = f.asInt;
        case 8:
          reboots = f.asInt;
        case 11:
          minApp = f.asInt;
        case 13:
          env = f.asString;
        case 15:
          count = f.asInt;
      }
    }
    return MyNodeInfo(
      nodeNum: num,
      rebootCount: reboots,
      minAppVersion: minApp,
      pioEnv: env,
      nodeDbCount: count,
    );
  }
}

/// `User`: a node's names and identity.
class MeshUser {
  const MeshUser({
    this.id = '',
    this.longName = '',
    this.shortName = '',
    this.hwModel = 0,
    this.role = 0,
    this.isLicensed = false,
    this.publicKey,
    this.isUnmessagable = false,
  });

  /// `!` followed by the node number in hex, e.g. `!a1b2c3d4`.
  final String id;
  final String longName;
  final String shortName;
  final int hwModel;
  final int role;

  /// Licensed amateur operator (no encryption).
  final bool isLicensed;
  final Uint8List? publicKey;
  final bool isUnmessagable;

  /// Encodes the fields [decode] reads.
  Uint8List encode() {
    final w = ProtoWriter()
      ..string(1, id)
      ..string(2, longName)
      ..string(3, shortName)
      ..uint(5, hwModel)
      ..boolean(6, isLicensed)
      ..uint(7, role);
    if (publicKey case final k? when k.isNotEmpty) w.bytes(8, k);
    w.boolean(9, isUnmessagable);
    return w.toBytes();
  }

  static MeshUser decode(Uint8List data) {
    var id = '', longName = '', shortName = '';
    var hw = 0, role = 0;
    var licensed = false, unmessagable = false;
    Uint8List? key;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          id = f.asString;
        case 2:
          longName = f.asString;
        case 3:
          shortName = f.asString;
        case 5:
          hw = f.asInt;
        case 6:
          licensed = f.asBool;
        case 7:
          role = f.asInt;
        case 8:
          key = f.asBytes;
        case 9:
          unmessagable = f.asBool;
      }
    }
    return MeshUser(
      id: id,
      longName: longName,
      shortName: shortName,
      hwModel: hw,
      role: role,
      isLicensed: licensed,
      publicKey: key,
      isUnmessagable: unmessagable,
    );
  }
}

/// `Position` (the fields the app shows).
class MeshPosition {
  const MeshPosition({
    this.latitude,
    this.longitude,
    this.altitude,
    this.time = 0,
    this.precisionBits = 0,
  });

  final double? latitude;
  final double? longitude;
  final int? altitude;
  final int time;
  final int precisionBits;

  static MeshPosition decode(Uint8List data) {
    double? lat, lon;
    int? alt;
    var time = 0, precision = 0;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          lat = f.asSfixed32 / 1e7;
        case 2:
          lon = f.asSfixed32 / 1e7;
        case 3:
          alt = f.asInt32;
        case 4:
          time = f.asInt;
        case 23:
          precision = f.asInt;
      }
    }
    return MeshPosition(
      latitude: lat,
      longitude: lon,
      altitude: alt,
      time: time,
      precisionBits: precision,
    );
  }
}

/// `DeviceMetrics` from telemetry.proto.
class DeviceMetrics {
  const DeviceMetrics({
    this.batteryLevel,
    this.voltage,
    this.channelUtilization,
    this.airUtilTx,
    this.uptimeSeconds,
  });

  /// Percent; 101 means powered externally.
  final int? batteryLevel;
  final double? voltage;
  final double? channelUtilization;
  final double? airUtilTx;
  final int? uptimeSeconds;

  static DeviceMetrics decode(Uint8List data) {
    int? battery, uptime;
    double? volts, chUtil, airUtil;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          battery = f.asInt;
        case 2:
          volts = f.asFloat;
        case 3:
          chUtil = f.asFloat;
        case 4:
          airUtil = f.asFloat;
        case 5:
          uptime = f.asInt;
      }
    }
    return DeviceMetrics(
      batteryLevel: battery,
      voltage: volts,
      channelUtilization: chUtil,
      airUtilTx: airUtil,
      uptimeSeconds: uptime,
    );
  }
}

/// `NodeInfo`: one entry of the radio's node database.
class MeshNodeInfo {
  const MeshNodeInfo({
    required this.num,
    this.user,
    this.position,
    this.snr,
    this.lastHeard = 0,
    this.metrics,
    this.channel = 0,
    this.viaMqtt = false,
    this.hopsAway,
    this.isFavorite = false,
    this.isIgnored = false,
  });

  final int num;
  final MeshUser? user;
  final MeshPosition? position;
  final double? snr;

  /// Unix seconds.
  final int lastHeard;
  final DeviceMetrics? metrics;
  final int channel;
  final bool viaMqtt;
  final int? hopsAway;
  final bool isFavorite;
  final bool isIgnored;

  static MeshNodeInfo decode(Uint8List data) {
    var num = 0, lastHeard = 0, channel = 0;
    MeshUser? user;
    MeshPosition? position;
    DeviceMetrics? metrics;
    double? snr;
    int? hops;
    var mqtt = false, fav = false, ignored = false;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          num = f.asInt;
        case 2:
          user = MeshUser.decode(f.asBytes);
        case 3:
          position = MeshPosition.decode(f.asBytes);
        case 4:
          snr = f.asFloat;
        case 5:
          lastHeard = f.asInt;
        case 6:
          metrics = DeviceMetrics.decode(f.asBytes);
        case 7:
          channel = f.asInt;
        case 8:
          mqtt = f.asBool;
        case 9:
          hops = f.asInt;
        case 10:
          fav = f.asBool;
        case 11:
          ignored = f.asBool;
      }
    }
    return MeshNodeInfo(
      num: num,
      user: user,
      position: position,
      snr: snr,
      lastHeard: lastHeard,
      metrics: metrics,
      channel: channel,
      viaMqtt: mqtt,
      hopsAway: hops,
      isFavorite: fav,
      isIgnored: ignored,
    );
  }
}

/// `LocalStats` from telemetry: what this node's radio sees.
class LocalStats {
  const LocalStats({
    this.channelUtilization,
    this.airUtilTx,
    this.packetsTx,
    this.packetsRx,
    this.packetsRxBad,
    this.onlineNodes,
    this.noiseFloor,
  });

  /// Percent of time the channel is busy.
  final double? channelUtilization;

  /// Percent of the last hour this node spent transmitting.
  final double? airUtilTx;
  final int? packetsTx;
  final int? packetsRx;
  final int? packetsRxBad;
  final int? onlineNodes;

  /// Background noise in dBm, when the firmware reports it.
  final int? noiseFloor;

  static LocalStats decode(Uint8List data) {
    double? ch, air;
    int? tx, rx, bad, online, noise;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 2:
          ch = f.asFloat;
        case 3:
          air = f.asFloat;
        case 4:
          tx = f.asInt;
        case 5:
          rx = f.asInt;
        case 6:
          bad = f.asInt;
        case 7:
          online = f.asInt;
        case 15:
          noise = f.asInt32;
      }
    }
    return LocalStats(
      channelUtilization: ch,
      airUtilTx: air,
      packetsTx: tx,
      packetsRx: rx,
      packetsRxBad: bad,
      onlineNodes: online,
      noiseFloor: noise,
    );
  }
}

/// `EnvironmentMetrics` from telemetry.proto (the common readings).
class EnvironmentMetrics {
  const EnvironmentMetrics({
    this.temperature,
    this.relativeHumidity,
    this.barometricPressure,
  });

  /// Degrees Celsius.
  final double? temperature;

  /// Percent.
  final double? relativeHumidity;

  /// hPa.
  final double? barometricPressure;

  bool get isEmpty =>
      temperature == null &&
      relativeHumidity == null &&
      barometricPressure == null;

  static EnvironmentMetrics decode(Uint8List data) {
    double? t, h, p;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          t = f.asFloat;
        case 2:
          h = f.asFloat;
        case 3:
          p = f.asFloat;
      }
    }
    return EnvironmentMetrics(
      temperature: t,
      relativeHumidity: h,
      barometricPressure: p,
    );
  }
}

/// `Telemetry`: the variants this app reads.
class Telemetry {
  const Telemetry({this.time, this.device, this.environment, this.local});

  /// When the node took the reading, Unix seconds; null if not set.
  final int? time;
  final DeviceMetrics? device;
  final EnvironmentMetrics? environment;
  final LocalStats? local;

  static Telemetry decode(Uint8List data) {
    int? time;
    DeviceMetrics? device;
    EnvironmentMetrics? environment;
    LocalStats? local;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          time = f.asInt == 0 ? null : f.asInt;
        case 2:
          device = DeviceMetrics.decode(f.asBytes);
        case 3:
          environment = EnvironmentMetrics.decode(f.asBytes);
        case 6:
          local = LocalStats.decode(f.asBytes);
      }
    }
    return Telemetry(
      time: time,
      device: device,
      environment: environment,
      local: local,
    );
  }
}

/// `RouteDiscovery`: a traceroute's answer.
class RouteDiscovery {
  const RouteDiscovery({
    this.route = const [],
    this.snrTowards = const [],
    this.routeBack = const [],
    this.snrBack = const [],
  });

  /// Nodes between us and the target, in order.
  final List<int> route;

  /// SNR (dB) of each hop towards the target, including the last; null
  /// where the firmware didn't know it.
  final List<double?> snrTowards;
  final List<int> routeBack;
  final List<double?> snrBack;

  static double? _snr(int raw) => raw == -128 ? null : raw / 4.0;

  static RouteDiscovery decode(Uint8List data) {
    final route = <int>[], back = <int>[];
    final towards = <double?>[], backSnr = <double?>[];
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          route.addAll(f.asFixed32List);
        case 2:
          towards.addAll(f.asInt32List.map(_snr));
        case 3:
          back.addAll(f.asFixed32List);
        case 4:
          backSnr.addAll(f.asInt32List.map(_snr));
      }
    }
    return RouteDiscovery(
      route: route,
      snrTowards: towards,
      routeBack: back,
      snrBack: backSnr,
    );
  }
}

/// Channel roles.
enum ChannelRole { disabled, primary, secondary }

/// `Channel` with its `ChannelSettings`.
class MeshChannel {
  const MeshChannel({
    required this.index,
    required this.role,
    this.name = '',
    this.psk,
    this.uplink = false,
    this.downlink = false,
  });

  final int index;
  final ChannelRole role;

  /// Empty for the primary channel means the preset's default name.
  final String name;

  /// Encryption key; never shown or logged.
  final Uint8List? psk;
  final bool uplink;
  final bool downlink;

  bool get isEnabled => role != ChannelRole.disabled;

  /// Encodes the channel for an admin `set_channel`.
  Uint8List encode() {
    final settings = ProtoWriter()
      ..bytes(2, psk ?? const [])
      ..string(3, name)
      ..boolean(5, uplink)
      ..boolean(6, downlink);
    return (ProtoWriter()
          ..uint(1, index)
          ..bytes(2, settings.toBytes(), always: true)
          ..uint(3, role.index))
        .toBytes();
  }

  static MeshChannel decode(Uint8List data) {
    var index = 0, role = 0;
    var name = '';
    Uint8List? psk;
    var up = false, down = false;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          index = f.asInt32;
        case 2:
          for (final s in readFields(f.asBytes)) {
            switch (s.number) {
              case 2:
                psk = s.asBytes;
              case 3:
                name = s.asString;
              case 5:
                up = s.asBool;
              case 6:
                down = s.asBool;
            }
          }
        case 3:
          role = f.asInt;
      }
    }
    return MeshChannel(
      index: index,
      role: role >= 0 && role < ChannelRole.values.length
          ? ChannelRole.values[role]
          : ChannelRole.disabled,
      name: name,
      psk: psk,
      uplink: up,
      downlink: down,
    );
  }
}

/// `DeviceMetadata`: firmware version and hardware.
class DeviceMetadata {
  const DeviceMetadata({
    this.firmwareVersion = '',
    this.deviceStateVersion = 0,
    this.hasWifi = false,
    this.hasBluetooth = false,
    this.hasEthernet = false,
    this.role = 0,
    this.hwModel = 0,
    this.hasPkc = false,
  });

  /// For example `2.8.2.d5f1619`.
  final String firmwareVersion;
  final int deviceStateVersion;
  final bool hasWifi;
  final bool hasBluetooth;
  final bool hasEthernet;
  final int role;
  final int hwModel;

  /// Supports public-key encrypted direct messages.
  final bool hasPkc;

  static DeviceMetadata decode(Uint8List data) {
    var version = '';
    var state = 0, role = 0, hw = 0;
    var wifi = false, bt = false, eth = false, pkc = false;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          version = f.asString;
        case 2:
          state = f.asInt;
        case 4:
          wifi = f.asBool;
        case 5:
          bt = f.asBool;
        case 6:
          eth = f.asBool;
        case 7:
          role = f.asInt;
        case 9:
          hw = f.asInt;
        case 11:
          pkc = f.asBool;
      }
    }
    return DeviceMetadata(
      firmwareVersion: version,
      deviceStateVersion: state,
      hasWifi: wifi,
      hasBluetooth: bt,
      hasEthernet: eth,
      role: role,
      hwModel: hw,
      hasPkc: pkc,
    );
  }
}

/// Everything a node sends to the app (`FromRadio`).
sealed class FromRadio {
  const FromRadio(this.id);

  /// Sequence number from the node; 0 if not set.
  final int id;

  /// Decodes one `FromRadio`. Throws [ProtobufException] for bad bytes.
  static FromRadio decode(Uint8List data) {
    var id = 0;
    FromRadio? result;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          id = f.asInt;
        case 2:
          result = PacketFromRadio(id, MeshPacket.decode(f.asBytes));
        case 3:
          result = MyInfoFromRadio(id, MyNodeInfo.decode(f.asBytes));
        case 4:
          result = NodeInfoFromRadio(id, MeshNodeInfo.decode(f.asBytes));
        case 5:
          result = ConfigFromRadio(id, f.asBytes, module: false);
        case 6:
          result = LogFromRadio(id, _logText(f.asBytes));
        case 7:
          result = ConfigCompleteFromRadio(id, f.asInt);
        case 8:
          result = RebootedFromRadio(id);
        case 9:
          result = ConfigFromRadio(id, f.asBytes, module: true);
        case 10:
          result = ChannelFromRadio(id, MeshChannel.decode(f.asBytes));
        case 11:
          result = QueueStatusFromRadio.decode(id, f.asBytes);
        case 13:
          result = MetadataFromRadio(id, DeviceMetadata.decode(f.asBytes));
        case 16:
          result = NotificationFromRadio(id, _notificationText(f.asBytes));
        default:
          if (f.number > 1) result ??= OtherFromRadio(id, f.number);
      }
    }
    // Encoders write `id` (field 1) first, so it is known by now.
    return result ?? OtherFromRadio(id, 0);
  }

  static String _logText(Uint8List data) {
    for (final f in readFields(data)) {
      if (f.number == 1) return f.asString;
    }
    return '';
  }

  static String _notificationText(Uint8List data) {
    for (final f in readFields(data)) {
      if (f.number == 4) return f.asString;
    }
    return '';
  }
}

/// A mesh packet heard or sent by the node.
final class PacketFromRadio extends FromRadio {
  const PacketFromRadio(super.id, this.packet);
  final MeshPacket packet;
}

/// This node's number and details (start of the config download).
final class MyInfoFromRadio extends FromRadio {
  const MyInfoFromRadio(super.id, this.info);
  final MyNodeInfo info;
}

/// One node from the node database.
final class NodeInfoFromRadio extends FromRadio {
  const NodeInfoFromRadio(super.id, this.node);
  final MeshNodeInfo node;
}

/// A `Config` or `ModuleConfig` section, kept raw until admin (step 13b).
final class ConfigFromRadio extends FromRadio {
  const ConfigFromRadio(super.id, this.raw, {required this.module});
  final Uint8List raw;
  final bool module;

  /// Which section it is (the oneof field number), or 0.
  int get section {
    final fields = readFields(raw);
    return fields.isEmpty ? 0 : fields.first.number;
  }
}

/// A firmware log line.
final class LogFromRadio extends FromRadio {
  const LogFromRadio(super.id, this.message);
  final String message;
}

/// End of the config download; [nonce] matches `want_config_id`.
final class ConfigCompleteFromRadio extends FromRadio {
  const ConfigCompleteFromRadio(super.id, this.nonce);
  final int nonce;
}

/// The node rebooted; the app must ask for the config again.
final class RebootedFromRadio extends FromRadio {
  const RebootedFromRadio(super.id);
}

/// One channel slot.
final class ChannelFromRadio extends FromRadio {
  const ChannelFromRadio(super.id, this.channel);
  final MeshChannel channel;
}

/// Space in the node's send queue, and the result for one packet.
final class QueueStatusFromRadio extends FromRadio {
  const QueueStatusFromRadio(
    super.id, {
    required this.result,
    required this.free,
    required this.maxLength,
    required this.packetId,
  });

  /// 0 when the packet was queued; non-zero for an error.
  final int result;
  final int free;
  final int maxLength;
  final int packetId;

  static QueueStatusFromRadio decode(int id, Uint8List data) {
    var res = 0, free = 0, max = 0, pid = 0;
    for (final f in readFields(data)) {
      switch (f.number) {
        case 1:
          res = f.asInt32;
        case 2:
          free = f.asInt;
        case 3:
          max = f.asInt;
        case 4:
          pid = f.asInt;
      }
    }
    return QueueStatusFromRadio(
      id,
      result: res,
      free: free,
      maxLength: max,
      packetId: pid,
    );
  }
}

/// Firmware version and hardware.
final class MetadataFromRadio extends FromRadio {
  const MetadataFromRadio(super.id, this.metadata);
  final DeviceMetadata metadata;
}

/// A message from the firmware meant for the person (e.g. a key warning).
final class NotificationFromRadio extends FromRadio {
  const NotificationFromRadio(super.id, this.message);
  final String message;
}

/// A `FromRadio` this app doesn't use yet.
final class OtherFromRadio extends FromRadio {
  const OtherFromRadio(super.id, this.field);
  final int field;
}

/// Builders for `ToRadio`.
abstract final class ToRadio {
  /// Sends a packet.
  static Uint8List packet(MeshPacket packet) =>
      (ProtoWriter()..bytes(1, packet.encode(), always: true)).toBytes();

  /// Asks for the node's whole config; it ends with config_complete_id.
  static Uint8List wantConfig(int nonce) =>
      (ProtoWriter()..uint(3, nonce, always: true)).toBytes();

  /// Tells a USB/TCP node the app is leaving.
  static Uint8List disconnect() => (ProtoWriter()..boolean(4, true)).toBytes();

  /// Keeps a USB/TCP connection alive.
  static Uint8List heartbeat([int nonce = 0]) {
    final inner = (ProtoWriter()..uint(1, nonce)).toBytes();
    return (ProtoWriter()..bytes(7, inner, always: true)).toBytes();
  }
}

/// Builds the payload for a text message.
Uint8List textPayload(String text) {
  final bytes = utf8.encode(text);
  if (bytes.isEmpty) throw ArgumentError.value(text, 'text', 'empty');
  if (bytes.length > meshtasticMaxPayload) {
    throw ArgumentError.value(
      bytes.length,
      'text',
      'longer than $meshtasticMaxPayload bytes',
    );
  }
  return Uint8List.fromList(bytes);
}

/// Formats a node number as Meshtastic does: `!a1b2c3d4`.
String nodeIdOf(int num) => '!${num.toRadixString(16).padLeft(8, '0')}';
