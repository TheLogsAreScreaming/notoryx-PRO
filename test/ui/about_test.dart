import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/ui/about_screen.dart';

void main() {
  testWidgets('shows version, disclaimer and the licence page', (t) async {
    t.view.physicalSize = const Size(420, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutScreen(version: Future.value('1.2.3 (4)')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Version 1.2.3 (4)'), findsOneWidget);
    expect(find.text('Not an emergency service'), findsOneWidget);
    await t.tap(find.byKey(const Key('about-licences')));
    await t.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test(
    'extra licences include the app, MECP and the encryption library',
    () async {
      registerExtraLicenses();
      registerExtraLicenses();
      final names = <String>[];
      await for (final e in LicenseRegistry.licenses) {
        names.addAll(e.packages);
      }
      expect(
        names,
        containsAll([
          'NOTORYX PRO',
          'MECP labels',
          'SQLite3MultipleCiphers',
          'libserialport',
        ]),
      );
      expect(names.where((n) => n == 'NOTORYX PRO'), hasLength(1));
    },
  );
}
