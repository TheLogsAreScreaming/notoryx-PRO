import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/automations.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/places.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

final radio = RadioId.meshtastic(0xa1);
final peak = NodeKey.meshtastic(0x22);
final chat = ChannelConversation(radio, 0);

class Calls {
  final sent = <(String, String)>[];
  final alerts = <(String, String)>[];
  final posts = <(Uri, String)>[];
  final joined = <(RadioId, String)>[];
  int sounds = 0;
  bool connected = true;

  AutomationHooks get hooks => AutomationHooks(
    send: (c, t) async {
      sent.add((c.key, t));
      return connected;
    },
    alert: (title, body) async => alerts.add((title, body)),
    playSound: () async => sounds++,
    joinChannel: (r, link) async {
      joined.add((r, link));
      return true;
    },
    post: (url, json) async {
      posts.add((url, json));
      return 204;
    },
  );
}

Node node({int? battery, GeoPoint? at, DateTime? heard}) => Node(
  key: peak,
  radioId: radio,
  name: 'Peak',
  batteryPercent: battery,
  position: at,
  lastHeard: heard,
);

Message msg(String text, DateTime at) => Message(
  conversation: chat,
  text: text,
  outgoing: false,
  sentAt: at,
  receivedAt: at,
  delivery: const Received(),
  senderName: 'Ann',
);

