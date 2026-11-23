import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/app/coverage_mapper.dart';
import 'package:notoryx_pro/mesh/coverage.dart';

/// A cell in the open South Pacific (-40, -130): no real place.
const _ocean = '88c6ac0911fffff';

/// Test vectors made with the coverage map server's own signing code and
/// Node's Ed25519, from the seed 01 02 … 20.
const _vectorKey = 'ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=';
const _vectorInput =
    'notoryx-coverage-signed/1\n{"best_rssi":-91,"best_snr":7.25,'
    '"cell":"88c6ac0911fffff","count":3,"repeaters":[{"id":"a1","snr":6},'
    '{"id":"b2","snr":-3.5}],"time":"2026-11-22T09:15:00.000Z"}';
const _vectorSig =
    'r7gKcJEwDq8txsiIONofgRFBpiTdETDx0NzFSUMWv8C88pcYNJyQoPBI3HzbaxZ5t9bSqpazBcRXtyaEQAjgDQ==';

/// A flooded packet that came to us through [path] (1-byte hashes).
Uint8List _flood(List<int> path, {int hashSize = 1}) => Uint8List.fromList([
  0x01 | (5 << 2), // flood, channel message
  (path.length ~/ hashSize) | ((hashSize - 1) << 6),
  ...path,
  1, 2, 3, 4,
]);

/// A zero-hop advert from a node of [type] whose key starts with [first].
Uint8List _advert(int first, int type) => Uint8List.fromList([
  0x01 | (4 << 2), // flood, advert
  0,
  first,
  ...List.filled(31, 7), // rest of the key
  ...List.filled(4, 0), // time
  ...List.filled(64, 0), // signature
  0x80 | type, // flags
]);

class _FakeSources implements CoverageSources {
  final fixes$ = StreamController<CoverageFix>.broadcast();
  bool wifi = true;
  List<CoverageRepeater> known = const [];

  @override
  Stream<CoverageFix> fixes() => fixes$.stream;

  /// One cell per whole degree of latitude, so tests can walk through cells.
  @override
  String cellAt(double latitude, double longitude) =>
      latitude == -40 ? _ocean : 'cell${latitude.round()}';

  @override
  List<(double, double)> cellOutline(String cell) => const [];

  @override
  Future<bool> onWifi() async => wifi;

  @override
  Future<List<CoverageRepeater>> repeaters() async => known;
}

class _Rig {
  _Rig({Map<String, String>? prefs}) : prefs = prefs ?? {};

  final Map<String, String> prefs;
  final sources = _FakeSources();
  final requests = <http.Request>[];
  DateTime now = DateTime.utc(2026, 11, 22, 9, 20);
  int status = 200;
  String reply = '{"accepted":1}';

  late final mapper = CoverageMapper(
    read: (n) async => prefs[n],
    write: (n, v) async => prefs[n] = v,
    sources: sources,
    now: () => now,
    httpClient: MockClient((r) async {
      requests.add(r);
      return http.Response(reply, status);
    }),
  );

  /// Maps at latitude [lat] and hears one packet via repeater [hop].
  void hear(double lat, {int hop = 0xa1, double snr = 6, int rssi = -91}) {
    mapper.fixForTesting = CoverageFix(
      latitude: lat,
      longitude: -130,
      accuracyMetres: 10,
      time: now,
    );
    mapper.heard(snr: snr, rssi: rssi, raw: _flood([0x55, hop]), at: now);
  }

  List<Map<String, Object?>> get sentCells => [
    for (final r in requests)
      for (final c in (jsonDecode(r.body) as Map)['cells'] as List)
        Map<String, Object?>.from(c as Map),
  ];
}

Future<bool> _verify(String keyB64, List<int> data, String sigB64) =>
    Ed25519().verify(
      data,
      signature: Signature(
        base64Decode(sigB64),
        publicKey: SimplePublicKey(
          base64Decode(keyB64),
          type: KeyPairType.ed25519,
        ),
      ),
    );

