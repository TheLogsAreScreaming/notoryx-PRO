import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/beacon_sheet.dart';
import 'package:notoryx_pro/ui/mecp_widgets.dart';
import 'package:notoryx_pro/ui/report_sheet.dart';
import 'package:notoryx_pro/ui/schedule_sheet.dart';
import 'package:notoryx_pro/ui/team_pack_screen.dart';
import 'package:notoryx_pro/ui/themes.dart';

import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

typedef Open =
    Future<void> Function(
      BuildContext,
      AppController,
      RadioConnection,
      Conversation,
    );

void main() {
  final sheets = <String, Open>{
    'beacon': (c, a, r, ch) =>
        showBeaconSheet(c, app: a, connection: r, conversation: ch),
    'reports': (c, a, r, ch) => showReportComposer(c, maxBytes: 200),
    'schedule': (c, a, r, ch) => showScheduleSheet(
      c,
      scheduler: a.scheduler,
      conversation: ch,
      maxBytes: 200,
    ),
    'mecp': (c, a, r, ch) => showMecpComposer(c, maxBytes: 200),
    'team setup': (c, a, r, ch) => Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (_) => TeamPackScreen(connection: r, store: a.store),
      ),
    ),
  };

  for (final MapEntry(key: name, value: open) in sheets.entries) {
    for (final b in Brightness.values) {
      testWidgets('$name ${b.name}: tap size, labels, contrast', (t) async {
        t.view.physicalSize = const Size(390, 1200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final handle = t.ensureSemantics();
        final store = MeshStore.memory();
        final app = AppController(
          store: store,
          links: FakeLinks(ScriptedMeshtasticLink()),
        );
        final c = (await t.runAsync(
          () => app.connect(
            const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
          ),
        ))!;
        final chat = ChannelConversation(c.radio!.id, 0);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(const ThemeChoice(), b),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => open(context, app, c, chat),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('go'));
        for (var i = 0; i < 8; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(seconds: 1));
        final problems = <String>[];
        for (final g in [
          androidTapTargetGuideline,
          labeledTapTargetGuideline,
          textContrastGuideline,
        ]) {
          final r = await g.evaluate(t);
          if (!r.passed) problems.add(r.reason ?? '');
        }
        handle.dispose();
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        await t.runAsync(app.shutdown);
        final closing = store.close();
        await t.pump(const Duration(seconds: 1));
        await t.runAsync(() => closing);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
