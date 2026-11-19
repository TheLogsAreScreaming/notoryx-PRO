import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:notoryx_pro/ui/range_rings_layer.dart';

void main() {
  const area = Rect.fromLTRB(0, 0, 300, 400);

  group('clampInto', () {
    test('leaves a label that fits where it is', () {
      expect(
        clampInto(const Offset(150, 200), compassTagSize, area),
        const Offset(150, 200),
      );
    });

    test('pulls a label back inside each edge', () {
      expect(
        clampInto(const Offset(500, 200), compassTagSize, area),
        const Offset(288, 200),
      );
      expect(
        clampInto(const Offset(150, -90), compassTagSize, area),
        const Offset(150, 10),
      );
      expect(
        clampInto(const Offset(-5, 999), compassTagSize, area),
        const Offset(12, 390),
      );
    });

    test('centres a label bigger than the area', () {
      expect(
        clampInto(const Offset(0, 0), const Size(400, 20), area),
        const Offset(150, 10),
      );
    });
  });

  group('firstFree', () {
    const candidates = [Offset(150, 5), Offset(290, 200), Offset(150, 200)];

    test('skips spots that would stick out of the area', () {
      expect(firstFree(candidates, ringLabelSize, area, const []), 2);
    });

    test('skips spots taken by another label', () {
      expect(
        firstFree(candidates, ringLabelSize, area, [
          Rect.fromCenter(
            center: const Offset(160, 205),
            width: 24,
            height: 20,
          ),
        ]),
        isNull,
      );
    });

    test('takes the first spot that is free', () {
      expect(
        firstFree(
          const [Offset(100, 100), Offset(200, 200)],
          ringLabelSize,
          area,
          const [],
        ),
        0,
      );
    });
  });

  test('unobscured leaves out the covered edges', () {
    expect(
      unobscured(
        const Size(300, 400),
        const EdgeInsets.only(top: 64, right: 80, bottom: 24),
      ),
      const Rect.fromLTRB(0, 64, 220, 376),
    );
    // Insets that cover everything fall back to the whole map.
    expect(
      unobscured(const Size(100, 100), const EdgeInsets.only(right: 120)),
      const Rect.fromLTRB(0, 0, 100, 100),
    );
  });

  testWidgets('ring and compass tags stay clear of the covered edges', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Your position off to the east and north of the view, so the E and N
    // tags and the north labels would land under the controls or off the map.
    const view = LatLng(45, -122);
    const you = LatLng(45.01, -121.985);
    const insets = EdgeInsets.only(top: 64, right: 80, bottom: 24);
    for (final zoom in [14.0, 3.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            key: ValueKey(zoom),
            options: MapOptions(initialCenter: view, initialZoom: zoom),
            children: const [RangeRingsLayer(center: you, insets: insets)],
          ),
        ),
      );
      await tester.pump();
      const clear = Rect.fromLTRB(0, 64, 320, 376);
      final tags = find.descendant(
        of: find.byKey(const Key('range-rings')),
        matching: find.byType(DecoratedBox),
      );
      expect(tags, findsWidgets);
      for (final e in tags.evaluate()) {
        final box = tester.getRect(find.byWidget(e.widget));
        expect(
          clear.inflate(.5).contains(box.topLeft) &&
              clear.inflate(.5).contains(box.bottomRight),
          isTrue,
          reason: 'tag at $box (zoom $zoom) is under a control',
        );
      }
      for (final t in ['N', 'E', 'S', 'W']) {
        expect(find.text(t), findsOneWidget);
      }
    }
  });
}
