import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshtastic.dart';

/// One scripted node per address.
class AddressedLinks extends LinkFactory {
  final links = <String, ScriptedMeshtasticLink>{};
  var _next = 0xa1b2c3d0;

  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) =>
      links[target.address] = ScriptedMeshtasticLink(myNode: _next++);
}

TcpTarget node(String host) =>
    TcpTarget(host: host, protocol: RadioProtocol.meshtastic);

void main() {
  late MeshStore store;
  late AddressedLinks links;
  late AppController app;

  setUp(() {
    store = MeshStore.memory();
    links = AddressedLinks();
    app = AppController(store: store, links: links);
  });

  tearDown(() async {
    await app.shutdown();
    await store.close();
  });

  test('two radios of the same mesh stay connected together', () async {
    final a = await app.connect(node('a'));
    final b = await app.connect(node('b'));
    expect(app.connections, [a, b]);
    expect(a.radio!.id, isNot(b.radio!.id));
    expect(app.connectionForRadio(a.radio!.id), same(a));
    expect(app.connectionForRadio(b.radio!.id), same(b));
    expect((await store.radios()).length, 2);

    // Messages go through the radio the conversation belongs to.
    final channel = ChannelConversation(b.radio!.id, 0);
    await app.connectionForRadio(channel.radioId)!.sendText(channel, 'hi');
    expect(links.links['tcp:b:4403']!.sent.last.packet, isNotNull);
    expect(
      links.links['tcp:a:4403']!.sent.where((s) => s.packet != null),
      isEmpty,
    );
  });

  test('connecting to the same radio again replaces it', () async {
    final first = await app.connect(node('a'));
    final again = await app.connect(node('a'));
    expect(app.connections, [again]);
    expect(first, isNot(same(again)));
  });

  test('at most four radios', () async {
    for (final h in ['a', 'b', 'c', 'd']) {
      await app.connect(node(h));
    }
    expect(app.canAddRadio, isFalse);
    await expectLater(app.connect(node('e')), throwsA(isA<TooManyRadios>()));
    await app.disconnect(app.connections.first);
    expect(app.canAddRadio, isTrue);
  });

  test('addresses tell transports apart', () {
    expect(node('h').address, 'tcp:h:4403');
    expect(
      const BleTarget(
        deviceId: 'X',
        name: 'n',
        protocol: RadioProtocol.meshcore,
      ).address,
      'ble:X',
    );
  });
}
