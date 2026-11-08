import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/ui/mecp_widgets.dart';

Widget host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('a received message is spelled out', (t) async {
    const raw = 'MECP/0/M01 Z99 2pax 48.65,20.13 stuck';
    await t.pumpWidget(host(MecpCard(MecpMessage.tryParse(raw)!, raw: raw)));
    expect(find.text('MAYDAY'), findsOneWidget);
    expect(find.text('• Injury'), findsOneWidget);
    expect(find.text('• Unknown code Z99'), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('stuck'), findsOneWidget);
    expect(find.text(raw), findsOneWidget);
  });

  testWidgets('a drill says so', (t) async {
    const raw = 'MECP/0/D01 M01';
    await t.pumpWidget(host(MecpCard(MecpMessage.tryParse(raw)!, raw: raw)));
    expect(find.text('DRILL (MAYDAY)'), findsOneWidget);
    expect(find.text('MAYDAY'), findsNothing);
  });

  testWidgets('composer needs a severity and adds the position', (t) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? result;
    await t.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showMecpComposer(
              context,
              maxBytes: 200,
              position: const GeoPoint(48.65201, 20.1305),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final use = find.widgetWithText(FilledButton, 'Put in message box');
    expect(t.widget<FilledButton>(use).onPressed, isNull);
    await t.tap(find.text('Medical'));
    await t.pumpAndSettle();
    await t.tap(find.text('Injury'));
    await t.pump();
    expect(t.widget<FilledButton>(use).onPressed, isNull);
    await t.tap(find.text('MAYDAY'));
    await t.pump();
    await t.tap(use);
    await t.pumpAndSettle();
    expect(result, 'MECP/0/M01 P05 48.6520,20.1305');
  });
}
