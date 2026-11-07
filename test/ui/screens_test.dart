import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/app.dart';
import 'package:notoryx_pro/ui/conversation_screen.dart';
import 'package:notoryx_pro/ui/diagnostics_screen.dart';
import 'package:notoryx_pro/ui/verify_screen.dart';
import 'package:notoryx_pro/mesh/identity.dart';
import 'package:notoryx_pro/mesh/diagnostics.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';

import '../support/scripted_meshtastic.dart';

final mc = RadioId.meshcore('aa' * 32);
final mt = RadioId.meshtastic(0xa1b2c3d4);
final relayKey = NodeKey.meshtastic(0x0badcafe);

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

/// Lets database work and streams catch up.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Removes the widgets (so database streams close) and shuts the store.
///
/// drift tidies up closed streams on a timer, so time is pumped before and
/// while closing; closing straight away would wait forever.
Future<void> tearDownApp(WidgetTester tester, AppController app) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {
    for (final p in RadioProtocol.values) {
      await app.disconnect(p);
    }
  });
  final closing = app.store.close();
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() => closing);
}

Future<void> seed(MeshStore store) async {
  final now = DateTime.now();
  await store.replaceChannels(mc, [
    Channel(radioId: mc, index: 0, name: 'Public', kind: ChannelKind.public),
  ]);
  await store.replaceChannels(mt, [
    Channel(
      radioId: mt,
      index: 0,
      name: 'Primary',
      kind: ChannelKind.public,
      isPrimary: true,
    ),
  ]);
  await store.upsertNode(
    Node(
      key: relayKey,
      radioId: mt,
      name: 'Ridge Relay',
      shortName: 'RR',
      kind: NodeKind.person,
      lastHeard: now.subtract(const Duration(minutes: 5)),
      path: const PathFacts(hops: 2, snr: 6.5),
    ),
  );
  await store.addMessage(
    Message(
      conversation: ChannelConversation(mc, 0),
      text: 'hello trail',
      outgoing: false,
      sentAt: now,
      receivedAt: now,
      delivery: const Received(),
      senderName: 'Ann',
      path: const PathFacts(hops: 3, snr: -2.5, route: RouteKind.flood),
    ),
  );
  await store.addMessage(
    Message(
      conversation: DirectConversation(mt, relayKey),
      text: 'psst',
      outgoing: false,
      sentAt: now,
      receivedAt: now,
      delivery: const Received(),
      from: relayKey,
      nativeId: 1,
      path: const PathFacts(hops: 2, snr: 6.5, rssi: -97),
    ),
  );
  await store.addMessage(
    Message(
      conversation: DirectConversation(mt, relayKey),
      text: 'anyone there?',
      outgoing: true,
      sentAt: now,
      receivedAt: now,
      delivery: const Failed('No route to the node'),
    ),
  );
}

