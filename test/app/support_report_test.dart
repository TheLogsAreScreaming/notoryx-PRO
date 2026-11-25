import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/support_report.dart';
import 'package:notoryx_pro/demo/demo_radio.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/radio/connection_log.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/about_screen.dart';
import 'package:notoryx_pro/ui/support_report_sheet.dart';

void main() {
  group('Scrubber', () {
    test('listed names become numbered placeholders, longest first', () {
      final s = Scrubber(['Base Camp', 'Base Camp 2', ' ', 'xy']);
      expect(
        s('BLE Base Camp 2 connected; Base Camp lost'),
        'BLE [name 1] connected; [name 2] lost',
      );
    });

    test('addresses, node IDs, keys and IPs go even when not listed', () {
      final s = Scrubber(const []);
      expect(s('BLE AA:BB:CC:11:22:33 ok'), 'BLE [address] ok');
      expect(s('from !a1b2c3d4 now'), 'from [node] now');
      expect(s('key ${'ab' * 32} saved'), 'key [key] saved');
      expect(s('TCP 192.168.1.20:4403'), 'TCP [ip]:4403');
      expect(
        s('id 0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0 found'),
        'id [device] found',
      );
      expect(s('opened, 42 bytes (type 0x05)'), 'opened, 42 bytes (type 0x05)');
    });
  });

  test('the report lists radios without names and scrubs the log', () {
    final report = supportReport(
      appVersion: '0.36.0 (41)',
      system: 'android 15',
      locale: 'en-US',
      radios: const [
        RadioSummary(
          protocol: 'MeshCore',
          transport: 'Bluetooth',
          status: 'connected',
          firmware: '1.9.1',
          model: 'Heltec V3',
        ),
      ],
      log: [
        LogEntry(DateTime.utc(2026, 11, 25, 9), 'BLE Base Camp', 'connected'),
      ],
      private: ['Base Camp'],
      now: DateTime.utc(2026, 11, 25, 10),
    );
    expect(report, contains('App: 0.36.0 (41)'));
    expect(
      report,
      contains('radio 1: MeshCore, Bluetooth, connected, firmware 1.9.1'),
    );
    expect(report, contains('BLE [name 1]  connected'));
    expect(report, isNot(contains('Base Camp')));
  });

  test('a demo radio and its nodes never appear by name', () async {
    final store = MeshStore.memory();
    final app = AppController(
      store: store,
      links: DemoLinks(chatter: const Duration(hours: 1), random: Random(1)),
    );
    final c = await app.connect(demoTarget);
    final names = [
      c.radio!.name,
      for (final n in await store.nodes(c.radio!.id)) n.name,
    ];
    final report = await buildSupportReport(
      app,
      appVersion: '1.0',
      locale: 'en',
      system: 'test',
    );
    expect(report, contains('radio 1: MeshCore'));
    for (final name in names.where((n) => n.trim().length >= 3)) {
      expect(report, isNot(contains(name)), reason: name);
    }
    await app.shutdown();
    await store.close();
  });

  testWidgets('About shows the report before anything is shared', (t) async {
    t.view.physicalSize = const Size(420, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MeshStore.memory();
    final app = AppController(store: store, links: DemoLinks());
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutScreen(version: Future.value('1.2.3 (4)'), app: app),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('about-support')));
    await t.pumpAndSettle();
    expect(find.textContaining('NOTORYX PRO support report'), findsOneWidget);
    expect(find.textContaining('none connected'), findsOneWidget);
    expect(find.byKey(const Key('support-share')), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('support-text')), findsNothing);
    await t.runAsync(() async {
      await app.shutdown();
      await store.close();
    });
  });
}
