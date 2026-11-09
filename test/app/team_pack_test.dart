import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_controller.dart';
import 'package:notoryx_pro/app/radio_target.dart';
import 'package:notoryx_pro/app/team_pack.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/places.dart';
import 'package:notoryx_pro/meshtastic/meshtastic.dart' show AdminField;
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/team_pack_screen.dart';

import '../support/scripted_meshtastic.dart';

class FakeLinks extends LinkFactory {
  FakeLinks(this.link);
  final RadioLink link;
  @override
  RadioLink create(RadioTarget target, {ConnectionLog? log}) => link;
}

final pack = TeamPack(
  name: 'Ridge',
  protocol: RadioProtocol.meshtastic,
  channels: [ChannelInvite.private(RadioProtocol.meshtastic, 'Camp')],
  radio: const {'region': 1, 'usePreset': 1, 'preset': 0, 'hops': 3, 'slot': 0},
  places: const [
    Place(
      kind: PlaceKind.geofence,
      name: 'Base',
      points: [GeoPoint(1, 2)],
      radiusM: 500,
    ),
  ],
);

void main() {
  void same(TeamPack back) {
    expect(back.name, 'Ridge');
    expect(back.channels.single.secret, pack.channels.single.secret);
    expect(back.radio, pack.radio);
    expect(back.places.single.radiusM, 500);
  }

  test('round trips as a file and as a code', () {
    same(TeamPack.parse(pack.toFile()));
    same(TeamPack.parse(pack.toCode()));
  });

  test('other things are refused; newer versions say so', () {
    expect(() => TeamPack.parse('hello'), throwsA(isA<NotATeamPack>()));
    expect(
      () => TeamPack.parse('notoryxteam:!!!'),
      throwsA(isA<NotATeamPack>()),
    );
    expect(
      () => TeamPack.parse(
        '{"format":"notoryx-pro-team","formatVersion":2,"protocol":"meshcore"}',
      ),
      throwsA(isA<NotATeamPack>().having((e) => e.tooNew, 'tooNew', true)),
    );
  });

  test('bad parts are dropped, the rest is kept', () {
    final j = jsonDecode(pack.toFile()) as Map<String, Object?>;
    final bad = {
      ...j,
      'radio': {
        'region': 999,
        'usePreset': 1,
        'preset': 0,
        'hops': 3,
        'slot': 0,
      },
      'channels': [
        {'n': 'waytoolongforthismesh', 's': ''},
        {
          'n': 'x',
          's': base64Encode([1, 2, 3]),
        },
      ],
    };
    final p = TeamPack.parse(jsonEncode(bad));
    expect(p.radio, isNull);
    expect(p.channels, isEmpty);
    expect(p.places, hasLength(1));
  });

  test('radio settings are left alone unless asked for', () async {
    final store = MeshStore.memory();
    final link = ScriptedMeshtasticLink();
    final node = FakeAdminNode(link.myNode);
    link.onPacket = (p) => node(p, myNode: link.myNode);
    final app = AppController(store: store, links: FakeLinks(link));
    final c = await app.connect(
      const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
    );
    final r = await applyTeamPack(
      c,
      store,
      pack,
      channels: true,
      radio: false,
      places: true,
    );
    await pumpEventQueue();
    expect((r.channels, r.places), (1, 1));
    expect(node.received.where((x) => x.$1 == AdminField.setConfig), isEmpty);
    expect(
      node.received.where((x) => x.$1 == AdminField.setChannel),
      hasLength(1),
    );
    await app.shutdown();
    await store.close();
  });

  testWidgets('screen: a pack opens with radio settings off', (t) async {
    t.view.physicalSize = const Size(420, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MeshStore.memory();
    final link = ScriptedMeshtasticLink();
    final node = FakeAdminNode(link.myNode);
    link.onPacket = (p) => node(p, myNode: link.myNode);
    final app = AppController(store: store, links: FakeLinks(link));
    final c = (await t.runAsync(
      () => app.connect(
        const TcpTarget(host: 'mt', protocol: RadioProtocol.meshtastic),
      ),
    ))!;
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TeamPackScreen(
          connection: c,
          store: store,
          pick: () async => pack.toFile(),
        ),
      ),
    );
    await t.tap(find.text('Open a file'));
    await settle();
    expect(
      t.widget<SwitchListTile>(find.byKey(const Key('team-apply-radio'))).value,
      isFalse,
    );
    await t.tap(find.byKey(const Key('team-apply')));
    await settle();
    expect(find.textContaining('Channels added: 1'), findsOneWidget);
    expect(find.textContaining('Places added: 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(app.shutdown);
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  });
}
