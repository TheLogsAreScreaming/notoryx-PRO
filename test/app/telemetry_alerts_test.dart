import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/telemetry_alerts.dart';
import 'package:notoryx_pro/mesh/lpp.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/store/mesh_store.dart';

import 'alerts_test.dart' show FakeNotifier;

final radio = RadioId.meshcore('aa' * 32);
final sensor = NodeKey.meshcore('bb' * 32);

TelemetryPoint temp(double c, DateTime t) =>
    TelemetryPoint(radioId: radio, node: sensor, time: t, temperature: c);

void main() {
  test('reads battery and weather out of a MeshCore LPP payload', () {
    final p = lppTelemetry(
      Uint8List.fromList([
        1, 116, 0x01, 0x9a, // 4.10 V
        2, 103, 0xff, 0x9c, // -10.0 °C
        2, 104, 90, // 45 %
        2, 115, 0x27, 0x9a, // 1013.8 hPa
        1, 120, 80, // 80 %
      ]),
      radioId: radio,
      node: sensor,
      time: DateTime(2026, 11, 22),
    )!;
    expect(p.voltage, closeTo(4.10, 1e-9));
    expect(p.temperature, closeTo(-10, 1e-9));
    expect(p.relativeHumidity, 45);
    expect(p.barometricPressure, closeTo(1013.8, 1e-9));
    expect(p.batteryLevel, 80);
    expect(
      lppTelemetry(
        Uint8List.fromList([1, 142, 1]),
        radioId: radio,
        node: sensor,
        time: DateTime(2026),
      ),
      isNull,
    );
  });

  test('alerts once on a crossing, with a quiet time', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    var now = DateTime(2026, 11, 22, 12);
    final notifier = FakeNotifier();
    final alerts = TelemetryAlerts(
      store: store,
      notifier: notifier,
      now: () => now,
    );
    addTearDown(alerts.dispose);
    await alerts.setLimit(
      radio,
      sensor,
      TelemetryValue.temperature,
      const TelemetryLimit(above: 30, below: 0),
    );
    expect(
      (await alerts.limitFor(radio, sensor, TelemetryValue.temperature))!.above,
      30,
    );

    await alerts.check(temp(25, now));
    await alerts.check(temp(31, now));
    expect(notifier.shown, hasLength(1));
    await alerts.check(temp(33, now));
    expect(notifier.shown, hasLength(1));
    now = now.add(const Duration(minutes: 5));
    await alerts.check(temp(20, now));
    await alerts.check(temp(-1, now));
    expect(notifier.shown, hasLength(1));
    now = now.add(const Duration(minutes: 40));
    await alerts.check(temp(20, now));
    await alerts.check(temp(-2, now));
    expect(notifier.shown, hasLength(2));

    await alerts.setLimit(radio, sensor, TelemetryValue.temperature, null);
    expect(
      await alerts.limitFor(radio, sensor, TelemetryValue.temperature),
      isNull,
    );
  });

  test('saved readings reach the alert stream', () async {
    final store = MeshStore.memory();
    addTearDown(store.close);
    final seen = store.newTelemetry.first;
    await store.addTelemetry(temp(21, DateTime.now()));
    expect((await seen).temperature, 21);
  });
}
