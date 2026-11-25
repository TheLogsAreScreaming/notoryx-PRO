import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/ui/privacy_screen.dart';

Future<void> show(
  WidgetTester t,
  PrivacyFacts facts, {
  Locale? locale,
  double width = 420,
}) async {
  t.view.physicalSize = Size(width, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PrivacyView(facts),
    ),
  );
  await t.pumpAndSettle();
}

/// The On / Off / count text at the end of a row.
String stateOf(WidgetTester t, String key) {
  final row = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(ListTile),
  );
  expect(row, findsOneWidget, reason: key);
  return (t.widget<ListTile>(row).trailing! as Text).data!;
}

void main() {
  testWidgets('a fresh install shares nothing, and says so in words', (
    t,
  ) async {
    await show(t, const PrivacyFacts());
    expect(find.text('Privacy'), findsOneWidget);
    for (final k in [
      'privacy-coverage',
      'privacy-feeds',
      'privacy-bridge',
      'privacy-moderation',
      'privacy-webhooks',
      'privacy-lock',
    ]) {
      expect(stateOf(t, k), 'Off', reason: k);
    }
    expect(stateOf(t, 'privacy-tiles'), 'Always');
    // No vault: encryption isn't available on this device.
    expect(stateOf(t, 'privacy-encryption'), 'Not on this device');
    expect(
      find.text('Off: coverage readings stay on this phone.'),
      findsOneWidget,
    );
  });

  testWidgets('what is on shows as On or as a count', (t) async {
    await show(
      t,
      const PrivacyFacts(
        coverageSharing: true,
        feeds: 2,
        bridges: 1,
        moderation: true,
        webhooks: true,
        encrypted: true,
        appLock: true,
      ),
    );
    expect(stateOf(t, 'privacy-coverage'), 'On');
    expect(stateOf(t, 'privacy-feeds'), '2');
    expect(stateOf(t, 'privacy-bridge'), '1');
    expect(stateOf(t, 'privacy-moderation'), 'On');
    expect(stateOf(t, 'privacy-webhooks'), 'On');
    expect(stateOf(t, 'privacy-encryption'), 'On');
    expect(stateOf(t, 'privacy-lock'), 'On');
    expect(
      find.textContaining('upload to the NOTORYX coverage map'),
      findsOneWidget,
    );
  });

  testWidgets('long German text fits a narrow phone', (t) async {
    await show(
      t,
      const PrivacyFacts(encrypted: false),
      locale: const Locale('de'),
      width: 320,
    );
    expect(t.takeException(), isNull);
    expect(find.text('Datenschutz'), findsOneWidget);
    expect(stateOf(t, 'privacy-encryption'), 'Aus');
  });
}
