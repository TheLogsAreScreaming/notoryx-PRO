import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/reports.dart';
import 'package:notoryx_pro/ui/report_sheet.dart';

void main() {
  test('SALUTE leaves out empty fields and keeps tags', () {
    expect(
      ReportKind.salute.encode(['2 ppl', '', 'ridge', '', '1400', ' a  b ']),
      'SALUTE S:2 ppl L:ridge T:1400 E:a b',
    );
  });

  test('9-Line numbers its fields', () {
    expect(
      ReportKind.nineLine.encode([
        'grid',
        '',
        '',
        '',
        '1L',
        ...List.filled(4, ''),
      ]),
      '9LINE 1:grid 5:1L',
    );
    expect(ReportKind.nineLine.tags, hasLength(9));
  });

  testWidgets('fills in position, returns text, blocks over-long', (t) async {
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? out;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              out = await showReportComposer(
                context,
                maxBytes: 30,
                position: '1.5,2.5',
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text('SALUTE report'));
    await t.pumpAndSettle();
    final use = find.widgetWithText(FilledButton, 'Put in message box');
    await t.enterText(find.byKey(const Key('report-S')), 'x' * 40);
    await t.pump();
    expect(t.widget<FilledButton>(use).onPressed, isNull);
    await t.enterText(find.byKey(const Key('report-S')), '2');
    await t.pump();
    await t.tap(use);
    await t.pumpAndSettle();
    expect(out, 'SALUTE S:2 L:1.5,2.5');
  });
}
