import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/radio/ble_profiles.dart';

void main() {
  // Copied by hand from each radio's published firmware, on purpose: a typo
  // in the profile must not be able to pass by comparing it with itself.
  test('Meshtastic IDs match the firmware (BluetoothCommon.h)', () {
    const p = BleProfile.meshtastic;
    expect(p.service, '6ba1b218-15a8-461f-9fa8-5dcae273eafd');
    expect(p.write, 'f75c76d2-129e-4dad-a1dd-7866124401e7');
    expect(p.notify, 'ed9da18c-a800-4f66-a670-aa7547e34453');
    expect(p.read, '2c55e69e-4993-11ed-b878-0242ac120002');
  });

  test('MeshCore IDs are the Nordic UART service', () {
    const p = BleProfile.meshcore;
    expect(p.service, '6e400001-b5a3-f393-e0a9-e50e24dcca9e');
    expect(p.write, '6e400002-b5a3-f393-e0a9-e50e24dcca9e');
    expect(p.notify, '6e400003-b5a3-f393-e0a9-e50e24dcca9e');
    expect(p.read, isNull);
  });
}
