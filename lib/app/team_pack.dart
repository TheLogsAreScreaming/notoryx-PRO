import 'dart:convert';
import 'dart:io' show gzip;

import '../mesh/gpx.dart' show maxRoutePoints;
import '../mesh/mesh.dart';
import '../mesh/places.dart';
import '../meshtastic/meshtastic.dart' show LoraField, SectionKind;
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';
import 'meshcore_settings.dart';
import 'radio_connection.dart';

/// A file or code that isn't a team pack this version can read.
class NotATeamPack implements Exception {
  const NotATeamPack({this.tooNew = false});
  final bool tooNew;
}

const _format = 'notoryx-pro-team';
const _prefix = 'notoryxteam:';

/// The most places one pack can carry.
const maxPackPlaces = 200;

/// Channels, radio settings and map places a team can share.
///
/// Never carries a radio's name, position, transmit power or keys for
/// anything but its channels.
class TeamPack {
  const TeamPack({
    required this.name,
    required this.protocol,
    this.channels = const [],
    this.radio,
    this.places = const [],
  });

  final String name;
  final RadioProtocol protocol;
  final List<ChannelInvite> channels;

  /// MeshCore: `f`, `bw`, `sf`, `cr`. Meshtastic: `region`, `usePreset`,
  /// `preset`, `hops`, `slot`.
  final Map<String, num>? radio;
  final List<Place> places;

  Map<String, Object?> _json() => {
    'format': _format,
    'formatVersion': 1,
    'name': name,
    'protocol': protocol.name,
    'channels': [
      for (final c in channels) {'n': c.name, 's': base64Encode(c.secret)},
    ],
    'radio': ?radio,
    'places': [
      for (final p in places)
        {
          'k': p.kind.name,
          'n': p.name,
          'p': [
            for (final x in p.points) [x.latitude, x.longitude],
          ],
          'r': ?p.radiusM,
        },
    ],
  };

  /// As a JSON file.
  String toFile() => const JsonEncoder.withIndent(' ').convert(_json());

  /// As compact text for a QR code.
  String toCode() =>
      _prefix + base64Url.encode(gzip.encode(utf8.encode(jsonEncode(_json()))));

  /// Reads a file or code. Everything is checked, since a pack can come
  /// from anyone; parts out of range are dropped, and a pack that isn't one
  /// throws [NotATeamPack].
  static TeamPack parse(String text) {
    final t = text.trim();
    final Object? root;
    try {
      root = jsonDecode(
        t.startsWith(_prefix)
            ? utf8.decode(
                gzip.decode(base64Url.decode(t.substring(_prefix.length))),
              )
            : t,
      );
    } on FormatException {
      throw const NotATeamPack();
    }
    if (root is! Map<String, Object?> || root['format'] != _format) {
      throw const NotATeamPack();
    }
    final version = root['formatVersion'];
    if (version is! int) throw const NotATeamPack();
    if (version > 1) throw const NotATeamPack(tooNew: true);
    final protocol = RadioProtocol.values.asNameMap()[root['protocol']];
    if (protocol == null) throw const NotATeamPack();
    return TeamPack(
      name: root['name'] is String ? root['name']! as String : '',
      protocol: protocol,
      channels: _channels(root['channels'], protocol),
      radio: _radio(root['radio'], protocol),
      places: _places(root['places']),
    );
  }

