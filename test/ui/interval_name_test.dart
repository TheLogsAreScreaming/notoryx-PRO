import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/ui/meshtastic_admin_screen.dart';

void main() {
  testWidgets('send intervals read as words, and the firmware never value as '
      'Never', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(intervalName(ctx, 0), 'Default');
    expect(intervalName(ctx, 900), 'Every 15 min');
    expect(intervalName(ctx, 3600), 'Every 1 h');
    expect(intervalName(ctx, 45), 'Every 45 s');
    expect(intervalName(ctx, intervalNever), 'Never');
    expect(intervalName(ctx, 2147483647), 'Never');
  });
}
