import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/app_lock.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/store/mesh_store.dart';
import 'package:notoryx_pro/ui/lock_gate.dart';

class FakeAuth implements DeviceAuth {
  UnlockResult next = UnlockResult.failed;
  bool has = true;
  int asked = 0;
  @override
  Future<bool> available() async => has;
  @override
  Future<UnlockResult> unlock(String reason) async {
    asked++;
    return next;
  }
}

void main() {
  test('settings round trip and default to off', () {
    expect(LockSettings.decode(null).on, isFalse);
    final s = LockSettings.decode(
      const LockSettings(on: true, graceSeconds: 300).encode(),
    );
    expect((s.on, s.graceSeconds), (true, 300));
  });

  late MeshStore store;
  late FakeAuth auth;
  late DateTime now;
  final cover = find.byKey(const Key('lock-cover'));

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester t, {bool locked = false}) async {
    store = MeshStore.memory();
    auth = FakeAuth();
    now = DateTime(2026);
    await t.runAsync(() => const LockSettings(on: true).save(store));
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => LockGate(
          store: store,
          auth: auth,
          startLocked: locked,
          now: () => now,
          child: child!,
        ),
        home: const Text('secret'),
      ),
    );
    await settle(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    final closing = store.close();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => closing);
  }

  void go(WidgetTester t, AppLifecycleState s) =>
      t.binding.handleAppLifecycleStateChanged(s);

  void away(WidgetTester t) {
    go(t, AppLifecycleState.inactive);
    go(t, AppLifecycleState.hidden);
  }

  void back(WidgetTester t) {
    go(t, AppLifecycleState.inactive);
    go(t, AppLifecycleState.resumed);
  }

  testWidgets('opens locked; a failed check stays locked', (t) async {
    await open(t, locked: true);
    expect(cover, findsOneWidget);
    expect(auth.asked, 1);
    auth.next = UnlockResult.unlocked;
    await t.tap(find.byKey(const Key('lock-unlock')));
    await settle(t);
    expect(cover, findsNothing);
    await finish(t);
  });

  testWidgets('a phone with no screen lock left cannot shut you out', (
    t,
  ) async {
    await open(t, locked: true);
    expect(cover, findsOneWidget);
    auth.next = UnlockResult.unavailable;
    await t.tap(find.byKey(const Key('lock-unlock')));
    await settle(t);
    expect(cover, findsNothing);
    await finish(t);
  });

  testWidgets('relocks only after the grace period', (t) async {
    await open(t);
    away(t);
    now = now.add(const Duration(seconds: 30));
    back(t);
    await settle(t);
    expect(cover, findsNothing);

    away(t);
    now = now.add(const Duration(seconds: 61));
    back(t);
    await settle(t);
    expect(cover, findsOneWidget);
    await finish(t);
  });

  testWidgets('screen: turning it on needs a passing check', (t) async {
    store = MeshStore.memory();
    auth = FakeAuth();
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LockSettingsScreen(store: store, auth: auth),
      ),
    );
    await settle(t);
    SwitchListTile sw() =>
        t.widget<SwitchListTile>(find.byKey(const Key('lock-on')));
    await t.tap(find.byKey(const Key('lock-on')));
    await settle(t);
    expect(sw().value, isFalse);
    auth.next = UnlockResult.unlocked;
    await t.tap(find.byKey(const Key('lock-on')));
    await settle(t);
    expect(sw().value, isTrue);
    await finish(t);
  });
}
