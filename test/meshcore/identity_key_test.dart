import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/meshcore/meshcore.dart';
import 'package:notoryx_pro/ui/identity_key_screen.dart';

import '../support/scripted_meshcore.dart';

final _key = Uint8List.fromList(List.generate(64, (i) => 255 - i));
final _hex = [for (final b in _key) b.toRadixString(16).padLeft(2, '0')].join();

void main() {
  group('session', _session);
  group('screen', _screen);
}

void _session() {
  late ScriptedMeshCoreLink link;
  late MeshCoreSession session;

  Future<void> open(List<Uint8List> Function(Uint8List) responder) async {
    link = ScriptedMeshCoreLink(responder: responder);
    await link.open();
    session = MeshCoreSession(link, timeout: const Duration(seconds: 1));
  }

  tearDown(() => session.dispose());

  test('export sends command 23 and returns the key', () async {
    await open(
      (_) => [
        Uint8List.fromList([Resp.privateKey, ..._key]),
      ],
    );
    expect(await session.exportPrivateKey(), _key);
    expect(link.commands.single, [Cmd.exportPrivateKey]);
  });

  test('import sends command 24 with the key', () async {
    await open((_) => [RadioFrames.ok()]);
    await session.importPrivateKey(_key);
    expect(link.commands.single, [Cmd.importPrivateKey, ..._key]);
    expect(
      () => MeshCoreCommands.importPrivateKey([1, 2]),
      throwsArgumentError,
    );
  });

  test('compiled out: feature off', () async {
    await open(
      (_) => [
        Uint8List.fromList([Resp.disabled]),
      ],
    );
    await expectLater(
      session.exportPrivateKey(),
      throwsA(isA<MeshCoreFeatureOff>()),
    );
  });

  test('too old for the command: feature off', () async {
    await open((_) => [RadioFrames.err(1)]);
    await expectLater(
      session.importPrivateKey(_key),
      throwsA(isA<MeshCoreFeatureOff>()),
    );
  });

  test('a bad key is refused', () async {
    await open((_) => [RadioFrames.err(6)]);
    await expectLater(
      session.importPrivateKey(_key),
      throwsA(isA<MeshCoreException>()),
    );
  });
}

void _screen() {
  test('pasted keys may have spaces, line breaks and 0x', () {
    expect(parseIdentityKey(_hex), _key);
    expect(parseIdentityKey('0x${_hex.toUpperCase()}'), _key);
    expect(
      parseIdentityKey('${_hex.substring(0, 60)}\n  ${_hex.substring(60)}'),
      _key,
    );
    expect(parseIdentityKey(_hex.substring(1)), isNull);
    expect(parseIdentityKey('g${_hex.substring(1)}'), isNull);
  });

  testWidgets('screen: key shown only after confirming; restore asks first', (
    tester,
  ) async {
    List<int>? imported;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IdentityKeyScreen(
          export: () async => _key,
          import: (k) async => imported = k,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('key-show')));
    await tester.pumpAndSettle();
    expect(find.text(_hex), findsNothing);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text(_hex), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('key-paste')), _hex);
    await tester.pump();
    final replace = find.byKey(const ValueKey('key-replace'));
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Replace identity'));
    await tester.pumpAndSettle();
    expect(imported, _key);
  });
}
