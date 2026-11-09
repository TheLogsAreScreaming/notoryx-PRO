import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/diagnostics.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/diagnostics_screen.dart';

void main() {
  testWidgets('saved traces open, show hops and clear', (tester) async {
    final store = MeshStore.memory();
    final radio = RadioId.meshtastic(9);
    final node = Node(radioId: radio, key: NodeKey.meshtastic(1), name: 'Sam');
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await tester.runAsync(
      () => store.addTrace(
        radio,
        'Sam',
        TraceResult(
          target: node.key,
          towards: const [TraceHop('Peak', 3.5), TraceHop('Sam', 1)],
          time: DateTime(2026, 11, 8, 9, 30),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SavedTracesSheet(store: store, node: node),
        ),
      ),
    );
    await settle();
    expect(find.text('2 hops'), findsOneWidget);
    expect(find.text('Peak'), findsNothing);

    await tester.tap(find.text('2 hops'));
    await tester.pumpAndSettle();
    expect(find.text('Peak'), findsOneWidget);
    expect(find.text('Towards Sam'), findsOneWidget);

    await tester.tap(find.text('Clear saved traces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear saved traces').last);
    await tester.pumpAndSettle();
    await settle();
    expect(find.textContaining('No saved traces yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });
}
