import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/message_export.dart';
import 'package:notoryx_pro/app/message_import.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/node_look.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/node_avatar.dart';

final node = NodeKey.meshtastic(0x1234).toString();

void main() {
  test('stored, replaced and cleared', () async {
    final s = MeshStore.memory();
    await s.setNodeLook(node, const NodeLook(color: 0xFF1976D2));
    expect((await s.nodeLooks())[node]!.color, 0xFF1976D2);
    await s.setNodeLook(node, NodeLook(photo: Uint8List.fromList([1, 2, 3])));
    final look = (await s.nodeLooks())[node]!;
    expect(look.color, isNull);
    expect(look.photo, [1, 2, 3]);
    await s.setNodeLook(node, const NodeLook());
    expect(await s.nodeLooks(), isEmpty);
    await s.close();
  });

  test('travel in backups; bad entries and huge photos are dropped', () {
    final json = messagesToJson(
      const [],
      const {},
      exportedAt: DateTime.utc(2026),
      looks: {
        node: NodeLook(color: 7, photo: Uint8List.fromList([9, 9])),
      },
    );
    final back = parseExport(json).looks[node]!;
    expect(back.color, 7);
    expect(back.photo, [9, 9]);

    final big =
        '{"format":"notoryx-pro-messages","formatVersion":1,'
        '"messages":[],"nodeLooks":[{"node":"nope","color":1},'
        '{"node":"$node","color":2,"photo":"${'A' * 400000}"}]}';
    final looks = parseExport(big).looks;
    expect(looks.keys, [node]);
    expect((looks[node]!.color, looks[node]!.photo), (2, null));
  });

  test('photos are shrunk to a small square', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 800, 600),
      Paint()..color = const Color(0xFF00FF00),
    );
    final img = await recorder.endRecording().toImage(800, 600);
    final png = (await img.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final small = await shrinkPhoto(png);
    final codec = await ui.instantiateImageCodec(small);
    final frame = await codec.getNextFrame();
    expect((frame.image.width, frame.image.height), (256, 256));
  });

  testWidgets('avatar falls back, then shows a colour; sheet sets it', (
    t,
  ) async {
    final store = MeshStore.memory();
    final app = AppController(store: store);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                NodeAvatar(app: app, nodeKey: node, icon: Icons.person),
                TextButton(
                  onPressed: () => showNodeLookSheet(
                    context,
                    app: app,
                    nodeKey: node,
                    name: 'Ann',
                  ),
                  child: const Text('go'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.person), findsOneWidget);
    app.looks.value = {node: const NodeLook(color: 0xFF388E3C)};
    await t.pump();
    final box = t.widget<Container>(
      find.descendant(
        of: find.byType(NodeAvatar),
        matching: find.byType(Container),
      ),
    );
    expect((box.decoration! as BoxDecoration).color, const Color(0xFF388E3C));

    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Colour or photo for Ann'), findsOneWidget);
    await t.tap(find.byKey(const Key('look-color-5')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(
      (await t.runAsync(store.nodeLooks))![node]!.color,
      nodeLookColors[5],
    );
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
