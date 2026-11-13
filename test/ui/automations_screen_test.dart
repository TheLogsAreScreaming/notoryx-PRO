import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/automations.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/automations_screen.dart';

void main() {
  testWidgets('build an automation: a message trigger and an alert', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = MeshStore.memory();
    late AppController app;
    await tester.runAsync(() async {
      app = AppController(store: store);
    });
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AutomationsScreen(app: app),
      ),
    );
    await settle();
    expect(find.text('No automations yet.'), findsOneWidget);
    final webhooks = find.widgetWithText(
      SwitchListTile,
      'Allow web requests (webhooks)',
    );
    expect(tester.widget<SwitchListTile>(webhooks).value, isFalse);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.text('New automation'));
    await settle();
    await tester.enterText(find.byType(TextField), 'SOS watch');
    await tester.tap(find.text('Add trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message received'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Containing (optional)'),
      'help',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Message containing “help”'), findsOneWidget);

    await tester.tap(find.text('Add action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show an alert'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Text'),
      '{node} needs help',
    );
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Alert: {node} needs help'), findsOneWidget);
    expect(find.byTooltip('Remove Alert: {node} needs help'), findsOneWidget);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.text('Save').first);
    await settle();
    expect(find.text('SOS watch'), findsOneWidget);
    expect(
      find.textContaining('When any of: Message containing'),
      findsOneWidget,
    );

    String? raw;
    await tester.runAsync(() async {
      raw = await store.preference(AutomationEngine.prefName);
    });
    final saved = AutomationSettings.decode(raw);
    expect(saved.rules.single.name, 'SOS watch');
    expect(saved.rules.single.actions.single, isA<AlertAction>());

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
    handle.dispose();
  });
}
