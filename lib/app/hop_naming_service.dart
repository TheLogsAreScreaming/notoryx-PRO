import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../mesh/hop_naming.dart';
import '../mesh/model.dart';
import '../mesh/signal.dart';

/// Keeps the [HopNaming] settings and picks saved, and looks up unknown
/// repeater IDs online when that's turned on. Only the IDs are sent.
class HopNamingService extends ChangeNotifier {
  HopNamingService({
    required Future<String?> Function(String name) read,
    required Future<void> Function(String name, String value) write,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : _read = read,
       _write = write,
       _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now {
    unawaited(_load());
  }

  final Future<String?> Function(String name) _read;
  final Future<void> Function(String name, String value) _write;
  final http.Client _http;
  final DateTime Function() _clock;

  HopNaming _value = HopNaming();
  final _asked = <String>{};
  final _pending = <String>{};
  GeoPoint? _near;
  Timer? _batch;
  Timer? _saveSoon;
  bool _disposed = false;

  HopNaming get value => _value;

  Future<void> _load() async {
    final raw = await _read(HopNaming.prefName);
    if (raw == null || _disposed) return;
    try {
      _value = HopNaming.fromJson(jsonDecode(raw));
      _changed();
    } on FormatException {
      // Unreadable: keep the defaults.
    }
  }

  Future<void> _save() =>
      _write(HopNaming.prefName, jsonEncode(_value.toJson(_clock())));

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _set(HopNaming next) async {
    _value = next;
    _changed();
    await _save();
  }

  Future<void> setOnline(bool on) => _set(_value.copyWith(online: on));

  /// Changes the lookup server; ignored unless it's an https address.
  Future<void> setServer(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.isScheme('https') || u.host.isEmpty) return;
    _asked.clear();
    await _set(_value.copyWith(server: url.trim(), forgetFound: true));
  }

  Future<void> setTieDays(int days) => _set(_value.copyWith(tieDays: days));

  Future<void> setTieMargin(int percent) =>
      _set(_value.copyWith(tieMargin: percent));

  Future<void> forgetPicks() => _set(_value.copyWith(forgetPicks: true));

  /// [target]'s route as named repeaters (see [resolveRoute]), walking
  /// from your radio at [from]. Looks up unknown IDs and saves new picks
  /// afterwards; safe to call while building.
  List<RouteHop> resolve(Node target, Iterable<Node> known, {GeoPoint? from}) {
    final hops = resolveRoute(
      target,
      known,
      naming: _value,
      from: from,
      now: _clock(),
    );
    if (_value.unsaved) {
      _value.unsaved = false;
      picksChanged();
    }
    want([
      for (final h in hops)
        if (h.node == null && h.onlineName == null) h.prefix,
    ], near: from);
    return hops;
  }

  /// Saves picks made while resolving routes, a little later.
  void picksChanged() {
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(seconds: 5), () {
      if (!_disposed) unawaited(_save());
    });
  }

  /// Looks up [ids] online, once each, when that's turned on. A name is
  /// kept only for a repeater within range of [near] (or, without a
  /// position, when the server is sure). Safe to call while building.
  void want(Iterable<String> ids, {GeoPoint? near}) {
    if (!_value.online || _disposed) return;
    _near = near ?? _near;
    for (final id in ids) {
      final hex = id.toLowerCase();
      if (_asked.add(hex)) _pending.add(hex);
    }
    if (_pending.isNotEmpty) {
      _batch ??= Timer(const Duration(milliseconds: 400), _lookUp);
    }
  }

  Future<void> _lookUp() async {
    _batch = null;
    final ids = _pending.toList();
    _pending.clear();
    if (ids.isEmpty || _disposed) return;
    final uri = Uri.parse(_value.server).replace(
      path: '/api/resolve-hops',
      queryParameters: {'hops': ids.map((i) => i.toUpperCase()).join(',')},
    );
    Object? reply;
    try {
      final r = await _http.get(uri).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) reply = jsonDecode(r.body);
    } on Object {
      reply = null;
    }
    if (_disposed) return;
    if (reply == null) {
      _asked.removeAll(ids); // try again next time
      return;
    }
    var any = false;
    for (final id in ids) {
      final name = onlineHopName(reply, id, you: _near);
      if (name != null) {
        _value.found[id] = name;
        any = true;
      }
    }
    if (any) _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _batch?.cancel();
    _saveSoon?.cancel();
    _http.close();
    super.dispose();
  }
}
