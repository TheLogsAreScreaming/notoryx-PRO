import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/bytes.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/admin_screens.dart';

import '../support/scripted_meshcore.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

final repeaterKey = RadioFrames.key(0xa1);

Uint8List loginOk({bool admin = true}) =>
    Uint8List.fromList([0x85, admin ? 1 : 0, ...repeaterKey.sublist(0, 6)]);

Uint8List status() {
  final w = ByteWriter()
    ..u8(0x87)
    ..u8(0)
    ..bytes(repeaterKey.sublist(0, 6))
    ..bytes([0x10, 0x0e]) // 3600 mV
    ..bytes([2, 0]) // queue
    ..bytes([0x8a, 0xff]) // noise -118
    ..bytes([0xa6, 0xff]) // rssi -90
    ..u32(1000)
    ..u32(400)
    ..u32(600) // airtime s
    ..u32(90000) // uptime: 1 d 1 h
    ..u32(1)
    ..u32(2)
    ..u32(3)
    ..u32(4)
    ..bytes([0, 0])
    ..bytes([0x18, 0x00]); // snr 6.0
  return w.toBytes();
}

Uint8List cliReply(String text) {
  final w = ByteWriter()
    ..u8(16)
    ..u8(20)
    ..u8(0)
    ..u8(0)
    ..bytes(repeaterKey.sublist(0, 6))
    ..u8(0xff)
    ..u8(1) // TXT_TYPE_CLI_DATA
    ..u32(1762500000)
    ..bytes(utf8.encode(text));
  return w.toBytes();
}

/// A companion that remembers settings changes and answers admin requests.
class Companion {
  String name = 'Ridge Base';
  int power = 22;
  final inbox = <Uint8List>[];
  final commands = <int>[];

  Uint8List selfInfo() {
    final f = RadioFrames.selfInfo(name: name);
    f[2] = power;
    return f;
  }

  List<Uint8List> call(Uint8List cmd) {
    commands.add(cmd.first);
    return switch (cmd.first) {
      Cmd.appStart => [selfInfo()],
      Cmd.deviceQuery => [RadioFrames.deviceInfo()],
      Cmd.setDeviceTime => [RadioFrames.ok()],
      Cmd.getContacts => [
        RadioFrames.contactsStart(1),
        RadioFrames.contact(seed: 0xa1, name: 'Peak', type: 2, pathLength: 0),
        RadioFrames.endOfContacts(1),
      ],
      Cmd.getChannel => [RadioFrames.err(2)],
      Cmd.syncNextMessage => [
        inbox.isEmpty ? RadioFrames.noMore() : inbox.removeAt(0),
      ],
      Cmd.setAdvertName => () {
        name = utf8.decode(cmd.sublist(1));
        return [RadioFrames.ok()];
      }(),
      Cmd.setTxPower => () {
        power = cmd[1].toSigned(8);
        return [RadioFrames.ok()];
      }(),
      Cmd.setRadioParams ||
      Cmd.setAdvertLatLon ||
      Cmd.setOtherParams => [RadioFrames.ok()],
      Cmd.runCli => [
        Uint8List.fromList([29, ...utf8.encode('v1.18.0')]),
      ],
      Cmd.sendLogin => [
        RadioFrames.sent(ack: 1, timeoutMs: 10),
        utf8.decode(cmd.sublist(33)) == 'secret'
            ? loginOk()
            : Uint8List.fromList([0x86, 0, ...repeaterKey.sublist(0, 6)]),
      ],
      Cmd.sendStatusRequest => [
        RadioFrames.sent(ack: 2, timeoutMs: 10),
        status(),
      ],
      Cmd.sendText => () {
        if (cmd[1] == 1) {
          inbox.add(cliReply('> ${utf8.decode(cmd.sublist(13))}\nOK'));
          return [RadioFrames.sent(ack: 3), RadioFrames.waiting()];
        }
        return [RadioFrames.sent(ack: 4)];
      }(),
      _ => [RadioFrames.err(1)],
    };
  }
}

