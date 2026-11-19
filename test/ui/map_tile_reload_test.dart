import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notoryx_pro/ui/map_tiles.dart';

/// A 4x4 PNG, so a real tile can be told from flutter_map's 1x1
/// transparent placeholder.
final tilePng = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  4,
  0,
  0,
  0,
  4,
  8,
  6,
  0,
  0,
  0,
  169,
  241,
  158,
  126,
  0,
  0,
  0,
  18,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  207,
  192,
  240,
  31,
  25,
  51,
  144,
  46,
  0,
  0,
  60,
  64,
  31,
  225,
  224,
  129,
  119,
  180,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

/// Answers every request with [tilePng] after [delay], unless the request
/// is aborted first.
class SlowTileServer extends http.BaseClient {
  SlowTileServer({this.delay = const Duration(milliseconds: 50)});

  final Duration delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abort = request is http.Abortable ? request.abortTrigger : null;
    final aborted = Completer<bool>();
    unawaited(
      abort?.then((_) {
        if (!aborted.isCompleted) aborted.complete(true);
      }),
    );
    unawaited(
      Future<void>.delayed(delay).then((_) {
        if (!aborted.isCompleted) aborted.complete(false);
      }),
    );
    if (await aborted.future) throw http.RequestAbortedException(request.url);
    return http.StreamedResponse(
      Stream.value(tilePng),
      200,
      contentLength: tilePng.length,
    );
  }
}

/// Resolves [provider] and returns the width of the image it gives.
Future<int> widthOf(ImageProvider provider) {
  final done = Completer<int>();
  provider
      .resolve(ImageConfiguration.empty)
      .addListener(
        ImageStreamListener(
          (info, _) {
            if (!done.isCompleted) done.complete(info.image.width);
          },
          onError: (e, _) {
            if (!done.isCompleted) done.completeError(e);
          },
        ),
      );
  return done.future;
}

/// What the map does when its size changes right after a move: cancel a
/// tile and ask for it again in the same frame.
Future<int> cancelThenAskAgain(TileProvider tiles) async {
  final layer = TileLayer(urlTemplate: 'https://t.test/{z}/{x}/{y}.png');
  const at = TileCoordinates(1216, 1530, 12);
  final cancelFirst = Completer<void>();
  final first = tiles.getImageWithCancelLoadingSupport(
    at,
    layer,
    cancelFirst.future,
  );
  unawaited(widthOf(first).catchError((_) => 0));
  cancelFirst.complete();
  final second = tiles.getImageWithCancelLoadingSupport(
    at,
    layer,
    Completer<void>().future,
  );
  return widthOf(second);
}

void main() {
  setUp(() => PaintingBinding.instance.imageCache.clear());

  testWidgets('a tile asked for again after a cancel still loads', (
    tester,
  ) async {
    final tiles = OwnLoadTileProvider(
      httpClient: SlowTileServer(),
      cachingProvider: const DisabledMapCachingProvider(),
      silenceExceptions: true,
    );
    final width = await tester.runAsync(() => cancelThenAskAgain(tiles));
    expect(width, 4, reason: 'the real tile, not the blank placeholder');
  });

  testWidgets('the stock provider shows the bug this guards against', (
    tester,
  ) async {
    final tiles = NetworkTileProvider(
      httpClient: SlowTileServer(),
      cachingProvider: const DisabledMapCachingProvider(),
      silenceExceptions: true,
    );
    final width = await tester.runAsync(() => cancelThenAskAgain(tiles));
    expect(width, 1, reason: 'the cancelled load is reused: blank tile');
  });
}
