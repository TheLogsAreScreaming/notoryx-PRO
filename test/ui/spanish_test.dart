import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/ui/mecp_widgets.dart';

void main() {
  testWidgets('a Spanish phone reads the app and emergency labels in Spanish', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('es');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MecpCard(
            MecpMessage.tryParse('MECP/1/M01 Rio 2pax')!,
            raw: 'raw',
          ),
        ),
      ),
    );
    expect(find.text('2 personas'), findsOneWidget);
    expect(find.textContaining('• '), findsOneWidget);
    expect(find.textContaining('Injury'), findsNothing);
  });
}