void main() {
  group('codec', () {
    test('settings commands', () {
      expect(
        toHex(
          MeshCoreCommands.setRadioParams(
            frequencyMHz: 910.525,
            bandwidthKHz: 62.5,
            spreadingFactor: 7,
            codingRate: 5,
          ),
        ),
        '0b'
        'bde40d00'
        '24f40000'
        '07'
        '05',
      );
      expect(
        () => MeshCoreCommands.setRadioParams(
          frequencyMHz: 100,
          bandwidthKHz: 125,
          spreadingFactor: 7,
          codingRate: 5,
        ),
        throwsArgumentError,
      );
      expect(MeshCoreCommands.setTxPower(-3), [12, 0xfd]);
      expect(
        toHex(MeshCoreCommands.setAdvertPosition(45.5, -122.25)),
        '0e'
        '6046b602'
        'f09cb6f8',
      );
      expect(
        MeshCoreCommands.setOtherParams(
          manualAddContacts: true,
          telemetryMode: 0x15,
          advertLocationPolicy: 1,
          multiAcks: 0,
        ),
        [38, 1, 0x15, 1, 0],
      );
      expect(utf8.decode(MeshCoreCommands.reboot().sublist(1)), 'reboot');
    });

    test('server commands', () {
      final login = MeshCoreCommands.sendLogin(repeaterKey, 'pw');
      expect(login.length, 1 + 32 + 2);
      expect(
        () => MeshCoreCommands.sendLogin(repeaterKey, 'x' * 16),
        throwsArgumentError,
      );
      expect(MeshCoreCommands.sendStatusRequest(repeaterKey).first, 27);
      expect(MeshCoreCommands.runCli('ver'), [66, ...'ver'.codeUnits]);
    });

    test('server answers decode', () {
      final ok = decodeFrame(loginOk()) as LoginResultPush;
      expect(ok.success, isTrue);
      expect(ok.isAdmin, isTrue);
      final fail =
          decodeFrame(
                Uint8List.fromList([0x86, 0, ...repeaterKey.sublist(0, 6)]),
              )
              as LoginResultPush;
      expect(fail.success, isFalse);
      final s = decodeFrame(status()) as RepeaterStatusPush;
      expect(s.batteryMv, 3600);
      expect(s.noiseFloor, -118);
      expect(s.lastRssi, -90);
      expect(s.uptimeSeconds, 90000);
      expect(s.lastSnr, 6.0);
      expect(
        (decodeFrame(Uint8List.fromList([29, 0x68, 0x69])) as CliReplyFrame)
            .text,
        'hi',
      );
    });
  });

  group('connection', () {
    late MeshStore store;
    late Companion radio;
    late AppController app;
    late MeshCoreConnection c;

    setUp(() async {
      store = MeshStore.memory();
      radio = Companion();
      app = AppController(
        store: store,
        links: FakeLinks(ScriptedMeshCoreLink(responder: radio.call)),
      );
      c =
          await app.connect(
                const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
              )
              as MeshCoreConnection;
    });

    tearDown(() async {
      await app.shutdown();
      await store.close();
    });

    test('settings: only changes are sent, then read back', () async {
      radio.commands.clear();
      final saved = await c.applySettings(
        c.settings!.copyWith(name: 'Summit Base', txPower: 17),
      );
      expect(radio.commands, [Cmd.setAdvertName, Cmd.setTxPower, Cmd.appStart]);
      expect(saved.name, 'Summit Base');
      expect(saved.txPower, 17);
      expect(c.radio!.name, 'Summit Base');
      expect((await store.radios()).single.name, 'Summit Base');
    });

    test('settings: radio and other params when changed', () async {
      radio.commands.clear();
      await c.applySettings(
        c.settings!.copyWith(spreadingFactor: 9, manualAddContacts: true),
      );
      expect(radio.commands, [
        Cmd.setRadioParams,
        Cmd.setOtherParams,
        Cmd.appStart,
      ]);
    });

    test('companion command line', () async {
      expect(c.hasCompanionCli, isTrue);
      expect(await c.runCli('ver'), 'v1.18.0');
    });

    test('repeater login, status and command line', () async {
      final peak = (await store.nodes(c.radio!.id)).single;
      expect((await c.login(peak, 'nope')).success, isFalse);
      final ok = await c.login(peak, 'secret');
      expect(ok.isAdmin, isTrue);
      final s = await c.serverStatus(peak);
      expect(s.packetsReceived, 1000);
      expect(await c.serverCommand(peak, 'neighbors'), '> neighbors\nOK');
      // The reply is not an inbox message.
      expect(
        await store.messages(DirectConversation(c.radio!.id, peak.key)),
        isEmpty,
      );
    });
  });

  testWidgets('settings screen checks values and saves', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MeshStore.memory();
    final radio = Companion();
    final app = AppController(
      store: store,
      links: FakeLinks(ScriptedMeshCoreLink(responder: radio.call)),
    );
    final c =
        (await tester.runAsync(
              () => app.connect(
                const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
              ),
            ))!
            as MeshCoreConnection;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MeshCoreSettingsScreen(connection: c),
      ),
    );
    await tester.enterText(find.byKey(const Key('settings-frequency')), '50');
    await tester.enterText(find.byKey(const Key('settings-name')), '');
    await tester.tap(find.text('Save to radio'));
    await tester.pump();
    expect(find.text('1 to 31 bytes'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('settings-name')), 'Camp 2');
    await tester.enterText(
      find.byKey(const Key('settings-frequency')),
      '910.525',
    );
    await tester.tap(find.text('Save to radio'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.textContaining('Saved.'), findsOneWidget);
    expect(radio.name, 'Camp 2');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await app.shutdown();
    });
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });

  testWidgets('server screen: log in, status, console', (tester) async {
    final store = MeshStore.memory();
    final radio = Companion();
    final app = AppController(
      store: store,
      links: FakeLinks(ScriptedMeshCoreLink(responder: radio.call)),
    );
    final c =
        (await tester.runAsync(
              () => app.connect(
                const TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore),
              ),
            ))!
            as MeshCoreConnection;
    final peak = (await tester.runAsync(
      () => store.nodes(c.radio!.id),
    ))!.single;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ServerScreen(connection: c, node: peak),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    final consoleButton = find.widgetWithText(OutlinedButton, 'Command line');
    expect(tester.widget<OutlinedButton>(consoleButton).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('server-password')), 'secret');
    await tester.tap(find.text('Log in'));
    await settle();
    expect(find.text('Logged in as admin'), findsOneWidget);
    await tester.tap(find.text('Get status'));
    await settle();
    expect(find.text('3.60 V'), findsOneWidget);
    expect(find.text('1 d 1 h'), findsOneWidget);
    expect(find.text('-118 dBm'), findsOneWidget);

    await tester.tap(consoleButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ver');
    await tester.tap(find.byTooltip('Run'));
    await settle();
    expect(find.textContaining('OK'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await app.shutdown();
    });
    final closing = store.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => closing);
  });
}
