import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/app/sentinel.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/radio/radio_link.dart';
import 'package:notoryx_pro/ui/sentinel_screen.dart';

void main() {
  testWidgets('Send stays above the keyboard while typing a note', (
    tester,
  ) async {
    // A 6.5-inch phone with the on-screen keyboard open.
    const dpr = 2.625;
    const keyboard = 330.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);

    final prefs = <String, String>{};
    final reports = <http.Request>[];
    final sentinel = SentinelService(
      read: (n) async => prefs[n],
      write: (n, v) async => prefs[n] = v,
      baseUrl: 'https://relay.test',
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/reports')) {
          reports.add(req);
          return http.Response(
            jsonEncode({'caseRef': 'SNT-1', 'status': 'received'}),
            201,
          );
        }
        return http.Response(jsonEncode({'advisory': true, 'bans': []}), 200);
      }),
    );
    await tester.runAsync(() async {
      await sentinel.start();
      await sentinel.setEnabled(true);
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSentinelReportSheet(
                context,
                sentinel: sentinel,
                network: RadioProtocol.meshcore,
                nodeId: 'ab' * 32,
                nodeName: 'Bot',
                messageExcerpt: 'buy now buy now buy now',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sentinel-note')));
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * dpr);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sentinel-note')),
      'test note',
    );
    await tester.pumpAndSettle();

    final send = find.byKey(const ValueKey('sentinel-send-report'));
    final screen = tester.view.physicalSize.height / dpr;
    expect(tester.getRect(send).bottom, lessThanOrEqualTo(screen - keyboard));

    await tester.runAsync(() async {
      await tester.tap(send);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(reports, hasLength(1));
    expect(
      (jsonDecode(reports.single.body) as Map)['reason'],
      contains('test note'),
    );

    await tester.runAsync(() => sentinel.setEnabled(false));
    sentinel.dispose();
  });
}
