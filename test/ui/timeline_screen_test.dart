import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/timeline_screen.dart';

void main() {
  testWidgets('the timeline mixes messages and node news, and filters', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = MeshStore.memory();
    final radio = RadioId.meshtastic(0xa1);
    late AppController app;
    final now = DateTime.now();
    await tester.runAsync(() async {
      app = AppController(store: store);
      await app.timeline.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await store.addMessage(
        Message(
          conversation: ChannelConversation(radio, 0),
          text: 'Water at the spring',
          outgoing: false,
          sentAt: now,
          receivedAt: now,
          delivery: const Received(),
          senderName: 'Ann',
        ),
      );
      await store.upsertNode(
        Node(
          key: NodeKey.meshtastic(0x22),
          radioId: radio,
          name: 'Hill Router',
          lastHeard: now.add(const Duration(minutes: 1)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TimelineScreen(app: app),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(find.text('Hill Router heard for the first time'), findsOneWidget);
    expect(find.text('Water at the spring'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Only messages.
    for (final chip in ['New nodes', 'Signal changes', 'Waypoints']) {
      await tester.tap(find.widgetWithText(FilterChip, chip));
      await tester.pump();
    }
    expect(find.text('Hill Router heard for the first time'), findsNothing);
    expect(find.text('Water at the spring'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
    handle.dispose();
  });
}