void main() {
  group('canonical JSON and signatures', () {
    test('sorted keys, no spaces, integral numbers without a point', () {
      expect(
        canonicalJson({
          'b': [1.5, 2.0, 'x'],
          'a': {'z': null, 'y': true},
        }),
        '{"a":{"y":true,"z":null},"b":[1.5,2,"x"]}',
      );
    });

    test('a cell signs exactly as the server checks it', () async {
      final log = CoverageLog()
        ..record(
          cell: _ocean,
          time: DateTime.utc(2026, 11, 22, 9, 21),
          snr: 7.25,
          rssi: -95,
        )
        ..record(
          cell: _ocean,
          time: DateTime.utc(2026, 11, 22, 9, 29),
          snr: -3.5,
          rssi: -91,
          repeater: 'b2',
        )
        ..record(
          cell: _ocean,
          time: DateTime.utc(2026, 11, 22, 9, 15),
          snr: 6,
          rssi: -99,
          repeater: 'a1',
        );
      final reading = log.readings.values.single;
      final cell = coverageCellJson(reading, CoveragePrivacy.delayed);
      expect(cell['time'], '2026-11-22T09:15:00.000Z');
      expect(cell['count'], 3);
      final input = coverageCellSigningBytes(cell);
      expect(utf8.decode(input), _vectorInput);

      final keys = await Ed25519().newKeyPairFromSeed([
        for (var i = 1; i <= 32; i++) i,
      ]);
      expect(base64Encode((await keys.extractPublicKey()).bytes), _vectorKey);
      final sig = await Ed25519().sign(input, keyPair: keys);
      expect(base64Encode(sig.bytes), _vectorSig);
    });

    test('best SNR is rounded to 2 places', () {
      final r = CoverageReading(cell: _ocean, slot: DateTime.utc(2026))
        ..add(snr: 5.123456, rssi: -80);
      expect(coverageCellJson(r, CoveragePrivacy.live)['best_snr'], 5.12);
    });
  });

  group('recording', () {
    test('15-minute UTC slots', () {
      expect(
        coverageSlotOf(DateTime.utc(2026, 11, 22, 9, 44, 59)),
        DateTime.utc(2026, 11, 22, 9, 30),
      );
    });

    test('the repeater heard directly', () {
      expect(heardDirectlyFrom(_flood([0x11, 0x22])), '22');
      expect(
        heardDirectlyFrom(_flood([0x11, 0x12, 0xab, 0xcd], hashSize: 2)),
        'abcd',
      );
      expect(heardDirectlyFrom(_advert(0x9c, 2)), '9c');
      // A companion's advert, and a packet that came straight from its
      // sender, name no repeater.
      expect(heardDirectlyFrom(_advert(0x9c, 1)), isNull);
      expect(heardDirectlyFrom(_flood([])), isNull);
      // Direct routes carry the hops still to go.
      expect(heardDirectlyFrom(Uint8List.fromList([0x02, 1, 0x33, 9])), isNull);
    });

    test('needs an accurate, fresh fix and mapping turned on', () async {
      final rig = _Rig();
      rig.hear(-40);
      expect(rig.mapper.log.readings, isEmpty, reason: 'not mapping');
      await rig.mapper.setMapping(true);
      rig.mapper.fixForTesting = CoverageFix(
        latitude: -40,
        longitude: -130,
        accuracyMetres: 250,
        time: rig.now,
      );
      rig.mapper.heard(snr: 1, rssi: -90, raw: _flood([1]), at: rig.now);
      expect(rig.mapper.log.readings, isEmpty, reason: 'too inaccurate');
      rig.mapper.fixForTesting = CoverageFix(
        latitude: -40,
        longitude: -130,
        accuracyMetres: 20,
        time: rig.now.subtract(const Duration(seconds: 31)),
      );
      rig.mapper.heard(snr: 1, rssi: -90, raw: _flood([1]), at: rig.now);
      expect(rig.mapper.log.readings, isEmpty, reason: 'fix too old');
      rig.hear(-40, snr: 3);
      rig.hear(-40, snr: 8, hop: 0xb2);
      final r = rig.mapper.log.readings.values.single;
      expect(r.count, 2);
      expect(r.bestSnr, 8);
      expect(r.repeaters, {'a1': 3.0, 'b2': 8.0});
    });

    test('keeps 7 days', () {
      final log = CoverageLog()
        ..record(cell: 'a', time: DateTime.utc(2026, 11, 1), snr: 1, rssi: -1)
        ..record(cell: 'b', time: DateTime.utc(2026, 11, 20), snr: 1, rssi: -1);
      log.trim(DateTime.utc(2026, 11, 22));
      expect(log.readings.values.map((r) => r.cell), ['b']);
    });
  });

  group('hiding the ends of a drive', () {
    test('first 2 and last 2 cells never upload', () async {
      final rig = _Rig();
      await rig.mapper.start();
      await rig.mapper.setPrivacy(CoveragePrivacy.live);
      await rig.mapper.setMapping(true);
      for (final lat in <double>[1, 2, 3, 4, 2, 5, 6]) {
        rig.hear(lat);
      }
      // While mapping, the last 2 cells are held back too.
      expect(rig.mapper.waiting, 2, reason: 'cells 3 and 4');
      await rig.mapper.setMapping(false);
      await rig.mapper.startSharing();
      rig.now = rig.now.add(const Duration(minutes: 30));
      await rig.mapper.upload();
      expect(rig.sentCells.map((c) => c['cell']).toSet(), {'cell3', 'cell4'});
    });

    test('a session the app closed in the middle of is trimmed', () async {
      final first = _Rig();
      await first.mapper.start();
      await first.mapper.setMapping(true);
      for (final lat in <double>[1, 2, 3, 4, 5]) {
        first.hear(lat);
      }
      // The app closes mid-session.
      first.mapper.dispose();

      final again = _Rig(prefs: first.prefs);
      // What was saved (readings are saved at most 20 s after they're heard).
      again.prefs[CoverageMapper.prefReadings] = jsonEncode(
        first.mapper.log.toJson(),
      );
      again.prefs[CoverageMapper.prefEnds] = jsonEncode(
        first.mapper.ends.toJson(),
      );
      again.now = first.now.add(const Duration(hours: 5));
      await again.mapper.start();
      await again.mapper.startSharing();
      await again.mapper.upload();
      expect(again.sentCells.map((c) => c['cell']).toSet(), {'cell3'});
    });
  });

  group('uploading', () {
    test('nothing is sent until the user agrees', () async {
      final rig = _Rig();
      await rig.mapper.start();
      await rig.mapper.setMapping(true);
      rig.hear(10);
      await rig.mapper.setHideEnds(false);
      rig.now = rig.now.add(const Duration(days: 1));
      await rig.mapper.upload();
      expect(rig.requests, isEmpty);
    });

    test('signed report: headers, per-cell signatures, repeaters', () async {
      final rig = _Rig();
      rig.sources.known = [
        CoverageRepeater(
          keyHex: 'AB' * 32,
          name: 'Test repeater',
          latitude: -40.01,
          longitude: -130.02,
          advert: DateTime.utc(2026, 11, 21, 8),
        ),
      ];
      await rig.mapper.start();
      await rig.mapper.setHideEnds(false);
      await rig.mapper.setMapperName('  Test mapper  ');
      await rig.mapper.setMapping(true);
      rig.hear(-40);
      // Heard nowhere through a repeater: stays on the phone.
      rig.mapper.fixForTesting = CoverageFix(
        latitude: 20,
        longitude: -130,
        accuracyMetres: 10,
        time: rig.now,
      );
      rig.mapper.heard(snr: 2, rssi: -100, raw: _flood(const []), at: rig.now);
      await rig.mapper.startSharing();
      await rig.mapper.upload();
      expect(rig.requests, isEmpty, reason: 'delayed by 3 hours');

      rig.now = rig.now.add(const Duration(hours: 3, minutes: 10));
      await rig.mapper.upload();
      final req = rig.requests.single;
      expect(req.url.toString(), coverageReportUrl);
      final body = jsonDecode(req.body) as Map<String, Object?>;
      final key = body['key'] as String;
      expect(req.headers['X-Notoryx-Key'], key);
      expect(
        await _verify(
          key,
          utf8.encode(req.body),
          req.headers['X-Notoryx-Signature']!,
        ),
        isTrue,
      );
      expect(body['format'], 'notoryx-coverage-hex/1');
      expect(body['resolution'], 8);
      expect(body['mapper'], 'Test mapper');
      expect(body['repeaters'], [
        {
          'key': 'ab' * 32,
          'name': 'Test repeater',
          'lat': -40.01,
          'lon': -130.02,
          'advert': '2026-11-21T08:00:00.000Z',
        },
      ]);
      final cell = Map<String, Object?>.from(
        (body['cells'] as List).single as Map,
      );
      expect(cell['cell'], _ocean);
      expect(cell['time'], '2026-11-22T09:15:00.000Z');
      expect(
        await _verify(
          key,
          coverageCellSigningBytes(cell),
          cell['sig']! as String,
        ),
        isTrue,
      );
      // The key is the coverage key kept in prefs, and stays the same.
      expect(rig.prefs[CoverageMapper.prefKey], isNotNull);
      expect(await rig.mapper.publicKey(), key);

      // Sent once only.
      await rig.mapper.upload();
      expect(rig.requests, hasLength(1));
    });

    test('at most 50 cells per request', () async {
      final rig = _Rig();
      await rig.mapper.start();
      await rig.mapper.setHideEnds(false);
      await rig.mapper.setPrivacy(CoveragePrivacy.live);
      await rig.mapper.setMapping(true);
      for (var i = 0; i < 120; i++) {
        rig.hear(i.toDouble());
      }
      await rig.mapper.startSharing();
      rig.now = rig.now.add(const Duration(minutes: 15));
      await rig.mapper.upload();
      expect(
        [
          for (final r in rig.requests)
            ((jsonDecode(r.body) as Map)['cells'] as List).length,
        ],
        [50, 50, 20],
      );
      expect(rig.mapper.waiting, 0);
    });

    test('anonymous: no key, no signatures, the day only, 24 h late', () async {
      final rig = _Rig();
      await rig.mapper.start();
      await rig.mapper.setHideEnds(false);
      await rig.mapper.setMapperName('Hidden');
      await rig.mapper.setPrivacy(CoveragePrivacy.anonymous);
      await rig.mapper.setMapping(true);
      rig.hear(-40);
      await rig.mapper.startSharing();
      rig.now = rig.now.add(const Duration(hours: 23));
      await rig.mapper.upload();
      expect(rig.requests, isEmpty);
      rig.now = rig.now.add(const Duration(hours: 2));
      await rig.mapper.upload();
      final req = rig.requests.single;
      expect(req.headers.containsKey('X-Notoryx-Key'), isFalse);
      expect(req.headers.containsKey('X-Notoryx-Signature'), isFalse);
      final body = jsonDecode(req.body) as Map;
      expect(body.keys, isNot(contains('key')));
      expect(body.keys, isNot(contains('mapper')));
      expect(body.keys, isNot(contains('repeaters')));
      final cell = (body['cells'] as List).single as Map;
      expect(cell['time'], '2026-11-22T00:00:00.000Z');
      expect(cell.keys, isNot(contains('sig')));
    });

    test('waits for Wi-Fi when asked to', () async {
      final rig = _Rig();
      rig.sources.wifi = false;
      await rig.mapper.start();
      await rig.mapper.setHideEnds(false);
      await rig.mapper.setPrivacy(CoveragePrivacy.live);
      await rig.mapper.setMapping(true);
      rig.hear(-40);
      await rig.mapper.startSharing();
      rig.now = rig.now.add(const Duration(minutes: 15));
      await rig.mapper.upload();
      expect(rig.requests, isEmpty);
      expect(rig.mapper.lastUpload, isA<CoverageWaitingForWifi>());
      await rig.mapper.setWifiOnly(false);
      await rig.mapper.upload();
      expect(rig.requests, hasLength(1));
      expect(rig.mapper.lastUpload, isA<CoverageUploaded>());
    });

    test('a refused upload is tried again later', () async {
      final rig = _Rig()..status = 400;
      await rig.mapper.start();
      await rig.mapper.setHideEnds(false);
      await rig.mapper.setPrivacy(CoveragePrivacy.live);
      await rig.mapper.setMapping(true);
      rig.hear(-40);
      await rig.mapper.startSharing();
      rig.now = rig.now.add(const Duration(minutes: 15));
      await rig.mapper.upload();
      expect(rig.mapper.lastUpload, isA<CoverageRefused>());
      expect(rig.mapper.waiting, 1);
      rig.status = 200;
      await rig.mapper.upload();
      expect(rig.mapper.waiting, 0);
    });
  });

  group('erase', () {
    test('signed erase request, returns how many went', () async {
      final rig = _Rig()..reply = '{"erased":3}';
      await rig.mapper.start();
      expect(await rig.mapper.erase(), 3);
      final req = rig.requests.single;
      expect(req.url.toString(), coverageEraseUrl);
      final body = jsonDecode(req.body) as Map;
      expect(body['format'], 'notoryx-coverage-erase/1');
      expect(body['key'], await rig.mapper.publicKey());
      expect(body['time'], '2026-11-22T09:20:00.000Z');
      expect(
        await _verify(
          body['key'] as String,
          utf8.encode(req.body),
          req.headers['X-Notoryx-Signature']!,
        ),
        isTrue,
      );
    });

    test('null when the map says no', () async {
      final rig = _Rig()..status = 401;
      await rig.mapper.start();
      expect(await rig.mapper.erase(), isNull);
    });
  });
}
