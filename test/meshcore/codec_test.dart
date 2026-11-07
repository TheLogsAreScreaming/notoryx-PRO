import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';

import '../support/scripted_meshcore.dart';

void main() {
  group('stream framing', () {
    test('wraps commands with < and a little-endian length', () {
      expect(wrapStreamFrame(Uint8List.fromList([0x16, 0x03])), [
        0x3c,
        2,
        0,
        0x16,
        0x03,
      ]);
      expect(() => wrapStreamFrame(Uint8List(0)), throwsArgumentError);
      expect(() => wrapStreamFrame(Uint8List(177)), throwsArgumentError);
    });

    test('decoder reassembles split frames and skips junk', () {
      final d = StreamFrameDecoder();
      expect(d.add('boot ok\r\n'.codeUnits), isEmpty);
      expect(d.add([0x3e, 3]), isEmpty);
      expect(d.add([0, 0x00, 0x01]), isEmpty);
      final frames = d.add([0x02, 0x3e, 1, 0, 0x0a, 0x3e]);
      expect(frames, [
        [0x00, 0x01, 0x02],
        [0x0a],
      ]);
      expect(d.add([1, 0, 0x83]), [
        [0x83],
      ]);
    });

    test('decoder treats impossible lengths as noise', () {
      final d = StreamFrameDecoder(maxLength: 10);
      expect(d.add([0x3e, 0, 0, 0x3e, 0xff, 0xff, 0x3e, 1, 0, 0x00]), [
        [0x00],
      ]);
    });
  });

  group('commands', () {
    test('APP_START carries 7 reserved bytes and the app name', () {
      expect(
        toHex(MeshCoreCommands.appStart('mccli')),
        '0100000000000000'
        '6d63636c69',
      );
    });

    test('DEVICE_QUERY asks for protocol 3', () {
      expect(MeshCoreCommands.deviceQuery(), [0x16, 0x03]);
    });

    test('channel message matches the protocol docs example', () {
      final f = MeshCoreCommands.sendChannelText(
        channel: 1,
        text: 'Hello',
        timestamp: 1234567890,
      );
      expect(toHex(f), '030001d202964948656c6c6f');
    });

    test('direct message sends a 6-byte key prefix', () {
      final f = MeshCoreCommands.sendText(
        publicKey: RadioFrames.key(0x40),
        text: 'hi',
        timestamp: 1,
        attempt: 2,
      );
      expect(
        toHex(f),
        '0200020100000040414243444568'
        '69',
      );
    });

    test('text over 160 bytes is refused', () {
      expect(
        () => MeshCoreCommands.sendChannelText(
          channel: 0,
          text: 'x' * 161,
          timestamp: 0,
        ),
        throwsArgumentError,
      );
      expect(
        MeshCoreCommands.sendChannelText(
          channel: 0,
          text: 'é' * 80,
          timestamp: 0,
        ).length,
        7 + 160,
      );
    });

    test('SET_CHANNEL is 50 bytes and refuses a named zero key', () {
      final secret = fromHex('8b3387e9c5cdea6ac9e5edbaa115cd72');
      final f = MeshCoreCommands.setChannel(0, 'Public', secret);
      expect(f.length, 50);
      expect(f.sublist(0, 8), [0x20, 0, ...'Public'.codeUnits]);
      expect(f.sublist(34), secret);
      expect(
        () => MeshCoreCommands.setChannel(1, 'Oops', Uint8List(16)),
        throwsArgumentError,
      );
      expect(MeshCoreCommands.setChannel(1, '', Uint8List(16)).length, 50);
      expect(
        () => MeshCoreCommands.setChannel(1, 'x' * 32, secret),
        throwsArgumentError,
      );
    });

    test('GET_CONTACTS adds since only when given', () {
      expect(MeshCoreCommands.getContacts(), [4]);
      expect(MeshCoreCommands.getContacts(since: 0x01020304), [4, 4, 3, 2, 1]);
    });
  });

  group('frames', () {
    test('SELF_INFO', () {
      final f = decodeFrame(RadioFrames.selfInfo()) as SelfInfoFrame;
      expect(f.name, 'Ridge Base');
      expect(f.txPower, 22);
      expect(f.publicKey, RadioFrames.key(0x10));
      expect(f.latitude, closeTo(45.123456, 1e-9));
      expect(f.longitude, closeTo(-122.654321, 1e-9));
      expect(f.frequencyMHz, closeTo(910.525, 1e-9));
      expect(f.bandwidthKHz, closeTo(62.5, 1e-9));
      expect(f.spreadingFactor, 7);
      expect(f.codingRate, 5);
    });

    test('DEVICE_INFO', () {
      final f = decodeFrame(RadioFrames.deviceInfo()) as DeviceInfoFrame;
      expect(f.firmwareCode, 14);
      expect(f.maxContacts, 350);
      expect(f.maxChannels, 40);
      expect(f.model, 'Heltec V3');
      expect(f.version, 'v1.18.0');
      expect(f.buildDate, '06 Oct 2026');
      expect(f.clientRepeat, isFalse);
      expect(f.pathHashMode, 1);
    });

    test('old DEVICE_INFO has just the version', () {
      final f = decodeFrame(Uint8List.fromList([13, 2])) as DeviceInfoFrame;
      expect(f.firmwareCode, 2);
      expect(f.maxChannels, isNull);
    });

    test('contact frame is 148 bytes with path, position and lastmod', () {
      final bytes = RadioFrames.contact();
      expect(bytes.length, 148);
      final c = decodeFrame(bytes) as ContactFrame;
      expect(c.name, 'Alpha');
      expect(c.type, NodeType.chat);
      expect(c.hops, 2);
      expect(c.path, [0xaa, 0xbb]);
      expect(c.latitude, closeTo(44.5, 1e-9));
      expect(c.lastModified, 1000);
      expect(c.isPush, isFalse);
    });

    test('a flood-only contact has no path', () {
      final c =
          decodeFrame(RadioFrames.contact(pathLength: 0xff)) as ContactFrame;
      expect(c.hasPath, isFalse);
      expect(c.hops, isNull);
      expect(c.path, isEmpty);
    });

    test('NEW_ADVERT push is a contact flagged as new', () {
      final c = decodeFrame(RadioFrames.contact(code: 0x8a)) as ContactFrame;
      expect(c.fromNewAdvert, isTrue);
      expect(c.isPush, isTrue);
    });

    test('channel message v3 splits the sender name', () {
      final m =
          decodeFrame(RadioFrames.channelMessageV3()) as ChannelMessageFrame;
      expect(m.snr, 6.5);
      expect(m.senderName, 'Bob');
      expect(m.body, 'hello all');
      expect(m.pathLength, 3);
    });

    test('signed direct message skips the signature', () {
      final m =
          decodeFrame(RadioFrames.contactMessageV3(text: 'yo', signed: true))
              as ContactMessageFrame;
      expect(m.text, 'yo');
      expect(m.textType, TextType.signedPlain);
      expect(m.signature, [1, 2, 3, 4]);
      expect(m.snr, -2.0);
      expect(m.keyPrefix, RadioFrames.key(0x40).sublist(0, 6));
    });

    test('SENT, SEND_CONFIRMED, battery, channel info, errors', () {
      final s = decodeFrame(RadioFrames.sent(flood: true)) as SentFrame;
      expect(s.flood, isTrue);
      expect(s.ackCode, 0xdeadbeef);
      expect(s.timeoutMs, 9000);

      final c = decodeFrame(RadioFrames.sendConfirmed(7)) as SendConfirmedPush;
      expect(c.ackCode, 7);
      expect(c.roundTripMs, 1450);

      final b =
          decodeFrame(fromHex('0c 100e 0a000000 00010000')) as BatteryFrame;
      expect(b.millivolts, 3600);
      expect(b.usedKb, 10);
      expect(b.totalKb, 256);

      final info =
          decodeFrame(
                Uint8List.fromList([
                  18,
                  0,
                  ...'Public'.codeUnits,
                  ...List.filled(26, 0),
                  ...fromHex('8b3387e9c5cdea6ac9e5edbaa115cd72'),
                ]),
              )
              as ChannelInfoFrame;
      expect(info.name, 'Public');
      expect(info.isEmpty, isFalse);

      expect(
        (decodeFrame(RadioFrames.err(2)) as ErrorFrame).code,
        MeshCoreErrorCode.notFound,
      );
      expect(
        (decodeFrame(Uint8List.fromList([1])) as ErrorFrame).code,
        MeshCoreErrorCode.unknown,
      );
    });

    test('short and unknown frames never throw', () {
      expect(decodeFrame(Uint8List(0)), isA<MalformedFrame>());
      expect(decodeFrame(Uint8List.fromList([5, 1, 2])), isA<MalformedFrame>());
      final u = decodeFrame(Uint8List.fromList([0x99, 1]));
      expect(u, isA<UnknownFrame>());
      expect(u.isPush, isTrue);
    });
  });
}
