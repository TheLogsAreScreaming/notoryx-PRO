import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/map_tiles.dart';

final mc = RadioId.meshcore('aa' * 32);
String key(String prefix) => prefix + '0' * (64 - prefix.length);

class FakeCache implements MapCachingProvider {
  CachedMapTile? tile;
  final puts = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async => tile;

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async => puts.add(url);
}

void main() {
  test('signal bars from SNR', () {
    expect(signalBars(const PathFacts()), isNull);
    expect(signalBars(const PathFacts(snr: 9)), 4);
    expect(signalBars(const PathFacts(snr: 0)), 3);
    expect(signalBars(const PathFacts(snr: -4.75)), 2);
    expect(signalBars(const PathFacts(snr: -10)), 1);
    expect(signalBars(const PathFacts(snr: -15)), 0);
  });

  group('MeshCore routes', () {
    final peakA = Node(
      key: NodeKey.meshcore(key('a1')),
      radioId: mc,
      name: 'Peak A',
      kind: NodeKind.relay,
      position: const GeoPoint(46, -121),
    );
    final ridge = Node(
      key: NodeKey.meshcore(key('b2')),
      radioId: mc,
      name: 'Ridge',
      kind: NodeKind.relay,
    );
    final clashOne = Node(
      key: NodeKey.meshcore(key('c3aa')),
      radioId: mc,
      name: 'C1',
    );
    final clashTwo = Node(
      key: NodeKey.meshcore(key('c3bb')),
      radioId: mc,
      name: 'C2',
    );
    final elsewhere = Node(
      key: NodeKey.meshcore(key('d4')),
      radioId: RadioId.meshcore('bb' * 32),
      name: 'Other radio',
    );

    test('hops resolve only to a unique repeater on the same radio', () {
      final target = Node(
        key: NodeKey.meshcore(key('ee')),
        radioId: mc,
        name: 'Friend',
        path: const PathFacts(hops: 4, route: RouteKind.direct),
        route: const [0xa1, 0xb2, 0xc3, 0xd4],
      );
      final hops = resolveRoute(target, [
        peakA,
        ridge,
        clashOne,
        clashTwo,
        elsewhere,
      ]);
      expect(hops.map((h) => h.prefix), ['a1', 'b2', 'c3', 'd4']);
      expect(hops.map((h) => h.node?.name), ['Peak A', 'Ridge', null, null]);
    });

    test('two-byte hashes are read two at a time', () {
      final target = Node(
        key: NodeKey.meshcore(key('ee')),
        radioId: mc,
        name: 'Friend',
        path: const PathFacts(hops: 1),
        route: const [0xc3, 0xbb],
      );
      expect(target.routeHashSize, 2);
      final hops = resolveRoute(target, [clashOne, clashTwo]);
      expect(hops.single.prefix, 'c3bb');
      expect(hops.single.node?.name, 'C2');
    });

    test('no route, no hops', () {
      expect(resolveRoute(peakA, [ridge]), isEmpty);
    });

    test('routes survive the database', () async {
      final store = MeshStore.memory();
      final n = Node(
        key: NodeKey.meshcore(key('ee')),
        radioId: mc,
        name: 'Friend',
        path: const PathFacts(hops: 2, route: RouteKind.direct),
        route: const [0xa1, 0xb2],
      );
      await store.upsertNode(n);
      expect((await store.node(mc, n.key))!.route, [0xa1, 0xb2]);
      await store.upsertNode(n.copyWith(route: const []));
      expect((await store.node(mc, n.key))!.route, isEmpty);
      await store.close();
    });
  });

  group('offline map tiles', () {
    CachedMapTile staleTile() => (
      bytes: Uint8List.fromList([1, 2, 3]),
      metadata: CachedMapTileMetadata(
        staleAt: DateTime.timestamp().subtract(const Duration(days: 3)),
        lastModified: null,
        etag: 'v1',
      ),
    );

    test('online: stale tiles stay stale so the server is asked', () async {
      final fake = FakeCache()..tile = staleTile();
      final cache = OfflineFriendlyCache(fake, NetworkStatus());
      expect((await cache.getTile('u'))!.metadata.isStale, isTrue);
    });

    test('offline: stale tiles are shown as fresh', () async {
      final fake = FakeCache()..tile = staleTile();
      final status = NetworkStatus()..markFailure();
      final cache = OfflineFriendlyCache(fake, status);
      final tile = (await cache.getTile('u'))!;
      expect(tile.metadata.isStale, isFalse);
      expect(tile.metadata.etag, 'v1');
      expect(tile.bytes, [1, 2, 3]);
      await cache.putTile(url: 'u', metadata: tile.metadata);
      expect(fake.puts, ['u']);
    });

    test('offline lasts two minutes after the last failure', () {
      var now = DateTime(2026, 11, 7, 12);
      final status = NetworkStatus(clock: () => now)..markFailure();
      expect(status.offline, isTrue);
      now = now.add(const Duration(minutes: 3));
      expect(status.offline, isFalse);
      status
        ..markFailure()
        ..markSuccess();
      expect(status.offline, isFalse);
    });

    test('the client notices when the network is unreachable', () async {
      final status = NetworkStatus();
      final down = StatusClient(
        MockClient((_) async => throw const SocketException('no route')),
        status,
      );
      await expectLater(
        down.get(Uri.parse('https://tile.example/1/1/1.png')),
        throwsA(isA<SocketException>()),
      );
      expect(status.offline, isTrue);

      final up = StatusClient(
        MockClient((_) async => http.Response('ok', 200)),
        status,
      );
      await up.get(Uri.parse('https://tile.example/1/1/1.png'));
      expect(status.offline, isFalse);
    });
  });
}
