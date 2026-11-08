import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/meshtastic_admin_screen.dart';
import 'package:notoryx_pro/ui/telemetry_screen.dart';

import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

const target = TcpTarget(host: 'node', protocol: RadioProtocol.meshtastic);
const remoteNum = 0x0badcafe;

/// A radio with its own admin and one remote node behind it.
class Bench {
  Bench() {
    link.onPacket = (p) => [
      ...local(p, myNode: link.myNode),
      ...remote(p, myNode: link.myNode),
    ];
  }

  final link = ScriptedMeshtasticLink();
  late final local = FakeAdminNode(link.myNode);
  final remote = FakeAdminNode(remoteNum);
}

Widget app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Lets real async work (the fake radio, the database) run in a widget test.
Future<void> settle(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> closeAll(
  WidgetTester tester,
  AppController controller,
  MeshStore store,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(controller.shutdown);
  final closing = store.close();
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() => closing);
}

Uint8List telemetry({int? battery, double? volts, double? temp, int? time}) {
  final w = ProtoWriter();
  if (time != null) w.fixed32(1, time);
  if (battery != null || volts != null) {
    final d = ProtoWriter();
    if (battery != null) d.uint(1, battery, always: true);
    if (volts != null) d.fixed32(2, floatBits(volts));
    w.bytes(2, d.toBytes(), always: true);
  }
  if (temp != null) {
    w.bytes(3, (ProtoWriter()..fixed32(1, floatBits(temp))).toBytes());
  }
  return w.toBytes();
}

int floatBits(double v) =>
    (ByteData(4)..setFloat32(0, v, Endian.little)).getUint32(0, Endian.little);

