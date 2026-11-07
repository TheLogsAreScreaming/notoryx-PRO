import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_connection.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/app/retry_policy.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import '../support/scripted_meshcore.dart';
import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

const fast = RetryPolicy(
  directAttempts: 2,
  floodAttempts: 2,
  minWait: Duration(milliseconds: 30),
  extraWait: Duration(milliseconds: 10),
  meshtasticResends: 1,
  meshtasticTimeout: Duration(milliseconds: 150),
);

/// A companion whose SENT replies come from [sent] (ack codes count up).
Responder companion({bool flood = false}) {
  var ack = 0x100;
  return (cmd) => switch (cmd.first) {
    Cmd.appStart => [RadioFrames.selfInfo()],
    Cmd.deviceQuery => [RadioFrames.deviceInfo()],
    Cmd.setDeviceTime => [RadioFrames.ok()],
    Cmd.getContacts => [
      RadioFrames.contactsStart(0),
      RadioFrames.endOfContacts(0),
    ],
    Cmd.getChannel => [RadioFrames.err(2)],
    Cmd.syncNextMessage => [RadioFrames.noMore()],
    Cmd.sendText => [RadioFrames.sent(ack: ack++, flood: flood, timeoutMs: 10)],
    Cmd.resetPath => [RadioFrames.ok()],
    _ => [RadioFrames.err(1)],
  };
}

Future<StoredMessage> waitForMessage(
  MeshStore store,
  int id,
  bool Function(Message m) done, {
  int ms = 3000,
}) async {
  final sw = Stopwatch()..start();
  while (true) {
    final m = (await store.message(id))!;
    if (done(m.message)) return m;
    if (sw.elapsedMilliseconds > ms) {
      fail(
        'timed out; last: ${m.message.delivery} after ${m.message.attempts}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MeshStore store;
  setUp(() => store = MeshStore.memory());
  tearDown(() => store.close());

  Future<(AppController, RadioConnection)> connect(
    RadioLink link,
    RadioTarget target,
  ) async {
    final app = AppController(
      store: store,
      links: FakeLinks(link),
      retries: fast,
    );
    final c = await app.connect(target);
    return (app, c);
  }

  const mcTarget = TcpTarget(host: 'mc', protocol: RadioProtocol.meshcore);
  const mtTarget = TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic);
  final peer = NodeKey.meshcore(toHex(RadioFrames.key(0x40)));

  group('MeshCore', () {
    test('direct attempts, then reset path and flood, then give up', () async {
      final link = ScriptedMeshCoreLink(responder: companion());
      final (app, c) = await connect(link, mcTarget);
      final id = await c.sendText(DirectConversation(c.radio!.id, peer), 'hi');
      final m = await waitForMessage(store, id, (m) => m.delivery is Failed);
      expect(
        (m.message.delivery as Failed).reason,
        'No acknowledgement after 4 tries',
      );
      expect(m.message.attempts, 4);
      final sends = link.commands
          .where(
            (cmd) => cmd.first == Cmd.sendText || cmd.first == Cmd.resetPath,
          )
          .map((cmd) => cmd.first)
          .toList();
      expect(sends, [
        Cmd.sendText,
        Cmd.sendText,
        Cmd.resetPath,
        Cmd.sendText,
        Cmd.sendText,
      ]);
      // Every attempt carries the same timestamp and a rising attempt byte.
      final texts = link.commands
          .where((cmd) => cmd.first == Cmd.sendText)
          .toList();
      expect(texts.map((t) => t[2]), [0, 1, 2, 3]);
      expect(
        texts.map((t) => t.sublist(3, 7).toString()).toSet(),
        hasLength(1),
      );
      await app.shutdown();
    });

    test("an earlier attempt's ack still counts as delivered", () async {
      final link = ScriptedMeshCoreLink(responder: companion());
      final (app, c) = await connect(link, mcTarget);
      final id = await c.sendText(DirectConversation(c.radio!.id, peer), 'hi');
      await waitForMessage(store, id, (m) => m.attempts >= 2);
      link.push(RadioFrames.sendConfirmed(0x100)); // ack of attempt 1
      final m = await waitForMessage(store, id, (m) => m.delivery is Delivered);
      expect(m.message.attempts, 2);
      await app.shutdown();
    });

    test('a contact with no route floods from the start', () async {
      final link = ScriptedMeshCoreLink(responder: companion(flood: true));
      final (app, c) = await connect(link, mcTarget);
      final id = await c.sendText(DirectConversation(c.radio!.id, peer), 'hi');
      final m = await waitForMessage(store, id, (m) => m.delivery is Failed);
      expect(m.message.attempts, 2);
      expect(link.commands.where((cmd) => cmd.first == Cmd.resetPath), isEmpty);
      await app.shutdown();
    });

    test('a failed message can be sent again by hand', () async {
      final link = ScriptedMeshCoreLink(responder: companion());
      final (app, c) = await connect(link, mcTarget);
      final id = await c.sendText(DirectConversation(c.radio!.id, peer), 'hi');
      await waitForMessage(store, id, (m) => m.delivery is Failed);
      await c.resend(id);
      await waitForMessage(store, id, (m) => m.delivery is Sent);
      link.push(RadioFrames.sendConfirmed(0x104));
      await waitForMessage(store, id, (m) => m.delivery is Delivered);
      expect(
        (await store.messages(DirectConversation(c.radio!.id, peer))),
        hasLength(1),
      );
      await app.shutdown();
    });
  });

  group('Meshtastic', () {
    test('no ack from the mesh: sends once more, then delivered', () async {
      final link = ScriptedMeshtasticLink();
      var tries = 0;
      link.onPacket = (p) {
        tries++;
        return [
          NodeFrames.routing(
            from: tries == 1 ? link.myNode : p.to,
            to: link.myNode,
            requestId: p.id,
            error: tries == 1 ? 5 : 0, // MAX_RETRANSMIT, then ack
          ),
        ];
      };
      final (app, c) = await connect(link, mtTarget);
      final dm = DirectConversation(
        c.radio!.id,
        NodeKey.meshtastic(0x0badcafe),
      );
      final id = await c.sendText(dm, 'hello');
      final m = await waitForMessage(store, id, (m) => m.delivery is Delivered);
      expect(m.message.attempts, 2);
      expect(tries, 2);
      await app.shutdown();
    });

    test('a refusal is not retried', () async {
      final link = ScriptedMeshtasticLink();
      link.onPacket = (p) => [
        NodeFrames.routing(
          from: link.myNode,
          to: link.myNode,
          requestId: p.id,
          error: 35,
        ),
      ];
      final (app, c) = await connect(link, mtTarget);
      final dm = DirectConversation(
        c.radio!.id,
        NodeKey.meshtastic(0x0badcafe),
      );
      final id = await c.sendText(dm, 'hello');
      final m = await waitForMessage(store, id, (m) => m.delivery is Failed);
      expect(
        (m.message.delivery as Failed).reason,
        "The node's key is unknown",
      );
      expect(m.message.attempts, 1);
      await app.shutdown();
    });

    test('no news at all ends as not acknowledged', () async {
      final link = ScriptedMeshtasticLink();
      final (app, c) = await connect(link, mtTarget);
      final dm = DirectConversation(
        c.radio!.id,
        NodeKey.meshtastic(0x0badcafe),
      );
      final id = await c.sendText(dm, 'anyone?');
      final m = await waitForMessage(store, id, (m) => m.delivery is Failed);
      expect((m.message.delivery as Failed).reason, 'No acknowledgement');
      await app.shutdown();
    });
  });
}
