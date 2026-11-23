/// Coverage mapping: what the radio hears, grouped into H3 hexagons and
/// 15-minute slots, and the signed report the NOTORYX coverage map reads.
///
/// Everything here is plain Dart so it can be tested without a radio, GPS
/// or the H3 library: the cell of a position is worked out by the caller.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../meshcore/bytes.dart';
import '../meshcore/raw_packet.dart';

/// The NOTORYX coverage map.
const coverageSiteUrl = 'https://coverage.meshmayhem.org/';
const coverageReportUrl = 'https://coverage.meshmayhem.org/v1/reports';
const coverageEraseUrl = 'https://coverage.meshmayhem.org/v1/erase';

const coverageReportFormat = 'notoryx-coverage-hex/1';
const coverageSignedFormat = 'notoryx-coverage-signed/1';
const coverageEraseFormat = 'notoryx-coverage-erase/1';

/// H3 resolution of every cell (about 0.7 km² each).
const coverageResolution = 8;

/// Readings are grouped into slots this long, in UTC.
const coverageSlot = Duration(minutes: 15);

/// How long readings stay on the phone.
const coverageKeep = Duration(days: 7);

/// A position fix is only used when it is this good and this fresh.
const coverageMaxAccuracyMetres = 200.0;
const coverageMaxFixAge = Duration(seconds: 30);

/// Most cells in one upload.
const coverageCellsPerReport = 50;

/// Most repeaters listed in one upload.
const coverageMaxRepeaters = 500;

/// Distinct cells hidden at each end of a mapping session.
const coverageHiddenEnds = 2;

/// How long after a slot closes it may be shared.
enum CoveragePrivacy {
  /// As soon as the slot closes.
  live(Duration.zero),

  /// Three hours later (the default).
  delayed(Duration(hours: 3)),

  /// A day later, with no key, no signatures and the time rounded to the day.
  anonymous(Duration(hours: 24));

  const CoveragePrivacy(this.delay);
  final Duration delay;

  static CoveragePrivacy parse(String? name) =>
      values.where((p) => p.name == name).firstOrNull ?? delayed;
}

/// The start of the 15-minute UTC slot [time] falls in.
DateTime coverageSlotOf(DateTime time) {
  final t = time.toUtc();
  return DateTime.utc(
    t.year,
    t.month,
    t.day,
    t.hour,
    t.minute - t.minute % coverageSlot.inMinutes,
  );
}

/// One cell during one slot: how much was heard and how well.
class CoverageReading {
  CoverageReading({
    required this.cell,
    required this.slot,
    this.count = 0,
    this.bestSnr = -1000,
    this.bestRssi = -1000,
    Map<String, double>? repeaters,
  }) : repeaters = repeaters ?? {};

  /// H3 cell index as lower-case hex.
  final String cell;

  /// Start of the slot, UTC.
  final DateTime slot;
  int count;
  double bestSnr;
  int bestRssi;

  /// Repeaters heard directly here (hop hash hex) and their best SNR.
  final Map<String, double> repeaters;

  /// Identifies the reading: cell and slot.
  String get id => coverageReadingId(cell, slot);

  /// When the slot ends and the reading stops changing.
  DateTime get closes => slot.add(coverageSlot);

  /// Whether the reading may be shared at [now] with [privacy].
  bool isDue(CoveragePrivacy privacy, DateTime now) =>
      !closes.add(privacy.delay).isAfter(now.toUtc());

  void add({required double snr, required int rssi, String? repeater}) {
    count++;
    if (snr > bestSnr) bestSnr = snr;
    if (rssi > bestRssi) bestRssi = rssi;
    if (repeater != null) {
      final was = repeaters[repeater];
      if (was == null || snr > was) repeaters[repeater] = snr;
    }
  }

  Map<String, Object?> toJson() => {
    'cell': cell,
    'slot': slot.toIso8601String(),
    'count': count,
    'snr': bestSnr,
    'rssi': bestRssi,
    'repeaters': repeaters,
  };

