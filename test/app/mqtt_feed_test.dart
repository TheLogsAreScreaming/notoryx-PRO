import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/mqtt_feed.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart';
import 'package:notoryx_pro/radio/radio_link.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final now = DateTime.utc(2026, 11, 8);

const cfg = MqttFeedConfig(
  id: '1',
  name: 'Test',
  protocol: RadioProtocol.meshtastic,
  host: 'broker',
  topic: 'msh/#',
);

Uint8List envelope() {
  final packet = ProtoWriter()
    ..fixed32(1, 0x12345678)
    ..fixed32(2, 0xffffffff)
    ..bytes(5, [1, 2, 3]);
  return (ProtoWriter()
        ..bytes(1, packet.toBytes())
        ..string(2, 'LongFast')
        ..string(3, '!abcd1234'))
      .toBytes();
}

class FakeBroker implements MqttBroker {
  void Function(Uint8List)? send;
  void Function(bool)? state;
  bool closed = false;
  Object? failure;

  @override
  Future<void> open({
    required void Function(Uint8List payload) onMessage,
    required void Function(bool connected) onConnection,
  }) async {
    if (failure != null) throw failure!;
    send = onMessage;
    state = onConnection;
    onConnection(true);
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('parsing', () {
    test('a Meshtastic envelope', () {
      final e = parseFeedMessage(RadioProtocol.meshtastic, envelope(), now)!;
      expect(e.from, '!12345678');
      expect(e.to, isNull);
      expect(e.kind, 'Encrypted');
      expect(e.encrypted, isTrue);
      expect(e.detail, 'LongFast · !abcd1234');
      expect(e.path.viaMqtt, isTrue);
    });

    test('a MeshCore observer report', () {
      final payload = utf8.encode(
        jsonEncode({
          'origin': 'Ridge',
          'raw': '1100AABBCCDD',
          'SNR': '7.5',
          'RSSI': -80,
        }),
      );
      final e = parseFeedMessage(
        RadioProtocol.meshcore,
        Uint8List.fromList(payload),
        now,
      )!;
      expect(e.protocol, RadioProtocol.meshcore);
      expect(e.path.snr, 7.5);
      expect(e.path.rssi, -80);
      expect(e.detail, startsWith('Ridge'));
    });

    test('junk from a broker is ignored, never thrown', () {
      final junk = [
        Uint8List(0),
        Uint8List.fromList([0xff, 0xff, 0xff]),
        Uint8List.fromList(utf8.encode('not json')),
        Uint8List.fromList(utf8.encode('{"raw":"zz"}')),
        Uint8List.fromList(utf8.encode('{"raw":"abc"}')),
        Uint8List.fromList(utf8.encode('[1,2]')),
      ];
      for (final b in junk) {
        for (final p in RadioProtocol.values) {
          expect(parseFeedMessage(p, b, now), isNull, reason: '$p $b');
        }
      }
    });
  });

  test('a feed connects, logs packets and stops', () async {
    final broker = FakeBroker();
    final feed = MqttFeed(cfg, (_) => broker);
    await feed.start();
    expect(feed.state, MqttFeedState.connected);
    broker.send!(envelope());
    broker.send!(Uint8List.fromList([0xff]));
    expect(feed.log.entries, hasLength(1));
    broker.state!(false);
    expect(feed.state, MqttFeedState.connecting);
    await feed.stop();
    expect(feed.state, MqttFeedState.off);
    expect(broker.closed, isTrue);
  });

  test('a failed connection says why and can be retried', () async {
    final broker = FakeBroker()..failure = 'no route';
    final feed = MqttFeed(cfg, (_) => broker);
    await feed.start();
    expect(feed.state, MqttFeedState.failed);
    expect(feed.error, 'no route');
    broker.failure = null;
    await feed.start();
    expect(feed.state, MqttFeedState.connected);
  });

  test('feeds are saved and removed', () async {
    final store = MeshStore.memory();
    final a = MqttFeeds(store, brokers: (_) => FakeBroker());
    await a.add(cfg);
    final b = MqttFeeds(store, brokers: (_) => FakeBroker());
    await b.load();
    expect(b.feeds.single.config.host, 'broker');
    await b.remove(b.feeds.single);
    final c = MqttFeeds(store, brokers: (_) => FakeBroker());
    await c.load();
    expect(c.feeds, isEmpty);
    await store.close();
  });
}
