import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../mesh/coverage.dart';

/// A position fix from the phone.
@immutable
class CoverageFix {
  const CoverageFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.time,
  });

  final double latitude;
  final double longitude;
  final double accuracyMetres;
  final DateTime time;

  /// Whether the fix is good enough to place a packet heard at [at].
  bool usableAt(DateTime at) =>
      accuracyMetres <= coverageMaxAccuracyMetres &&
      at.difference(time).abs() <= coverageMaxFixAge;
}

/// What the phone offers coverage mapping: position fixes, H3 cells, the
/// network type and the repeaters the radios know. Swapped out in tests.
abstract interface class CoverageSources {
  /// Position fixes while mapping. Errors mean location is off or denied.
  Stream<CoverageFix> fixes();

  /// The resolution-8 H3 cell at a position, as lower-case hex.
  String cellAt(double latitude, double longitude);

  /// Corners of [cell], as (latitude, longitude) pairs.
  List<(double, double)> cellOutline(String cell);

  /// Whether the phone is on Wi-Fi (or a wired network) now.
  Future<bool> onWifi();

  /// MeshCore repeaters with an advertised position, newest first.
  Future<List<CoverageRepeater>> repeaters();
}

typedef CoverageRead = Future<String?> Function(String name);
typedef CoverageWrite = Future<void> Function(String name, String value);

/// Why mapping isn't recording.
enum CoverageProblem { locationOff }

/// How the last upload went.
sealed class CoverageUpload {
  const CoverageUpload(this.at);
  final DateTime at;
}

final class CoverageUploaded extends CoverageUpload {
  const CoverageUploaded(super.at, this.cells);
  final int cells;
}

final class CoverageRefused extends CoverageUpload {
  const CoverageRefused(super.at, this.status);
  final int status;
}

final class CoverageUnreachable extends CoverageUpload {
  const CoverageUnreachable(super.at);
}

final class CoverageWaitingForWifi extends CoverageUpload {
  const CoverageWaitingForWifi(super.at);
}

/// Records MeshCore coverage while the user maps and, if they agreed,
/// shares it with the NOTORYX coverage map.
///
/// Mapping and sharing are both off by default. Nothing goes over the
/// network until the user agrees to share.
class CoverageMapper extends ChangeNotifier {
  CoverageMapper({
    required CoverageRead read,
    required CoverageWrite write,
    required this.sources,
    http.Client? httpClient,
    DateTime Function()? now,
    this.reportUrl = coverageReportUrl,
    this.eraseUrl = coverageEraseUrl,
  }) : _read = read,
       _write = write,
       _http = httpClient,
       _now = now ?? DateTime.now;

  final CoverageRead _read;
  final CoverageWrite _write;
  final CoverageSources sources;
  http.Client? _http;
  final DateTime Function() _now;
  final String reportUrl;
  final String eraseUrl;

  http.Client get _client => _http ??= http.Client();

  static const prefReadings = 'coverage.readings';
  static const prefEnds = 'coverage.ends';
  static const prefSent = 'coverage.sent';
  static const prefSharing = 'coverage.sharing';
  static const prefPrivacy = 'coverage.privacy';
  static const prefWifiOnly = 'coverage.wifi_only';
  static const prefHideEnds = 'coverage.hide_ends';
  static const prefMapper = 'coverage.mapper_name';
  static const prefKey = 'coverage.key';

  static const uploadEvery = Duration(minutes: 2);
  static const _timeout = Duration(seconds: 15);
  static const maxMapperName = 40;

  final CoverageLog log = CoverageLog();
  final CoverageEnds ends = CoverageEnds();
  final Set<String> _sent = {};

  bool _sharing = false;
  CoveragePrivacy _privacy = CoveragePrivacy.delayed;
  bool _wifiOnly = true;
  bool _hideEnds = true;
  String _mapperName = '';
  bool _mapping = false;
  CoverageFix? _fix;
  CoverageProblem? _problem;
  CoverageUpload? _lastUpload;
  StreamSubscription<CoverageFix>? _fixes;
  Timer? _timer;
  Timer? _saveSoon;
  Future<void>? _uploading;
  bool _disposed = false;
  SimpleKeyPair? _keys;

  bool get mapping => _mapping;
  bool get sharing => _sharing;
  CoveragePrivacy get privacy => _privacy;
  bool get wifiOnly => _wifiOnly;
  bool get hideEnds => _hideEnds;
  String get mapperName => _mapperName;
  CoverageFix? get fix => _fix;
  CoverageProblem? get problem => _problem;
  CoverageUpload? get lastUpload => _lastUpload;

  /// Readings that would be shared once their delay has passed.
  int get waiting => _shareable().length;

  Future<String?> _get(String name) async {
    try {
      return await _read(name);
    } on Object {
      return null;
    }
  }

