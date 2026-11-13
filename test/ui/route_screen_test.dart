import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/route_planner.dart';
import 'package:notoryx_pro/ui/route_screen.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the route chart reads each hop and its link aloud', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: RouteChart(
            from: 'Base',
            to: 'Ann',
            choice: RouteChoice(
              source: RouteSource.trace,
              measured: DateTime(2026, 11, 13, 9),
              hops: const [
                PlannedHop(hash: 'a1', label: 'Peak', snr: 5, backSnr: 4),
                PlannedHop(hash: 'b2', label: 'b2'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Hop 1, Peak: out 5.0 dB, back 4.0 dB'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Hop 2, b2: link not measured'),
      findsOneWidget,
    );
    expect(find.textContaining('2 hops'), findsOneWidget);
    expect(find.textContaining('weakest link 4.0 dB'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('the editor builds a route in order and pops its hashes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final radio = RadioId.meshcore('ab' * 32);
    Node relay(int b, String name) => Node(
      key: NodeKey.meshcore(b.toRadixString(16) * 32),
      radioId: radio,
      name: name,
      kind: NodeKind.relay,
      publicKey: List.filled(32, b),
    );
    List<String>? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showModalBottomSheet<List<String>>(
                context: context,
                builder: (_) => RouteEditorSheet(
                  candidates: [relay(0xa1, 'Peak'), relay(0xb2, 'Mill')],
                  hashSize: 1,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('No repeaters picked yet.'), findsOneWidget);

    for (final name in ['Peak (a1)', 'Mill (b2)']) {
      await tester.tap(find.text('Add repeater'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    // Swap them, then use the route.
    await tester.tap(find.byTooltip('Move Mill up'));
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text('Use this route'));
    await tester.pumpAndSettle();
    expect(result, ['b2', 'a1']);
    handle.dispose();
  });
}
