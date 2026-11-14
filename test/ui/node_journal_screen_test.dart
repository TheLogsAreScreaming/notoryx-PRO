import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/node_journal_screen.dart';

void main() {
  testWidgets('journal lists nodes with labels; tags and notes are kept', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = MeshStore.memory();
    final now = DateTime(2026, 11, 13, 23);
    final rpt = NodeKey.meshcore('ef' * 32);
    final ann = NodeKey.meshtastic(0x22);
    late AppController app;
    await tester.runAsync(() async {
      app = AppController(store: store);
      for (var d = 9; d >= 0; d--) {
        for (var h = 0; h < 24; h += 2) {
          await store.upsertNode(
            Node(
              key: rpt,
              radioId: RadioId.meshcore('cd' * 32),
              name: 'Hilltop',
              kind: NodeKind.relay,
              lastHeard: DateTime(2026, 11, 13 - d, h),
            ),
          );
        }
      }
      await store.upsertNode(
        Node(
          key: ann,
          radioId: RadioId.meshtastic(0xa1),
          name: 'Ann',
          lastHeard: now.subtract(const Duration(hours: 2)),
        ),
      );
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
        home: JournalScreen(app: app, clock: () => now),
      ),
    );
    await settle();
    expect(find.text('Hilltop'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.textContaining('Always-on relay ('), findsOneWidget);
    expect(find.textContaining('New arrival (60% sure)'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Filter by label.
    final chip = find.widgetWithText(ChoiceChip, 'New arrival');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pump();
    expect(find.text('Hilltop'), findsNothing);
    expect(find.text('Ann'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pump();

    // Search.
    await tester.enterText(find.byKey(const Key('journal-search')), 'hill');
    await tester.pump();
    expect(find.text('Ann'), findsNothing);
    await tester.enterText(find.byKey(const Key('journal-search')), '');
    await tester.pump();

    // Open the repeater: labels with evidence, and the mark is labelled.
    await tester.tap(find.text('Hilltop'));
    await tester.pumpAndSettle();
    await settle();
    expect(find.text('What it seems to be'), findsOneWidget);
    expect(
      find.textContaining('Heard during 12 of the 24 hours'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Says it is a repeater or router'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Generated mark for efefefef'),
      findsOneWidget,
    );
    expect(find.text('Times heard: 120'), findsOneWidget);

    // Add a tag.
    await tester.ensureVisible(find.byKey(const Key('journal-add-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journal-add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('journal-tag-field')), 'Club');
    await tester.tap(find.widgetWithText(FilledButton, 'Add tag'));
    await tester.pumpAndSettle();
    await settle();
    expect(find.widgetWithText(InputChip, 'club'), findsOneWidget);

    // Save a note.
    await tester.ensureVisible(find.byKey(const Key('journal-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('journal-note')), 'Solar');
    await tester.ensureVisible(find.text('Save note'));
    await tester.tap(find.text('Save note'));
    await settle();
    expect(find.text('Note saved'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    late List<String> tags;
    late String note;
    await tester.runAsync(() async {
      final e = (await store.journalEntry(rpt))!;
      tags = e.tags;
      note = e.note;
    });
    expect(tags, ['club']);
    expect(note, 'Solar');

    await tester.pumpWidget(const SizedBox());
    // Let drift finish cancelling the watch on its timer.
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
    handle.dispose();
  });
}
