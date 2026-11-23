import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:h3_flutter/h3_flutter.dart';

import '../mesh/coverage.dart';
import '../mesh/mesh.dart';
import '../radio/radio_link.dart';
import '../store/mesh_store.dart';
import 'coverage_mapper.dart';

/// The phone's GPS, the H3 library, the network type and the stored
/// MeshCore repeaters. Nothing is touched until coverage mapping uses it.
class PhoneCoverageSources implements CoverageSources {
  PhoneCoverageSources(this.store);

  final MeshStore store;
  H3? _h3;

  H3 get _cells => _h3 ??= const H3Factory().load();

  @override
  Stream<CoverageFix> fixes() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabledException();
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
      throw const PermissionDeniedException('location');
    }
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).map(
      (pos) => CoverageFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMetres: pos.accuracy,
        time: pos.timestamp,
      ),
    );
  }

  @override
  String cellAt(double latitude, double longitude) => _cells
      .geoToCell(GeoCoord(lat: latitude, lon: longitude), coverageResolution)
      .toRadixString(16);

  @override
  List<(double, double)> cellOutline(String cell) => [
    for (final c in _cells.cellToBoundary(BigInt.parse(cell, radix: 16)))
      (c.lat, c.lon),
  ];

  /// Phones only: Wi-Fi is the interface named wlan* (Android) or en*
  /// (iOS) with a usable address; mobile data uses other names. Desktops
  /// are on Wi-Fi or a wired network.
  @override
  Future<bool> onWifi() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final wifiName = Platform.isAndroid ? 'wlan' : 'en';
    try {
      final interfaces = await NetworkInterface.list();
      return interfaces.any(
        (i) =>
            i.name.startsWith(wifiName) &&
            i.addresses.any((a) => !a.isLoopback && !a.isLinkLocal),
      );
    } on SocketException {
      return false;
    }
  }

  @override
  Future<List<CoverageRepeater>> repeaters() async {
    final seen = <String>{};
    final out = <CoverageRepeater>[];
    final nodes = [...await store.watchAllNodes().first]
      ..sort(
        (a, b) =>
            (b.lastHeard ?? DateTime(0)).compareTo(a.lastHeard ?? DateTime(0)),
      );
    for (final n in nodes) {
      final key = n.key.native.toLowerCase();
      final at = n.position;
      final heard = n.lastHeard;
      if (n.protocol != RadioProtocol.meshcore ||
          n.kind != NodeKind.relay ||
          at == null ||
          heard == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(key) ||
          !seen.add(key)) {
        continue;
      }
      out.add(
        CoverageRepeater(
          keyHex: key,
          name: n.name,
          latitude: at.latitude,
          longitude: at.longitude,
          advert: heard,
        ),
      );
      if (out.length >= coverageMaxRepeaters) break;
    }
    return out;
  }
}