  static CoverageReading? fromJson(Object? json) {
    if (json is! Map) return null;
    final cell = json['cell'];
    final slot = DateTime.tryParse('${json['slot']}');
    final count = json['count'];
    final snr = json['snr'];
    final rssi = json['rssi'];
    final reps = json['repeaters'];
    if (cell is! String ||
        slot == null ||
        count is! int ||
        snr is! num ||
        rssi is! int ||
        reps is! Map) {
      return null;
    }
    return CoverageReading(
      cell: cell,
      slot: slot.toUtc(),
      count: count,
      bestSnr: snr.toDouble(),
      bestRssi: rssi,
      repeaters: {
        for (final e in reps.entries)
          if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      },
    );
  }
}

String coverageReadingId(String cell, DateTime slot) =>
    '$cell@${coverageSlotOf(slot).toIso8601String()}';

/// Every reading on the phone, keyed by [CoverageReading.id].
class CoverageLog {
  final Map<String, CoverageReading> readings = {};

  void record({
    required String cell,
    required DateTime time,
    required double snr,
    required int rssi,
    String? repeater,
  }) {
    final slot = coverageSlotOf(time);
    readings
        .putIfAbsent(
          coverageReadingId(cell, slot),
          () => CoverageReading(cell: cell, slot: slot),
        )
        .add(snr: snr, rssi: rssi, repeater: repeater);
  }

  /// Forgets readings older than [coverageKeep].
  void trim(DateTime now) => readings.removeWhere(
    (_, r) => now.toUtc().difference(r.slot) > coverageKeep,
  );

  /// The best SNR heard in each cell, for the map.
  Map<String, double> bestSnrByCell() {
    final out = <String, double>{};
    for (final r in readings.values) {
      final was = out[r.cell];
      if (was == null || r.bestSnr > was) out[r.cell] = r.bestSnr;
    }
    return out;
  }

  List<Object?> toJson() => [for (final r in readings.values) r.toJson()];

  void load(Object? json) {
    readings.clear();
    if (json is! List) return;
    for (final item in json) {
      final r = CoverageReading.fromJson(item);
      if (r != null) readings[r.id] = r;
    }
  }
}

/// MeshCore advert type byte for a repeater.
const _advertRepeater = 2;

/// The repeater our radio heard [raw] from directly, as hop hash hex, or
/// null. A flooded packet's last path hash is the repeater that passed it to
/// us; a zero-hop repeater advert came straight from that repeater (its
/// one-byte hash is the first byte of its key).
String? heardDirectlyFrom(Uint8List raw) {
  final info = MeshCorePacketInfo.parse(raw);
  if (info == null || !info.isFlood) return null;
  if (info.hops > 0) {
    final size = info.hashSize;
    return toHex(info.path.sublist(info.path.length - size));
  }
  // Advert: 32-byte key, 4-byte time, 64-byte signature, then flags.
  final body = info.body;
  if (info.payload == MeshCorePayload.advert &&
      body.length > 100 &&
      body[100] & 0x0f == _advertRepeater) {
    return toHex(body.sublist(0, 1));
  }
  return null;
}

/// The time a reading is shared with: its slot, or the day for anonymous.
DateTime coverageSharedTime(CoverageReading r, CoveragePrivacy privacy) =>
    privacy == CoveragePrivacy.anonymous
    ? DateTime.utc(r.slot.year, r.slot.month, r.slot.day)
    : r.slot;

double _twoPlaces(double v) => (v * 100).roundToDouble() / 100;

/// One cell as uploaded, without its signature.
Map<String, Object?> coverageCellJson(
  CoverageReading r,
  CoveragePrivacy privacy,
) => {
  'cell': r.cell,
  // Slots start on whole minutes, so this reads like 2026-11-22T09:15:00.000Z.
  'time': coverageSharedTime(r, privacy).toIso8601String(),
  'count': r.count,
  'best_snr': _twoPlaces(r.bestSnr),
  'best_rssi': r.bestRssi,
  'repeaters': [
    for (final e in r.repeaters.entries)
      {'id': e.key, 'snr': _twoPlaces(e.value)},
  ],
};