void main() {
  testWidgets('empty app shows guidance on every tab', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    expect(
      find.textContaining('Connect a radio on the Radios tab'),
      findsOneWidget,
    );

    await tester.tap(find.text('Nodes'));
    await settle(tester);
    expect(find.textContaining('No nodes yet'), findsOneWidget);

    await tester.tap(find.text('Radios'));
    await settle(tester);
    expect(find.text('No radio connected. Find one below.'), findsOneWidget);
    expect(find.text('Find Bluetooth radios'), findsOneWidget);
    expect(find.text('Add Wi-Fi radio'), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('inbox lists channels and direct messages from both meshes', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seed(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);

    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Ann: hello trail'), findsOneWidget);
    expect(find.text('Direct messages'), findsOneWidget);
    expect(find.text('Ridge Relay'), findsOneWidget);
    expect(find.text('You: anyone there?'), findsOneWidget);
    expect(find.text('MeshCore'), findsWidgets);
    expect(find.text('Meshtastic'), findsWidgets);
    await tearDownApp(tester, app);
  });

  testWidgets('conversation shows path facts and failures', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seed(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);

    await tester.tap(find.text('Ridge Relay'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('psst'), findsOneWidget);
    expect(
      find.textContaining('2 hops · SNR 6.5 dB · -97 dBm'),
      findsOneWidget,
    );
    expect(find.text('Not delivered: No route to the node'), findsOneWidget);
    expect(find.text('Connect this radio to send messages.'), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('tapping a message opens how it travelled', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seed(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.tap(find.text('hello trail'));
    await tester.pumpAndSettle();
    expect(find.text('How this message travelled'), findsOneWidget);
    expect(find.text('Flooded through the mesh'), findsOneWidget);
    expect(find.text('3 hops'), findsOneWidget);
    expect(find.text('SNR -2.5 dB'), findsOneWidget);
    expect(find.text('Ann'), findsWidgets);
    await tearDownApp(tester, app);
  });

  testWidgets('no Send again while the radio is offline', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seed(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Ridge Relay'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Not delivered: No route to the node'), findsOneWidget);
    expect(find.text('Send again'), findsNothing);
    await tearDownApp(tester, app);
  });

  testWidgets('nodes tab shows kind, mesh and how it was heard', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    await tester.runAsync(() => seed(app.store));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Nodes'));
    await settle(tester);
    expect(find.text('Ridge Relay'), findsOneWidget);
    expect(find.text('(RR)'), findsOneWidget);
    expect(
      find.textContaining('Person · Heard 5 min ago · 2 hops'),
      findsOneWidget,
    );
    await tearDownApp(tester, app);
  });

  testWidgets('map without positions explains why it is empty', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await tester.tap(find.text('Map'));
    await settle(tester);
    expect(find.textContaining('No positions yet'), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('map shows nodes from both meshes and a MeshCore route', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    final relay = Node(
      key: NodeKey.meshcore('a1${'0' * 62}'),
      radioId: mc,
      name: 'Peak Repeater',
      kind: NodeKind.relay,
      position: const GeoPoint(46.0, -121.0),
    );
    final friend = Node(
      key: NodeKey.meshcore('ee${'0' * 62}'),
      radioId: mc,
      name: 'Sam',
      kind: NodeKind.person,
      position: const GeoPoint(46.1, -121.1),
      path: const PathFacts(hops: 1, snr: -3, route: RouteKind.direct),
      route: const [0xa1],
    );
    final ranger = Node(
      key: NodeKey.meshtastic(0x0badcafe),
      radioId: mt,
      name: 'Ranger',
      kind: NodeKind.person,
      position: const GeoPoint(45.9, -121.2),
    );
    await tester.runAsync(() => app.store.upsertNodes([relay, friend, ranger]));
    await tester.pumpWidget(NotoryxProApp(app: app));
    await tester.tap(find.text('Map'));
    await settle(tester);
    expect(find.bySemanticsLabel('Sam, MeshCore'), findsOneWidget);
    expect(find.bySemanticsLabel('Ranger, Meshtastic'), findsOneWidget);
    expect(find.bySemanticsLabel('Peak Repeater, MeshCore'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Sam, MeshCore'));
    await tester.pumpAndSettle();
    expect(find.text('Signal 2 of 4'), findsOneWidget);
    expect(find.text('Signal is from the last repeater'), findsOneWidget);
    expect(find.text('• Peak Repeater'), findsOneWidget);
    await tester.tap(find.text('Show route on map'));
    await tester.pumpAndSettle();
    expect(find.byType(PolylineLayer), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('packet log lists packets newest first and pauses', (
    tester,
  ) async {
    final log = PacketLog()
      ..add(
        PacketLogEntry(
          time: DateTime(2026, 11, 7, 9, 0, 1),
          protocol: RadioProtocol.meshcore,
          kind: 'Advert',
          path: const PathFacts(hops: 2, snr: 6.5, route: RouteKind.flood),
          bytes: 120,
          detail: 'a1 b2',
        ),
      )
      ..add(
        PacketLogEntry(
          time: DateTime(2026, 11, 7, 9, 0, 2),
          protocol: RadioProtocol.meshtastic,
          kind: 'Encrypted',
          from: '!0badcafe',
          encrypted: true,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PacketLogView(log: log)),
      ),
    );
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['09:00:02  Encrypted', '09:00:01  Advert']);
    expect(find.textContaining("can't read (other channel)"), findsOneWidget);
    expect(find.textContaining('a1 b2'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    log.add(
      PacketLogEntry(
        time: DateTime(2026, 11, 7, 9, 0, 3),
        protocol: RadioProtocol.meshcore,
        kind: 'Ack',
      ),
    );
    await tester.pump();
    expect(find.text('1 packets arrived while paused'), findsOneWidget);
    expect(find.textContaining('Ack'), findsNothing);
  });

  testWidgets('a failed MeshCore message explains what may be wrong', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    final sam = NodeKey.meshcore('ee' * 32);
    await tester.runAsync(() async {
      await app.store.upsertNode(
        Node(
          key: sam,
          radioId: mc,
          name: 'Sam',
          lastHeard: DateTime.now().subtract(const Duration(days: 3)),
          path: const PathFacts(route: RouteKind.flood),
        ),
      );
      final now = DateTime.now();
      await app.store.addMessage(
        Message(
          conversation: DirectConversation(mc, sam),
          text: 'you there?',
          outgoing: true,
          sentAt: now,
          receivedAt: now,
          delivery: const Failed('No acknowledgement after 5 tries'),
        ),
      );
    });
    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.tap(find.text('you there?'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Why it might not have arrived'), findsOneWidget);
    expect(
      find.textContaining("haven't been heard for over a day"),
      findsOneWidget,
    );
    expect(find.textContaining('no known route'), findsOneWidget);
    expect(find.textContaining('have you as a contact'), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('verify by scanning their code, then badges appear', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    final key = Uint8List.fromList(List.generate(32, (i) => 0xee - i));
    final sam = Node(
      key: NodeKey.meshcore(hexOf(key)),
      radioId: mc,
      name: 'Sam',
      publicKey: key,
    );
    final impostor = Node(
      key: NodeKey.meshcore('11' * 32),
      radioId: mc,
      name: 'Sam',
      publicKey: Uint8List.fromList(List.filled(32, 0x11)),
    );
    await tester.runAsync(() async {
      await app.store.upsertNodes([sam, impostor]);
      final now = DateTime.now();
      await app.store.addMessage(
        Message(
          conversation: DirectConversation(mc, sam.key),
          text: 'it is me',
          outgoing: false,
          sentAt: now,
          receivedAt: now,
          delivery: const Received(),
          from: sam.key,
          authenticated: true,
        ),
      );
      await app.store.replaceChannels(mc, [
        Channel(
          radioId: mc,
          index: 0,
          name: 'Public',
          kind: ChannelKind.public,
        ),
      ]);
      await app.store.addMessage(
        Message(
          conversation: ChannelConversation(mc, 0),
          text: 'send me your password',
          outgoing: false,
          sentAt: now,
          receivedAt: now,
          delivery: const Received(),
          senderName: 'Sam',
        ),
      );
    });

    var scanned = ContactCard(
      protocol: RadioProtocol.meshcore,
      name: 'Sam',
      publicKey: Uint8List.fromList(List.filled(32, 0x11)),
    ).toLink();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VerifyScreen(app: app, node: sam, scan: (_) async => scanned),
      ),
    );
    await settle(tester);
    expect(find.text(keyFingerprint(key)), findsOneWidget);
    expect(find.textContaining('Connect your radio'), findsOneWidget);

    await tester.tap(find.text('Scan their code'));
    await settle(tester);
    expect(find.textContaining('belongs to someone else'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(VerifyScreen)),
    ).removeCurrentSnackBar();
    await tester.pump();

    scanned = ContactCard(
      protocol: RadioProtocol.meshcore,
      name: 'Sam',
      publicKey: key,
    ).toLink();
    await tester.tap(find.text('Scan their code'));
    await settle(tester);
    expect(find.text('Sam is verified.'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Remove verification'), findsOneWidget);

    await tester.pumpWidget(NotoryxProApp(app: app));
    await settle(tester);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Verified sender'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.textContaining('Another node uses this name'), findsOneWidget);
    expect(find.textContaining("can't prove who sent them"), findsOneWidget);
    await tearDownApp(tester, app);
  });

  testWidgets('verify by comparing fingerprints asks for confirmation', (
    tester,
  ) async {
    final app = AppController(store: MeshStore.memory());
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final node = Node(
      key: NodeKey.meshtastic(7),
      radioId: mt,
      name: 'Ranger',
      publicKey: key,
    );
    await tester.runAsync(() => app.store.upsertNode(node));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VerifyScreen(app: app, node: node),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('The fingerprints match'));
    await tester.pumpAndSettle();
    expect(find.textContaining('compared every group'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await settle(tester);
    final v = await tester.runAsync(() => app.store.verifications());
    expect(v![node.key]!.method, VerificationMethod.compared);
    await tearDownApp(tester, app);
  });

  testWidgets('Wi-Fi dialog checks the address and port', (tester) async {
    final app = AppController(store: MeshStore.memory());
    await tester.pumpWidget(NotoryxProApp(app: app));
    await tester.tap(find.text('Radios'));
    await settle(tester);
    await tester.tap(find.text('Add Wi-Fi radio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text("Enter the radio's address"), findsOneWidget);
    await tester.enterText(find.byKey(const Key('wifi-host')), 'radio.local');
    await tester.enterText(find.byKey(const Key('wifi-port')), '99999');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Use a port between 1 and 65535'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tearDownApp(tester, app);
  });

  testWidgets('connected radio: composer counts bytes and sends', (
    tester,
  ) async {
    final link = ScriptedMeshtasticLink();
    final app = AppController(
      store: MeshStore.memory(),
      links: FakeLinks(link),
    );
    await tester.runAsync(
      () => app.connect(
        const TcpTarget(host: 'node', protocol: RadioProtocol.meshtastic),
      ),
    );
    final conversation = ChannelConversation(mt, 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationScreen(
          app: app,
          conversation: conversation,
          title: 'Trail',
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Say hello'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'héllo');
    await tester.pump();
    expect(find.text('6/233'), findsOneWidget, reason: 'é is two bytes');
    await tester.tap(find.byTooltip('Send'));
    await settle(tester);
    expect(find.text('héllo'), findsOneWidget);
    expect(link.sent.last.packet!.channel, 1);
    await tearDownApp(tester, app);
  });
}