  Future<void> _set(String name, String value) async {
    try {
      await _write(name, value);
    } on Object {
      // Storage unavailable; kept for this session only.
    }
  }

  Object? _json(String? text) {
    if (text == null) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Loads saved readings and settings. A mapping session cut short by
  /// the app closing has its ends hidden now.
  Future<void> start() async {
    _sharing = await _get(prefSharing) == 'true';
    _privacy = CoveragePrivacy.parse(await _get(prefPrivacy));
    _wifiOnly = await _get(prefWifiOnly) != 'false';
    _hideEnds = await _get(prefHideEnds) != 'false';
    _mapperName = await _get(prefMapper) ?? '';
    log.load(_json(await _get(prefReadings)));
    log.trim(_now());
    final wasOpen = _json(await _get(prefEnds));
    ends.load(wasOpen, log.readings.values);
    final sent = _json(await _get(prefSent));
    if (sent is List) _sent.addAll(sent.whereType<String>());
    if (wasOpen is Map && wasOpen['session'] != null) await _save();
    if (_sharing) _schedule();
    _notify();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(uploadEvery, (_) => unawaited(upload()));
  }

  /// Starts or stops recording.
  Future<void> setMapping(bool on) async {
    if (on == _mapping) return;
    _mapping = on;
    _problem = null;
    if (on) {
      if (_hideEnds) ends.start(_now());
      _fixes = sources.fixes().listen(
        (f) {
          _fix = f;
          _problem = null;
          _notify();
        },
        onError: (Object _) {
          _problem = CoverageProblem.locationOff;
          _notify();
        },
      );
    } else {
      await _fixes?.cancel();
      _fixes = null;
      _fix = null;
      ends.stop(log.readings.values);
    }
    await _save();
    _notify();
    if (!on && _sharing) unawaited(upload());
  }

  /// Records a packet a MeshCore radio heard: [snr] dB, [rssi] dBm, [raw]
  /// the packet as heard on air.
  void heard({
    required double snr,
    required int rssi,
    required Uint8List raw,
    DateTime? at,
  }) {
    if (!_mapping) return;
    final fix = _fix;
    final time = at ?? _now();
    if (fix == null || !fix.usableAt(time)) return;
    final String cell;
    try {
      cell = sources.cellAt(fix.latitude, fix.longitude);
    } on Object {
      return;
    }
    if (_hideEnds) ends.saw(cell, time);
    log.record(
      cell: cell,
      time: time,
      snr: snr,
      rssi: rssi,
      repeater: heardDirectlyFrom(raw),
    );
    _saveSoon ??= Timer(const Duration(seconds: 20), () {
      _saveSoon = null;
      unawaited(_save());
    });
    _notify();
  }

  List<CoverageReading> _shareable() {
    final held = _hideEnds ? ends.held : const <String>{};
    return [
      for (final r in log.readings.values)
        if (r.repeaters.isNotEmpty &&
            !_sent.contains(r.id) &&
            !ends.private.contains(r.id) &&
            !held.contains(r.cell))
          r,
    ];
  }

  /// Sends every reading whose delay has passed. Does nothing unless the
  /// user agreed to share.
  Future<void> upload() async {
    // One at a time: a call made while another runs goes after it.
    for (var running = _uploading; running != null; running = _uploading) {
      await running;
    }
    final run = _uploading = _upload();
    try {
      await run;
    } finally {
      if (identical(_uploading, run)) _uploading = null;
    }
  }

  Future<void> _upload() async {
    if (!_sharing) return;
    final now = _now();
    log.trim(now);
    final due = [
      for (final r in _shareable())
        if (r.isDue(_privacy, now)) r,
    ];
    if (due.isEmpty) return;
    if (_wifiOnly && !await sources.onWifi()) {
      _lastUpload = CoverageWaitingForWifi(now);
      _notify();
      return;
    }
    for (var i = 0; i < due.length; i += coverageCellsPerReport) {
      final batch = due.sublist(i, min(i + coverageCellsPerReport, due.length));
      if (!await _post(batch)) break;
      _sent.addAll(batch.map((r) => r.id));
    }
    _sent.retainWhere(log.readings.containsKey);
    ends.private.retainWhere(log.readings.containsKey);
    await _save();
    _notify();
  }

  Future<bool> _post(List<CoverageReading> batch) async {
    final anonymous = _privacy == CoveragePrivacy.anonymous;
    final headers = {'Content-Type': 'application/json'};
    final String body;
    if (anonymous) {
      body = jsonEncode({
        'format': coverageReportFormat,
        'resolution': coverageResolution,
        'created': _now().toUtc().toIso8601String(),
        'cells': [for (final r in batch) coverageCellJson(r, _privacy)],
      });
    } else {
      final keys = await _keyPair();
      final key = base64Encode((await keys.extractPublicKey()).bytes);
      final cells = <Map<String, Object?>>[];
      for (final r in batch) {
        final cell = coverageCellJson(r, _privacy);
        cells.add({
          ...cell,
          'sig': await _sign(coverageCellSigningBytes(cell)),
        });
      }
      List<Map<String, Object?>> repeaters;
      try {
        repeaters = [
          for (final r in (await sources.repeaters()).take(
            coverageMaxRepeaters,
          ))
            r.toJson(),
        ];
      } on Object {
        repeaters = const [];
      }
      body = jsonEncode({
        'format': coverageReportFormat,
        'resolution': coverageResolution,
        'key': key,
        'created': _now().toUtc().toIso8601String(),
        if (_mapperName.isNotEmpty) 'mapper': _mapperName,
        'repeaters': repeaters,
        'cells': cells,
      });
      headers['X-Notoryx-Key'] = key;
      headers['X-Notoryx-Signature'] = await _sign(utf8.encode(body));
    }
    try {
      final res = await _client
          .post(Uri.parse(reportUrl), headers: headers, body: body)
          .timeout(_timeout);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      _lastUpload = ok
          ? CoverageUploaded(_now(), batch.length)
          : CoverageRefused(_now(), res.statusCode);
      return ok;
    } on Object {
      _lastUpload = CoverageUnreachable(_now());
      return false;
    }
  }

  /// The coverage key: its own Ed25519 key, made on first use. Never the
  /// radio's identity.
  Future<SimpleKeyPair> _keyPair() async {
    final have = _keys;
    if (have != null) return have;
    List<int>? seed;
    try {
      final saved = await _get(prefKey);
      if (saved != null) seed = base64Decode(saved);
    } on FormatException {
      seed = null;
    }
    if (seed == null || seed.length != 32) {
      final random = Random.secure();
      seed = [for (var i = 0; i < 32; i++) random.nextInt(256)];
      await _set(prefKey, base64Encode(seed));
    }
    return _keys = await Ed25519().newKeyPairFromSeed(seed);
  }

  Future<String> _sign(List<int> bytes) async => base64Encode(
    (await Ed25519().sign(bytes, keyPair: await _keyPair())).bytes,
  );

  /// The public coverage key, base64.
  Future<String> publicKey() async =>
      base64Encode((await (await _keyPair()).extractPublicKey()).bytes);

  /// Turns sharing on after the user agreed to what is sent.
  Future<void> startSharing() async {
    _sharing = true;
    await _set(prefSharing, 'true');
    _schedule();
    _notify();
    unawaited(upload());
  }

  /// Stops sharing. Readings stay on the phone; nothing more is sent.
  Future<void> stopSharing() async {
    _sharing = false;
    _timer?.cancel();
    _timer = null;
    await _set(prefSharing, 'false');
    _notify();
  }

  Future<void> setPrivacy(CoveragePrivacy value) async {
    _privacy = value;
    await _set(prefPrivacy, value.name);
    _notify();
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    await _set(prefWifiOnly, '$value');
    _notify();
  }

  Future<void> setHideEnds(bool value) async {
    _hideEnds = value;
    if (!value) ends.stop(const []);
    if (value && _mapping) ends.start(_now());
    await _set(prefHideEnds, '$value');
    _notify();
  }

  /// The name coverage map members see; empty for none.
  Future<void> setMapperName(String value) async {
    final clean = value.trim();
    _mapperName = String.fromCharCodes(clean.runes.take(maxMapperName));
    await _set(prefMapper, _mapperName);
    _notify();
  }

  /// Asks the coverage map to delete everything this phone's coverage key
  /// uploaded. Returns how many readings went, or null if it failed.
  /// Anonymous uploads carry no key, so they can't be found or erased.
  Future<int?> erase() async {
    final keys = await _keyPair();
    final body = jsonEncode({
      'format': coverageEraseFormat,
      'key': base64Encode((await keys.extractPublicKey()).bytes),
      'time': _now().toUtc().toIso8601String(),
    });
    try {
      final res = await _client
          .post(
            Uri.parse(eraseUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-Notoryx-Signature': await _sign(utf8.encode(body)),
            },
            body: body,
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final json = jsonDecode(res.body);
      final n = json is Map ? json['erased'] : null;
      return n is int ? n : 0;
    } on Object {
      return null;
    }
  }

  Future<void> _save() async {
    _saveSoon?.cancel();
    _saveSoon = null;
    await _set(prefReadings, jsonEncode(log.toJson()));
    await _set(prefEnds, jsonEncode(ends.toJson()));
    await _set(prefSent, jsonEncode(_sent.toList()));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @visibleForTesting
  set fixForTesting(CoverageFix fix) => _fix = fix;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _saveSoon?.cancel();
    unawaited(_fixes?.cancel());
    super.dispose();
  }
}