void main() {
  group('connection', () {
    late MeshStore store;
    late Bench bench;
    late AppController controller;
    late MeshtasticConnection c;

    setUp(() async {
      store = MeshStore.memory();
      bench = Bench();
      controller = AppController(store: store, links: FakeLinks(bench.link));
      c = await controller.connect(target) as MeshtasticConnection;
    });

    tearDown(() async {
      await controller.shutdown();
      await store.close();
    });

    test('loads all sections and saves only what changed', () async {
      final s = await c.loadSettings();
      expect(s[SectionKind.owner].text(OwnerField.longName), 'Ridge Relay');
      expect(s[SectionKind.position].number(PositionField.broadcastSecs), 900);
      expect(s.hasChanges, isFalse);

      final edited = s
          .withValue(SectionKind.owner, OwnerField.longName, 'Camp North')
          .withValue(
            SectionKind.telemetry,
            TelemetryField.deviceInterval,
            3600,
          );
      expect(edited.radioChanged, isFalse);
      expect(
        edited.withValue(SectionKind.lora, LoraField.region, 3).radioChanged,
        isTrue,
      );
      expect(
        edited
            .withValue(
              SectionKind.device,
              DeviceField.role,
              MeshtasticRole.router,
            )
            .becomesInfrastructure,
        isTrue,
      );

      await c.saveSettings(edited);
      await pumpEventQueue();
      expect(
        bench.local.fields.skipWhile((f) => f != AdminField.beginEditSettings),
        [
          AdminField.beginEditSettings,
          AdminField.setOwner,
          AdminField.setModuleConfig,
          AdminField.commitEditSettings,
        ],
      );
      expect(c.radio!.name, 'Camp North', reason: 'radio name updated');
      expect((await store.radios()).single.name, 'Camp North');
    });

    test('administers another node over the mesh', () async {
      final s = await c.loadSettings(node: remoteNum);
      expect(bench.remote.packets.every((p) => p.pkiEncrypted), isTrue);
      await c.saveSettings(
        s.withValue(SectionKind.lora, LoraField.hopLimit, 4),
        node: remoteNum,
      );
      await pumpEventQueue();
      expect(
        SettingsSection(
          SectionKind.lora,
          bench.remote.sections[SectionKind.lora]!,
        ).number(LoraField.hopLimit),
        4,
      );
      expect(c.radio!.name, 'Base Camp', reason: 'own radio untouched');
    });

    test('keeps telemetry from every node, own and others', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      bench.link
        ..push(
          NodeFrames.packet(
            from: remoteNum,
            to: broadcastNode,
            portnum: PortNum.telemetry,
            payload: telemetry(battery: 87, volts: 4.01, time: now - 60),
          ),
        )
        ..push(
          NodeFrames.packet(
            from: bench.link.myNode,
            to: broadcastNode,
            portnum: PortNum.telemetry,
            payload: telemetry(battery: 101, temp: 18.5),
          ),
        )
        // A clock far in the past is not trusted.
        ..push(
          NodeFrames.packet(
            from: remoteNum,
            to: broadcastNode,
            portnum: PortNum.telemetry,
            payload: telemetry(battery: 85, time: 1000),
          ),
        );
      final radio = c.radio!.id;
      final since = DateTime.now().subtract(const Duration(days: 1));
      var remote = <TelemetryPoint>[];
      for (var i = 0; i < 50 && remote.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        remote = await store.telemetry(
          radio,
          NodeKey.meshtastic(remoteNum),
          since: since,
        );
      }
      expect(remote.map((p) => p.batteryLevel), [87, 85]);
      expect(remote.first.voltage, closeTo(4.01, 0.001));
      expect(
        remote.first.time,
        DateTime.fromMillisecondsSinceEpoch((now - 60) * 1000),
      );
      final own = await store.telemetry(
        radio,
        NodeKey.meshtastic(bench.link.myNode),
        since: since,
      );
      expect(own.single.isPowered, isTrue);
      expect(own.single.temperature, 18.5);
    });
  });

  test('telemetry older than 14 days is dropped', () async {
    final store = MeshStore.memory();
    final radio = RadioId.meshtastic(1);
    final node = NodeKey.meshtastic(2);
    final now = DateTime(2026, 11, 7, 12);
    await store.addTelemetry(
      TelemetryPoint(
        radioId: radio,
        node: node,
        time: now.subtract(const Duration(days: 15)),
        batteryLevel: 50,
      ),
    );
    await store.addTelemetry(
      TelemetryPoint(radioId: radio, node: node, time: now, batteryLevel: 60),
    );
    await store.addTelemetry(
      TelemetryPoint(radioId: radio, node: node, time: now),
    ); // empty: not stored
    final all = await store.telemetry(radio, node, since: DateTime(2000));
    expect(all.map((p) => p.batteryLevel), [60]);
    await store.close();
  });

  testWidgets('settings screen: edit, warn about radio changes, save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MeshStore.memory();
    final bench = Bench();
    final controller = AppController(
      store: store,
      links: FakeLinks(bench.link),
    );
    final c =
        (await tester.runAsync(() => controller.connect(target)))!
            as MeshtasticConnection;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MeshtasticSettingsScreen(connection: c),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Asking the node for its settings…'), findsOneWidget);
    await settle(tester);
    expect(find.text('Ridge Relay'), findsOneWidget);
    expect(find.text('United States'), findsOneWidget);
    expect(find.text('Every 15 min'), findsOneWidget);
    final save = find.byKey(const Key('mt-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('mt-short-name')), 'TOOLONG');
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(find.text('1 to 4 characters'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mt-short-name')), 'CN');
    await tester.enterText(find.byKey(const Key('mt-slot')), '20');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Save these changes?'), findsOneWidget);
    expect(find.textContaining('region, preset or slot'), findsOneWidget);
    await tester.tap(find.text('Save to radio').last);
    await settle(tester);
    expect(find.textContaining('Saved.'), findsOneWidget);
    expect(find.text('open'), findsOneWidget, reason: 'screen closed');
    final lora = SettingsSection(
      SectionKind.lora,
      bench.local.sections[SectionKind.lora]!,
    );
    expect(lora.number(LoraField.channelNum), 20);
    expect(
      SettingsSection(
        SectionKind.owner,
        bench.local.sections[SectionKind.owner]!,
      ).text(OwnerField.shortName),
      'CN',
    );
    await closeAll(tester, controller, store);
  });

  testWidgets('standard setup for a region fills region, preset, slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MeshStore.memory();
    final bench = Bench();
    bench.local.sections[SectionKind.lora] =
        (ProtoWriter()
              ..uint(LoraField.region, 0)
              ..uint(LoraField.modemPreset, 3)
              ..uint(LoraField.channelNum, 9)
              ..uint(LoraField.hopLimit, 3))
            .toBytes();
    final controller = AppController(
      store: store,
      links: FakeLinks(bench.link),
    );
    final c =
        (await tester.runAsync(() => controller.connect(target)))!
            as MeshtasticConnection;
    expect(c.regionUnset, isTrue);
    await tester.pumpWidget(app(MeshtasticSettingsScreen(connection: c)));
    await settle(tester);
    expect(find.text('Not set'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mt-presets')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('EU 868 MHz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('EU 868 MHz'), findsOneWidget);
    expect(find.text('Long Fast'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mt-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to radio').last);
    await settle(tester);
    final lora = SettingsSection(
      SectionKind.lora,
      bench.local.sections[SectionKind.lora]!,
    );
    expect(lora.number(LoraField.region), 3);
    expect(lora.flag(LoraField.usePreset), isTrue);
    expect(lora.number(LoraField.modemPreset), MeshtasticPreset.longFast);
    expect(lora.number(LoraField.channelNum), 0);
    expect(c.regionUnset, isFalse);
    await closeAll(tester, controller, store);
  });

  testWidgets('remote admin explains a silent node and offers the key', (
    tester,
  ) async {
    final store = MeshStore.memory();
    final bench = Bench()..remote.answers = false;
    final controller = AppController(
      store: store,
      links: FakeLinks(bench.link),
    );
    final c =
        (await tester.runAsync(() => controller.connect(target)))!
            as MeshtasticConnection;
    final node = Node(
      key: NodeKey.meshtastic(remoteNum),
      radioId: c.radio!.id,
      name: 'Ridge Relay',
    );
    await tester.pumpWidget(
      app(
        MeshtasticSettingsScreen(
          connection: c,
          node: node,
          timeout: const Duration(milliseconds: 100),
        ),
      ),
    );
    expect(find.text('Admin: Ridge Relay'), findsOneWidget);
    await settle(tester, rounds: 3);
    // The answer timer runs on the test clock.
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester, rounds: 3);
    expect(find.textContaining('admin keys'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await closeAll(tester, controller, store);
  });

  testWidgets('telemetry screen shows charts and the range', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MeshStore.memory();
    final radio = RadioId.meshtastic(1);
    final node = NodeKey.meshtastic(2);
    final now = DateTime(2026, 11, 7, 12);
    await tester.runAsync(() async {
      for (var i = 0; i < 5; i++) {
        await store.addTelemetry(
          TelemetryPoint(
            radioId: radio,
            node: node,
            time: now.subtract(Duration(hours: 5 - i)),
            batteryLevel: 90 - i * 2,
            voltage: 4.1 - i * 0.02,
            channelUtilization: 10.0 + i,
          ),
        );
      }
    });
    await tester.pumpWidget(
      app(
        TelemetryScreen(
          store: store,
          radioId: radio,
          node: node,
          name: 'Ridge Relay',
          now: () => now,
        ),
      ),
    );
    await settle(tester, rounds: 5);
    expect(find.text('Telemetry: Ridge Relay'), findsOneWidget);
    expect(find.text('5 readings'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Low 82% · high 90%'), findsOneWidget);
    expect(find.text('Temperature'), findsNothing, reason: 'no sensor');
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      find.bySemanticsLabel('Battery: now 82%, low 82%, high 90%'),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });
}
