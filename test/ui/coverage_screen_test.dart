import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notoryx_pro/app/coverage_mapper.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/coverage.dart';
import 'package:notoryx_pro/ui/coverage_screen.dart';

class _NoSources implements CoverageSources {
  @override
  Stream<CoverageFix> fixes() => const Stream.empty();
  @override
  String cellAt(double latitude, double longitude) => 'cell';
  @override
  List<(double, double)> cellOutline(String cell) => const [];
  @override
  Future<bool> onWifi() async => true;
  @override
  Future<List<CoverageRepeater>> repeaters() async => const [];
}

void main() {
  testWidgets('sharing stays off until the user agrees', (tester) async {
    final prefs = <String, String>{};
    var requests = 0;
    final mapper = CoverageMapper(
      read: (n) async => prefs[n],
      write: (n, v) async => prefs[n] = v,
      sources: _NoSources(),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await mapper.start();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CoverageScreen(coverage: mapper),
      ),
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.covNoHexagons), findsOneWidget);
    expect(find.text(l.covShareOff), findsOneWidget);

    // Cancel: still off.
    await tester.tap(find.byKey(const Key('coverage-share')));
    await tester.pumpAndSettle();
    expect(find.text(l.covConsentBody), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(mapper.sharing, isFalse);
    expect(prefs[CoverageMapper.prefSharing], isNull);

    // Agree: on, with the defaults the dialog describes.
    await tester.tap(find.byKey(const Key('coverage-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coverage-agree')));
    await tester.pumpAndSettle();
    expect(mapper.sharing, isTrue);
    expect(mapper.privacy, CoveragePrivacy.delayed);
    expect(mapper.wifiOnly, isTrue);
    expect(mapper.hideEnds, isTrue);
    expect(requests, 0, reason: 'nothing recorded, nothing sent');
    await tester.scrollUntilVisible(
      find.byKey(const Key('coverage-erase')),
      200,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('coverage-stop-sharing')),
      200,
    );
    await tester.tap(find.byKey(const Key('coverage-stop-sharing')));
    await tester.pumpAndSettle();
    expect(mapper.sharing, isFalse);
    expect(prefs[CoverageMapper.prefSharing], 'false');
    mapper.dispose();
  });
}