/// [value] as canonical JSON: keys sorted, no spaces, and numbers with no
/// fraction written as integers, so every platform signs the same bytes.
String canonicalJson(Object? value) {
  if (value is Map) {
    final keys = [for (final k in value.keys) '$k']..sort();
    return '{${[for (final k in keys) '${jsonEncode(k)}:${canonicalJson(value[k])}'].join(',')}}';
  }
  if (value is List) return '[${value.map(canonicalJson).join(',')}]';
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return jsonEncode(value);
}

/// The bytes a cell's signature covers.
Uint8List coverageCellSigningBytes(Map<String, Object?> cell) {
  final copy = Map<String, Object?>.of(cell)..remove('sig');
  final reps = copy['repeaters'];
  if (reps is List) {
    copy['repeaters'] = [...reps]
      ..sort((a, b) => '${(a as Map)['id']}'.compareTo('${(b as Map)['id']}'));
  }
  return Uint8List.fromList(
    utf8.encode('$coverageSignedFormat\n${canonicalJson(copy)}'),
  );
}

/// A MeshCore repeater's own public advert, sent so the map can name hop
/// hashes. Never the phone's position.
class CoverageRepeater {
  const CoverageRepeater({
    required this.keyHex,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.advert,
  });

  final String keyHex;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime advert;

  Map<String, Object?> toJson() => {
    'key': keyHex.toLowerCase(),
    'name': name,
    'lat': latitude,
    'lon': longitude,
    'advert': advert.toUtc().toIso8601String(),
  };
}

/// Keeps the start and end of each mapping session off the map, so nobody
/// can tell where a drive began or ended (often someone's home).
///
/// The first [coverageHiddenEnds] distinct cells of a session are private
/// from the moment they are seen. The last ones are held back while mapping
/// (the session may end there) and become private when it stops.
class CoverageEnds {
  final List<String> first = [];

  /// Cells in the order last visited, most recent last.
  final List<String> visited = [];
  DateTime? started;

  /// Reading IDs that never leave the phone.
  final Set<String> private = {};

  bool get active => started != null;

  void start(DateTime now) {
    first.clear();
    visited.clear();
    started = now.toUtc();
  }

  /// Notes that a reading was taken in [cell] at [time].
  void saw(String cell, DateTime time) {
    if (!active) return;
    if (visited.isEmpty || visited.last != cell) {
      visited
        ..remove(cell)
        ..add(cell);
    }
    if (first.length < coverageHiddenEnds && !first.contains(cell)) {
      first.add(cell);
    }
    if (first.contains(cell)) private.add(coverageReadingId(cell, time));
  }

  /// The most recently visited cells, as many as are hidden.
  Iterable<String> get _last =>
      visited.skip(max(0, visited.length - coverageHiddenEnds));

  /// Cells held back while the session is still going.
  Set<String> get held => active ? _last.toSet() : const {};

  /// Ends the session: every reading of it in the first or last cells
  /// becomes private.
  void stop(Iterable<CoverageReading> readings) {
    final from = started;
    if (from != null && visited.isNotEmpty) {
      final ends = {...first, ..._last};
      final since = coverageSlotOf(from);
      for (final r in readings) {
        if (ends.contains(r.cell) && !r.slot.isBefore(since)) {
          private.add(r.id);
        }
      }
    }
    first.clear();
    visited.clear();
    started = null;
  }

  Map<String, Object?> toJson() => {
    'private': private.toList(),
    if (started != null)
      'session': {
        'started': started!.toIso8601String(),
        'first': first,
        'visited': visited,
      },
  };

  /// Loads saved state. A session still open (the app closed mid-drive) is
  /// ended at once, against [readings].
  void load(Object? json, Iterable<CoverageReading> readings) {
    private.clear();
    first.clear();
    visited.clear();
    started = null;
    if (json is! Map) return;
    final p = json['private'];
    if (p is List) private.addAll(p.whereType<String>());
    final s = json['session'];
    if (s is Map) {
      final at = DateTime.tryParse('${s['started']}');
      if (at != null) {
        started = at.toUtc();
        first.addAll((s['first'] as List? ?? const []).whereType<String>());
        visited.addAll((s['visited'] as List? ?? const []).whereType<String>());
        stop(readings);
      }
    }
  }
}
