import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:path_provider/path_provider.dart';

/// Remembers whether tile requests have recently failed for lack of network.
class NetworkStatus {
  NetworkStatus({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _lastFailure;
  final _back = StreamController<void>.broadcast(sync: true);

  /// How long one failure counts as "offline".
  static const window = Duration(minutes: 2);

  /// Whether the map should assume there's no internet right now.
  bool get offline =>
      _lastFailure != null && _clock().difference(_lastFailure!) < window;

  /// Fires when a download works again after a failure, so the map can
  /// fetch the tiles it left blank while the network was down.
  Stream<void> get backOnline => _back.stream;

  void markFailure() => _lastFailure = _clock();

  void markSuccess() {
    final wasDown = _lastFailure != null;
    _lastFailure = null;
    if (wasDown) _back.add(null);
  }
}

/// Tells tile layers when to fetch tiles again that they left blank.
///
/// A tile whose download fails stays blank until it is scrolled away. This
/// fires when downloads work again, and every [retryEvery] while the
/// network still looks down, so the map fills in by itself. The timer only
/// runs while something listens.
class TileReloader {
  TileReloader(this.status, {this.retryEvery = const Duration(seconds: 30)});

  final NetworkStatus status;
  final Duration retryEvery;
  StreamSubscription<void>? _back;
  Timer? _timer;

  late final StreamController<void> _reload = StreamController.broadcast(
    onListen: () {
      _back = status.backOnline.listen((_) => _reload.add(null));
      _timer = Timer.periodic(retryEvery, (_) {
        if (status.offline) _reload.add(null);
      });
    },
    onCancel: () {
      unawaited(_back?.cancel());
      _back = null;
      _timer?.cancel();
      _timer = null;
    },
  );

  /// Pass to `TileLayer.reset`.
  Stream<void> get stream => _reload.stream;
}

/// An HTTP client that reports network failures to [status].
class StatusClient extends http.BaseClient {
  StatusClient(this._inner, this.status);

  final http.Client _inner;
  final NetworkStatus status;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      status.markSuccess();
      return response;
    } on http.RequestAbortedException {
      // The map cancels downloads for tiles it no longer shows (after a
      // zoom or pan). That says nothing about the network.
      rethrow;
    } on SocketException {
      status.markFailure();
      rethrow;
    } on http.ClientException {
      status.markFailure();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

/// The HTTP client for map tiles.
///
/// A tile whose download fails is left blank by the map until it is
/// scrolled away, so a short network drop (for example while switching
/// between Wi-Fi and mobile data) could leave the map grey. Network errors
/// and server errors are retried a few times, with growing pauses, before
/// [status] hears about the failure.
http.Client tileHttpClient(
  http.Client inner,
  NetworkStatus status, {
  Duration Function(int retryCount)? delay,
}) => StatusClient(
  RetryClient(
    inner,
    retries: 3,
    when: (response) => response.statusCode >= 500,
    whenError: (error, _) =>
        error is SocketException || error is http.ClientException,
    delay: delay ?? (n) => Duration(milliseconds: 800 * (n + 1)),
  ),
  status,
);

/// Tile cache that follows the server's caching rules while online, but
/// shows saved tiles of any age when the network is unreachable.
///
/// Every tile viewed is kept (up to the cache size), so areas looked at
/// before a trip stay available in the backcountry. Bulk-downloading areas
/// from openstreetmap.org isn't allowed by its tile policy, so the app
/// doesn't offer it.
class OfflineFriendlyCache implements MapCachingProvider {
  OfflineFriendlyCache(this._delegate, this.status);

  final MapCachingProvider _delegate;
  final NetworkStatus status;

  @override
  bool get isSupported => _delegate.isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final tile = await _delegate.getTile(url);
    if (tile == null || !tile.metadata.isStale || !status.offline) return tile;
    return (
      bytes: tile.bytes,
      metadata: CachedMapTileMetadata(
        staleAt: DateTime.timestamp().add(NetworkStatus.window),
        lastModified: tile.metadata.lastModified,
        etag: tile.metadata.etag,
      ),
    );
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) => _delegate.putTile(url: url, metadata: metadata, bytes: bytes);
}

/// The map's tile source and cache.
class MapTiles {
  MapTiles._(this.provider, this.status);

  /// OpenStreetMap's standard tiles.
  static const urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Identifies the app to the tile server, as its policy asks.
  static const userAgentPackageName = 'com.bastionmesh.notoryx_pro';

  final TileProvider provider;
  final NetworkStatus status;

  /// When to fetch blank tiles again; pass to `TileLayer.reset`.
  late final Stream<void> reload = TileReloader(status).stream;

  /// Sets up the cache in the app's own storage (not a folder the system
  /// may clear), up to [maxBytes].
  static Future<MapTiles> create({int maxBytes = 500 * 1024 * 1024}) async {
    final dir = await getApplicationSupportDirectory();
    final status = NetworkStatus();
    final cache = OfflineFriendlyCache(
      BuiltInMapCachingProvider.getOrCreateInstance(
        cacheDirectory: '${dir.path}/map_tiles',
        maxCacheSize: maxBytes,
      ),
      status,
    );
    final provider = NetworkTileProvider(
      httpClient: tileHttpClient(http.Client(), status),
      cachingProvider: cache,
      silenceExceptions: true,
    );
    return MapTiles._(provider, status);
  }
}
