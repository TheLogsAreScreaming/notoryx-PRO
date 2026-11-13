import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/replay_screen.dart';

void main() {
  testWidgets('a day plays back: team first, scrub, play, everyone', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = MeshStore.memory();
    final radio = RadioId.meshtastic(0xa1);
    final day = DateTime(2026, 11, 12);
    late AppController app;
    await tester.runAsync(() async {
      app = AppController(store: store);
      await store.upsertRadio(
        Radio(id: radio, name: 'Base', self: NodeKey.meshtastic(0xa1)),
      );
      for (var i = 0; i < 3; i++) {
        // Ann is a favourite: on the team.
        await store.upsertNode(
          Node(
            key: NodeKey.meshtastic(0x22),
            radioId: radio,
            name: 'Ann Lee',
            isFavorite: true,
            position: GeoPoint(45.5 + i / 100, -122.6),
            lastHeard: day.add(Duration(hours: 9, minutes: 30 * i)),
          ),
        );
        await store.upsertNode(
          Node(
            key: NodeKey.meshtastic(0x33),
            radioId: radio,
            name: 'Stranger',
            position: GeoPoint(45.6, -122.5 + i / 100),
            lastHeard: day.add(Duration(hours: 10, minutes: 30 * i)),
          ),
        );
      }
    });
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReplayScreen(app: app, day: day),
      ),
    );
    await settle();
    // Team only: Ann, shown at her last position of the day.
    expect(find.widgetWithText(FilterChip, 'Ann Lee'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Stranger'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Map at .*: 1 node shown')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Last seen 10:00 AM at 45.52000'),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    // Scrub to the very start.
    await tester.drag(find.byType(Slider), const Offset(-2000, 0));
    await tester.pump();
    expect(
      find.textContaining('Last seen 9:00 AM at 45.50000'),
      findsOneWidget,
    );

    // Play advances the clock, pause stops it.
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Pause'), findsOneWidget);
    // 5 replayed minutes per second, for 2 seconds.
    expect(find.text('9:10 AM'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    await tester.tap(find.text('Everyone'));
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'Stranger'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
    handle.dispose();
  });
}