  static List<ChannelInvite> _channels(Object? raw, RadioProtocol protocol) {
    if (raw is! List<Object?>) return const [];
    final maxName = protocol == RadioProtocol.meshcore ? 31 : 11;
    final sizes = protocol == RadioProtocol.meshcore
        ? const {16}
        : const {0, 1, 16, 32};
    final out = <ChannelInvite>[];
    for (final c in raw.take(16)) {
      if (c is! Map<String, Object?>) continue;
      final name = c['n'];
      final secret = c['s'];
      if (name is! String || secret is! String || name.isEmpty) continue;
      if (utf8.encode(name).length > maxName) continue;
      try {
        final key = base64Decode(secret);
        if (!sizes.contains(key.length)) continue;
        out.add(ChannelInvite(protocol: protocol, name: name, secret: key));
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  static Map<String, num>? _radio(Object? raw, RadioProtocol protocol) {
    if (raw is! Map<String, Object?>) return null;
    bool within(String k, num lo, num hi) {
      final v = raw[k];
      return v is num && v >= lo && v <= hi;
    }

    final keys = protocol == RadioProtocol.meshcore
        ? const ['f', 'bw', 'sf', 'cr']
        : const ['region', 'usePreset', 'preset', 'hops', 'slot'];
    final ok = protocol == RadioProtocol.meshcore
        ? within('f', 150, 2500) &&
              MeshCoreSettings.bandwidths.any((b) => b == raw['bw']) &&
              within('sf', 5, 12) &&
              within('cr', 5, 8)
        : within('region', 1, 64) &&
              within('usePreset', 0, 1) &&
              within('preset', 0, 16) &&
              within('hops', 1, 7) &&
              within('slot', 0, 1024);
    return ok ? {for (final k in keys) k: raw[k]! as num} : null;
  }

  static List<Place> _places(Object? raw) {
    if (raw is! List<Object?>) return const [];
    final out = <Place>[];
    for (final p in raw.take(maxPackPlaces)) {
      if (p is! Map<String, Object?>) continue;
      final kind = PlaceKind.values.asNameMap()[p['k']];
      final name = p['n'];
      final pts = p['p'];
      if (kind == null || name is! String || pts is! List<Object?>) continue;
      final points = <GeoPoint>[];
      for (final x in pts.take(maxRoutePoints)) {
        if (x is! List<Object?> || x.length < 2) continue;
        final (la, lo) = (x[0], x[1]);
        if (la is num && lo is num && la.abs() <= 90 && lo.abs() <= 180) {
          points.add(GeoPoint(la.toDouble(), lo.toDouble()));
        }
      }
      final r = p['r'];
      final radius = r is num ? r.toDouble() : null;
      final valid = switch (kind) {
        PlaceKind.waypoint => points.isNotEmpty,
        PlaceKind.route => points.length >= 2,
        PlaceKind.geofence =>
          points.isNotEmpty &&
              radius != null &&
              radius >= 10 &&
              radius <= 100000,
      };
      if (valid) {
        out.add(Place(kind: kind, name: name, points: points, radiusM: radius));
      }
    }
    return out;
  }
}

/// What applying a pack did.
class TeamPackResult {
  const TeamPackResult(this.channels, this.channelsFull, this.places);
  final int channels;

  /// Channels left out because the radio has no free slot.
  final int channelsFull;
  final int places;
}

/// Builds a pack from [c]'s current channels and radio settings. The open
/// default channel is left out, since everyone already has it.
Future<TeamPack> buildTeamPack(
  RadioConnection c,
  MeshStore store, {
  required String name,
  required bool includeChannels,
  required bool includeRadio,
  required bool includePlaces,
}) async {
  Map<String, num>? radio;
  if (includeRadio && c is MeshCoreConnection) {
    final s = c.settings;
    if (s != null) {
      radio = {
        'f': s.frequencyMHz,
        'bw': s.bandwidthKHz,
        'sf': s.spreadingFactor,
        'cr': s.codingRate,
      };
    }
  } else if (includeRadio && c is MeshtasticConnection) {
    final lora = (await c.loadSettings())[SectionKind.lora];
    radio = {
      'region': lora.number(LoraField.region),
      'usePreset': lora.flag(LoraField.usePreset) ? 1 : 0,
      'preset': lora.number(LoraField.modemPreset),
      'hops': lora.number(LoraField.hopLimit),
      'slot': lora.number(LoraField.channelNum),
    };
  }
  return TeamPack(
    name: name,
    protocol: c.protocol,
    channels: !includeChannels
        ? const []
        : [
            for (final s in await c.channelSlots())
              if (!s.isPrimary &&
                  hexOf(s.invite.secret) != meshCorePublicKeyHex)
                s.invite,
          ],
    radio: radio,
    places: includePlaces
        ? (await store.watchPlaces().first).take(maxPackPlaces).toList()
        : const [],
  );
}

/// Applies the chosen parts of [pack] to [c]. Radio settings go last, as
/// the radio may restart.
Future<TeamPackResult> applyTeamPack(
  RadioConnection c,
  MeshStore store,
  TeamPack pack, {
  required bool channels,
  required bool radio,
  required bool places,
}) async {
  final sameMesh = pack.protocol == c.protocol;
  var added = 0;
  var full = 0;
  if (channels && sameMesh) {
    for (final invite in pack.channels) {
      try {
        await c.addChannel(invite);
        added++;
      } on ChannelsFull {
        full++;
      }
    }
  }
  if (places) await store.addPlaces(pack.places);
  final r = pack.radio;
  if (radio && sameMesh && r != null) {
    if (c is MeshCoreConnection) {
      final now = c.settings;
      if (now == null) throw StateError('Not connected');
      await c.applySettings(
        now.copyWith(
          frequencyMHz: r['f']!.toDouble(),
          bandwidthKHz: r['bw']!.toDouble(),
          spreadingFactor: r['sf']!.toInt(),
          codingRate: r['cr']!.toInt(),
        ),
      );
    } else if (c is MeshtasticConnection) {
      final s = await c.loadSettings();
      await c.saveSettings(
        s
            .withValue(SectionKind.lora, LoraField.region, r['region']!.toInt())
            .withValue(
              SectionKind.lora,
              LoraField.usePreset,
              r['usePreset'] != 0,
            )
            .withValue(
              SectionKind.lora,
              LoraField.modemPreset,
              r['preset']!.toInt(),
            )
            .withValue(SectionKind.lora, LoraField.hopLimit, r['hops']!.toInt())
            .withValue(
              SectionKind.lora,
              LoraField.channelNum,
              r['slot']!.toInt(),
            ),
      );
    }
  }
  return TeamPackResult(added, full, places ? pack.places.length : 0);
}
