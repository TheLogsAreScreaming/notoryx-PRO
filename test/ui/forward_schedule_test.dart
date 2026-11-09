import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/conversation_screen.dart';
import 'package:notoryx_pro/ui/schedule_sheet.dart';

final ch = ChannelConversation(RadioId.meshtastic(0xa1b2c3d4), 0);

void main() {
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Widget host(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> finish(WidgetTester t, MeshStore store) async {
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  }

  testWidgets('schedule: needs text and a time, then lists it', (t) async {
    t.view.physicalSize = const Size(420, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MeshStore.memory();
    final app = AppController(store: store);
    await t.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScheduleSheet(
                context,
                scheduler: app.scheduler,
                conversation: ch,
                maxBytes: 20,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await settle(t);
    FilledButton save() =>
        t.widget<FilledButton>(find.byKey(const Key('schedule-save')));
    expect(save().onPressed, isNull);
    await t.enterText(find.byKey(const Key('schedule-text')), 'check in');
    await t.pump();
    expect(save().onPressed, isNull, reason: 'no time yet');
    await t.tap(find.text('In 1 hour'));
    await t.pump();
    await t.tap(find.byKey(const Key('schedule-save')));
    await settle(t);
    expect(find.text('check in'), findsWidgets);
    expect(find.byTooltip('Cancel this message'), findsOneWidget);
    await finish(t, store);
  });

  testWidgets('a forwarded message waits in the box, unsent', (t) async {
    final store = MeshStore.memory();
    final app = AppController(store: store);
    await t.pumpWidget(
      host(
        ConversationScreen(
          app: app,
          conversation: ch,
          title: 'Trail',
          draft: 'Fwd Ann: water at hut',
        ),
      ),
    );
    await settle(t);
    expect(find.text('Connect this radio to send messages.'), findsOneWidget);
    expect((await t.runAsync(() => store.messages(ch)))!, isEmpty);
    await finish(t, store);
  });
}
