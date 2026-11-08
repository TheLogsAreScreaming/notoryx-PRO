import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';

import '../support/scripted_meshtastic.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  group('admin messages', () {
    test('get requests, including the zero-valued device section', () {
      // get_config_request = 5 (varint): DEVICE_CONFIG is 0 and must still
      // be written, or the node sees an empty message.
      expect(hex(AdminMessages.get(SectionKind.device)), '28 00');
      expect(hex(AdminMessages.get(SectionKind.lora)), '28 05');
      expect(hex(AdminMessages.get(SectionKind.position)), '28 01');
      // get_module_config_request = 7, TELEMETRY_CONFIG = 5.
      expect(hex(AdminMessages.get(SectionKind.telemetry)), '38 05');
      // get_owner_request = 3, get_device_metadata_request = 12.
      expect(hex(AdminMessages.get(SectionKind.owner)), '18 01');
      expect(hex(AdminMessages.getMetadata()), '60 01');
    });

    test('changes carry the session passkey (field 101)', () {
      final key = [1, 2, 3];
      expect(hex(AdminMessages.beginEdit(key)), '80 04 01 aa 06 03 01 02 03');
      expect(hex(AdminMessages.commitEdit(key)), '88 04 01 aa 06 03 01 02 03');
      expect(hex(AdminMessages.reboot(key)), '88 06 02 aa 06 03 01 02 03');
    });

    test('set wraps the section in Config / ModuleConfig, owner bare', () {
      final lora = SettingsSection(
        SectionKind.lora,
        Uint8List(0),
      ).withValue(LoraField.hopLimit, 4);
      // set_config = 34 (len) { Config.lora = 6 (len) { hop_limit = 8: 4 } }
      expect(
        hex(AdminMessages.set(lora, [7])),
        '92 02 04 32 02 40 04 aa 06 01 07',
      );
      final telemetry = SettingsSection(
        SectionKind.telemetry,
        Uint8List(0),
      ).withValue(TelemetryField.deviceInterval, 900);
      // set_module_config = 35 { ModuleConfig.telemetry = 6 { 1: 900 } }
      expect(
        hex(AdminMessages.set(telemetry, [7])),
        '9a 02 05 32 03 08 84 07 aa 06 01 07',
      );
      final owner = SettingsSection(
        SectionKind.owner,
        Uint8List(0),
      ).withValue(OwnerField.shortName, 'AB');
      // set_owner = 32 { short_name = 3: "AB" }
      expect(
        hex(AdminMessages.set(owner, [7])),
        '82 02 04 1a 02 41 42 aa 06 01 07',
      );
    });
  });

  group('settings sections', () {
    final raw = FakeAdminNode(1).sections[SectionKind.lora]!;

    test('editing keeps every field it did not touch, byte for byte', () {
      final s = SettingsSection(SectionKind.lora, raw);
      expect(s.number(LoraField.region), 1);
      expect(s.number(LoraField.hopLimit), 3);
      expect(s.changed, isFalse);
      final edited = s.withValue(LoraField.hopLimit, 5);
      expect(edited.changed, isTrue);
      expect(edited.changedFields, {LoraField.hopLimit});
      final back = readFields(edited.encode());
      expect(back.firstWhere((f) => f.number == 8).asInt, 5);
      expect(back.firstWhere((f) => f.number == 6).asInt, 0x3f800000);
      expect(back.firstWhere((f) => f.number == 200).asString, 'future field');
      expect(back.where((f) => f.number == 8), hasLength(1));
    });

    test('setting a value back to the original drops the change', () {
      final s = SettingsSection(SectionKind.lora, raw)
          .withValue(LoraField.hopLimit, 5)
          .withValue(LoraField.hopLimit, 3)
          .withValue(LoraField.txEnabled, true);
      expect(s.changed, isFalse);
    });

    test('turning a flag off removes it (proto3 default)', () {
      final s = SettingsSection(
        SectionKind.lora,
        raw,
      ).withValue(LoraField.usePreset, false);
      expect(s.flag(LoraField.usePreset), isFalse);
      expect(
        readFields(s.encode()).where((f) => f.number == LoraField.usePreset),
        isEmpty,
      );
    });

    test('negative transmit power survives', () {
      final s = SettingsSection(
        SectionKind.lora,
        (ProtoWriter()..uint(LoraField.txPower, -3)).toBytes(),
      );
      expect(s.signed(LoraField.txPower), -3);
      final e = SettingsSection(
        SectionKind.lora,
        s.withValue(LoraField.txPower, -5).encode(),
      );
      expect(e.signed(LoraField.txPower), -5);
    });

    test('answers are read back into sections', () {
      final answer =
          (ProtoWriter()
                ..bytes(
                  AdminField.getConfigResponse,
                  (ProtoWriter()..bytes(6, raw, always: true)).toBytes(),
                )
                ..bytes(AdminField.sessionPasskey, [5, 5]))
              .toBytes();
      final reply = AdminReply.decode(answer);
      expect(reply.passkey, [5, 5]);
      expect(reply.section(SectionKind.lora)!.number(LoraField.region), 1);
      expect(reply.section(SectionKind.telemetry), isNull, reason: 'other');
      // A section at all-defaults arrives empty.
      final empty = AdminReply.decode(
        (ProtoWriter()..bytes(
              AdminField.getConfigResponse,
              (ProtoWriter()..bytes(1, [], always: true)).toBytes(),
            ))
            .toBytes(),
      );
      expect(empty.section(SectionKind.device)!.number(DeviceField.role), 0);
    });
  });

  test('telemetry with sensor readings', () {
    final env =
        (ProtoWriter()
              ..fixed32(1, 0x41b40000) // 22.5 °C
              ..fixed32(2, 0x42480000) // 50 %
              ..fixed32(3, 0x447d4000)) // 1013 hPa
            .toBytes();
    final t = Telemetry.decode(
      (ProtoWriter()
            ..fixed32(1, 1762500000)
            ..bytes(3, env))
          .toBytes(),
    );
    expect(t.time, 1762500000);
    expect(t.environment!.temperature, 22.5);
    expect(t.environment!.relativeHumidity, 50);
    expect(t.environment!.barometricPressure, 1013);
    expect(t.device, isNull);
  });

  group('session', () {
    late ScriptedMeshtasticLink link;
    late MeshtasticSession session;
    late FakeAdminNode local;
    late FakeAdminNode remote;

    setUp(() async {
      link = ScriptedMeshtasticLink();
      local = FakeAdminNode(link.myNode);
      remote = FakeAdminNode(0x0badcafe);
      link.onPacket = (p) => [
        ...local(p, myNode: link.myNode),
        ...remote(p, myNode: link.myNode),
      ];
      await link.open();
      session = MeshtasticSession(link);
      await session.handshake();
    });

    tearDown(() => session.dispose());

    test('reads this radio’s settings with plain admin packets', () async {
      final lora = await session.readSection(link.myNode, SectionKind.lora);
      expect(lora.number(LoraField.region), 1);
      final p = local.packets.single;
      expect(p.to, link.myNode);
      expect(p.decoded!.portnum, PortNum.admin);
      expect(p.decoded!.wantResponse, isTrue);
      expect(p.pkiEncrypted, isFalse);
    });

    test(
      'saves a batch: begin, each change, commit, all with the passkey',
      () async {
        final lora = await session.readSection(link.myNode, SectionKind.lora);
        final owner = await session.readSection(link.myNode, SectionKind.owner);
        await session.writeSections(link.myNode, [
          lora.withValue(LoraField.hopLimit, 5),
          owner, // unchanged: not sent
          owner.withValue(OwnerField.longName, 'Base Camp 2'),
        ]);
        await pumpEventQueue();
        expect(local.fields, [
          AdminField.getConfigRequest,
          AdminField.getOwnerRequest,
          AdminField.beginEditSettings,
          AdminField.setConfig,
          AdminField.setOwner,
          AdminField.commitEditSettings,
        ]);
        for (final r in local.received.skip(2)) {
          expect(r.$3, local.passkey);
        }
        final saved = SettingsSection(
          SectionKind.lora,
          local.sections[SectionKind.lora]!,
        );
        expect(saved.number(LoraField.hopLimit), 5);
        expect(saved.number(LoraField.region), 1, reason: 'rest kept');
        expect(
          SettingsSection(
            SectionKind.owner,
            local.sections[SectionKind.owner]!,
          ).text(OwnerField.longName),
          'Base Camp 2',
        );
      },
    );

    test('without a recent passkey it asks for one first', () async {
      await session.writeSections(link.myNode, [
        SettingsSection(
          SectionKind.device,
          Uint8List(0),
        ).withValue(DeviceField.role, MeshtasticRole.clientMute),
      ]);
      await pumpEventQueue();
      expect(local.fields, [
        AdminField.getMetadataRequest,
        AdminField.beginEditSettings,
        AdminField.setConfig,
        AdminField.commitEditSettings,
      ]);
    });

    test('other nodes are reached with public-key encryption', () async {
      final owner = await session.readSection(0x0badcafe, SectionKind.owner);
      expect(owner.text(OwnerField.longName), 'Ridge Relay');
      final p = remote.packets.single;
      expect(p.to, 0x0badcafe);
      expect(p.pkiEncrypted, isTrue);
      expect(local.packets, isEmpty);

      await session.rebootNode(0x0badcafe);
      await pumpEventQueue();
      expect(remote.fields.last, AdminField.rebootSeconds);
      expect(remote.packets.last.wantAck, isTrue);
    });

    test('a node that won’t answer times out', () async {
      remote.answers = false;
      await expectLater(
        session.readSection(
          0x0badcafe,
          SectionKind.lora,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<MeshtasticTimeout>()),
      );
    });
  });
}