void main() {
  var now = DateTime(2026, 11, 13, 18, 0, 5); // a Friday
  late MeshStore store;
  late Calls calls;
  late AutomationEngine engine;

  setUp(() {
    now = DateTime(2026, 11, 13, 18, 0, 5);
    store = MeshStore.memory();
    calls = Calls();
    engine = AutomationEngine(store: store, hooks: calls.hooks, now: () => now);
  });
  tearDown(() => store.close());

  Automation rule(
    List<AutoTrigger> when,
    List<AutoAction> then, {
    bool all = false,
    int id = 1,
  }) => Automation(
    id: id,
    name: 'R$id',
    matchAll: all,
    triggers: when,
    actions: then,
  );

  test('settings survive JSON with every trigger and action', () {
    final s = AutomationSettings(
      webhooks: true,
      rules: [
        Automation(
          id: 3,
          name: 'All of it',
          matchAll: true,
          cooldown: const Duration(minutes: 15),
          triggers: [
            BatteryTrigger(radio: radio, node: peak, below: 20),
            const TimeTrigger(hour: 7, minute: 30, weekdays: {1, 5}),
            GeofenceTrigger(place: 4, enter: false, radio: radio, node: peak),
            MessageTrigger(
              contains: 'help',
              conversation: chat,
              directOnly: true,
            ),
            PresenceTrigger(
              radio: radio,
              node: peak,
              online: false,
              after: const Duration(hours: 1),
            ),
          ],
          actions: [
            SendAction(conversation: chat, text: '{node} at {battery}%'),
            const AlertAction('Look'),
            JoinChannelAction(radio: radio, link: 'https://example/#x'),
            const SoundAction(),
            const WebhookAction('https://hooks.example/x'),
          ],
        ),
      ],
    );
    final back = AutomationSettings.decode(s.encode());
    expect(back.encode(), s.encode());
    expect(back.webhooks, isTrue);
    expect(back.rules.single.triggers, hasLength(5));
    expect(back.rules.single.actions, hasLength(5));
    expect(back.nextId, 4);
    expect(AutomationSettings.decode('nonsense').rules, isEmpty);
    expect(
      const AutomationSettings().webhooks,
      isFalse,
      reason: 'off by default',
    );
    expect(WebhookAction.validUrl('ftp://x'), isFalse);
    expect(WebhookAction.validUrl('https://'), isFalse);
  });

  test('a message trigger sends a filled-in reply, within limits', () async {
    engine.settings = AutomationSettings(
      rules: [
        rule(
          [const MessageTrigger(contains: 'HELP')],
          [SendAction(conversation: chat, text: '{node} said: {text} @{time}')],
        ),
      ],
    );
    await engine.onMessage(msg('need help here', now));
    expect(calls.sent.single, (chat.key, 'Ann said: need help here @18:00'));
    // Cooldown: the next one is skipped.
    await engine.onMessage(msg('help again', now));
    expect(calls.sent, hasLength(1));
    // Other bots, old backlog and non-matching text never trigger.
    now = now.add(const Duration(minutes: 10));
    await engine.onMessage(msg('[auto] help', now));
    await engine.onMessage(msg('help', now.subtract(const Duration(hours: 1))));
    await engine.onMessage(msg('hello', now));
    expect(calls.sent, hasLength(1));
    await engine.onMessage(msg('help', now));
    expect(calls.sent, hasLength(2));
    expect(engine.log.first.ok, isTrue);
  });

  test('battery falling below the line alerts once', () async {
    engine.settings = AutomationSettings(
      rules: [
        rule(
          [BatteryTrigger(radio: radio, node: peak, below: 20)],
          [const AlertAction('{node} at {battery}%'), const SoundAction()],
        ),
      ],
    );
    await engine.onNodes([node(battery: 15)]);
    expect(calls.alerts, isEmpty, reason: 'first reading is a baseline');
    await engine.onNodes([node(battery: 40)]);
    await engine.onNodes([node(battery: 18)]);
    expect(calls.alerts.single, ('R1', 'Peak at 18%'));
    expect(calls.sounds, 1);
    now = now.add(const Duration(hours: 1));
    await engine.onNodes([node(battery: 12)]);
    expect(calls.alerts, hasLength(1), reason: 'still below: no new crossing');
  });

  test('AND: a time only fires while the battery is low', () async {
    engine.settings = AutomationSettings(
      rules: [
        rule(
          [
            const TimeTrigger(hour: 18, minute: 0, weekdays: {5}),
            BatteryTrigger(radio: radio, node: peak, below: 30),
          ],
          [const AlertAction('charge {node}')],
          all: true,
        ),
      ],
    );
    await engine.onNodes([node(battery: 80)]);
    await engine.onTick();
    expect(calls.alerts, isEmpty);

    // Next Friday at 18:00 with a low battery.
    now = now.add(const Duration(days: 7));
    // The battery crossing fires, and 18:00 on a Friday holds, so it runs.
    await engine.onNodes([node(battery: 25)]);
    expect(calls.alerts, hasLength(1));
    calls.alerts.clear();
    now = now.add(const Duration(days: 1)); // Saturday: not a chosen day
    await engine.onTick();
    expect(calls.alerts, isEmpty);
  });

  test('OR: either trigger is enough; a time fires once a minute', () async {
    engine.settings = AutomationSettings(
      rules: [
        rule(
          [
            const TimeTrigger(hour: 18, minute: 0),
            const MessageTrigger(contains: 'ping'),
          ],
          [const SoundAction()],
        ),
      ],
    );
    await engine.onTick();
    now = now.add(const Duration(seconds: 20));
    await engine.onTick();
    expect(calls.sounds, 1);
  });

  test('geofence enter fires with the place name', () async {
    engine
      ..settings = AutomationSettings(
        rules: [
          rule(
            [const GeofenceTrigger(place: 9, enter: true)],
            [const AlertAction('{node} reached {place}')],
          ),
        ],
      )
      ..onPlaces(const [
        Place(
          id: 9,
          kind: PlaceKind.geofence,
          name: 'Camp',
          points: [GeoPoint(45.0, -122.0)],
          radiusM: 200,
        ),
      ]);
    await engine.onNodes([node(at: const GeoPoint(45.01, -122.0))]);
    await engine.onNodes([node(at: const GeoPoint(45.0005, -122.0))]);
    expect(calls.alerts.single.$2, 'Peak reached Camp');
  });

  test('a node going quiet, then coming back', () async {
    engine.settings = AutomationSettings(
      rules: [
        rule(
          [
            PresenceTrigger(
              radio: radio,
              node: peak,
              online: false,
              after: const Duration(minutes: 30),
            ),
          ],
          [const AlertAction('{node} quiet')],
        ),
        rule(
          [
            PresenceTrigger(
              radio: radio,
              node: peak,
              online: true,
              after: const Duration(minutes: 30),
            ),
          ],
          [const AlertAction('{node} back')],
          id: 2,
        ),
      ],
    );
    await engine.onNodes([node(heard: now)]);
    await engine.onTick(); // baseline: present
    now = now.add(const Duration(minutes: 45));
    await engine.onTick();
    expect(calls.alerts.map((a) => a.$2), ['Peak quiet']);
    await engine.onNodes([node(heard: now)]);
    expect(calls.alerts.map((a) => a.$2), ['Peak quiet', 'Peak back']);
  });

  test('webhooks only run when allowed, and post JSON', () async {
    final r = rule(
      [const MessageTrigger()],
      [const WebhookAction('https://hooks.example/in')],
    );
    engine.settings = AutomationSettings(rules: [r]);
    await engine.onMessage(msg('hi', now));
    expect(calls.posts, isEmpty);
    expect(engine.log.first.ok, isFalse);
    expect(engine.log.first.note, 'web requests are off');

    now = now.add(const Duration(minutes: 6));
    engine.settings = AutomationSettings(rules: [r], webhooks: true);
    await engine.onMessage(msg('hi', now));
    final (url, body) = calls.posts.single;
    expect(url.host, 'hooks.example');
    expect(jsonDecode(body), containsPair('text', 'hi'));
    expect(jsonDecode(body), containsPair('rule', 'R1'));
  });

  test('all rules together run at most 30 times an hour', () async {
    engine.settings = AutomationSettings(
      rules: [
        for (var i = 1; i <= 40; i++)
          rule([const MessageTrigger()], [const SoundAction()], id: i),
      ],
    );
    await engine.onMessage(msg('x', now));
    expect(calls.sounds, AutomationEngine.maxPerHour);
  });

  test('a failed action is logged and the rest still run', () async {
    calls.connected = false;
    engine.settings = AutomationSettings(
      rules: [
        rule(
          [const MessageTrigger()],
          [SendAction(conversation: chat, text: 'x'), const SoundAction()],
        ),
      ],
    );
    await engine.onMessage(msg('x', now));
    expect(calls.sounds, 1);
    expect(engine.log.last.ok, isFalse);
    expect(engine.log.last.note, 'radio not connected');
  });

  test('saving keeps the settings in the store', () async {
    await engine.save(
      AutomationSettings(
        rules: [
          rule([const MessageTrigger()], [const SoundAction()]),
        ],
      ),
    );
    final again = AutomationSettings.decode(
      await store.preference(AutomationEngine.prefName),
    );
    expect(again.rules.single.name, 'R1');
  });
}
