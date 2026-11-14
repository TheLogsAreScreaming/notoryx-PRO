import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/checklists.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/checklists_screen.dart';

void main() {
  testWidgets('starter lists, a run, a saved record and a new checklist', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = MeshStore.memory();
    final book = ChecklistBook(store);
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
        home: ChecklistsScreen(book: book),
      ),
    );
    await settle();
    expect(find.text('Pre-trip'), findsOneWidget);
    expect(find.text('Deployment'), findsOneWidget);
    expect(find.text('Finished checklists are saved here.'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Start the pre-trip list and tick two items.
    await tester.tap(find.widgetWithText(TextButton, 'Start').first);
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('0 of 6 done'), findsWidgets);
    await tester.tap(find.text('Radio charged and spare power packed'));
    await settle();
    await tester.tap(find.text('Phone paired with the radio'));
    await settle();
    expect(find.text('2 of 6 done'), findsWidgets);
    expect(find.textContaining('Ticked '), findsNWidgets(2));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    // Finish with items left: asks first.
    await tester.ensureVisible(find.byKey(const Key('checklist-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checklist-finish')));
    await settle();
    await tester.pumpAndSettle();
    expect(
      find.text('Items not ticked: 4. Finish and save anyway?'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Finish and save'),
      ),
    );
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('Checklist record saved'), findsOneWidget);
    expect(book.records, hasLength(1));
    expect(find.textContaining('2 of 6 done'), findsOneWidget);

    // Open the record: ticked items say so to screen readers.
    await tester.tap(find.textContaining('2 of 6 done'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Done\n')), findsNWidgets(2));
    expect(find.bySemanticsLabel(RegExp(r'^Not done\n')), findsNWidgets(4));
    expect(find.byTooltip('Export this record'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A new checklist needs a name and items.
    await tester.tap(find.text('New checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checklist-save')));
    await tester.pump();
    expect(find.text('Give the checklist a name'), findsOneWidget);
    expect(find.text('Add at least one item'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('checklist-name')), 'Hike');
    await tester.enterText(
      find.byKey(const Key('checklist-items')),
      'Water\n\n  Snacks  ',
    );
    await tester.tap(find.byKey(const Key('checklist-save')));
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('Hike'), findsOneWidget);
    expect(book.templates!.last.items, ['Water', 'Snacks']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(store.close);
    handle.dispose();
  });
}
