import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/channel_conflicts.dart';

SlotCopy slot(int index, String name, int fill) => SlotCopy(
  index: index,
  name: name,
  secret: Uint8List.fromList(List.filled(16, fill)),
);

void main() {
  test('same or new slots are fine; changed and emptied slots conflict', () {
    final out = findChannelConflicts(
      saved: [slot(0, 'Public', 1), slot(1, 'Team', 2), slot(2, 'Ops', 3)],
      radio: [slot(0, 'Public', 1), slot(1, 'Team', 9), slot(3, '#new', 4)],
      slots: 8,
    );
    expect(out.map((c) => c.index), [1, 2]);
    expect(out[0].secretDiffers, isTrue);
    expect(out[0].nameDiffers, isFalse);
    expect(out[1].radio, isNull);
  });

  test('pending copies win until the radio matches them', () {
    final pending = [slot(1, 'Team', 2)];
    expect(
      findChannelConflicts(
        saved: [slot(1, 'Team', 9)],
        radio: [slot(1, 'Team', 9)],
        slots: 8,
        pending: pending,
      ).single.app.secret.first,
      2,
    );
    expect(
      findChannelConflicts(
        saved: [slot(1, 'Team', 9)],
        radio: [slot(1, 'Team', 2)],
        slots: 8,
        pending: pending,
      ),
      isEmpty,
    );
  });

  test('slots past the radio count are ignored; copies round-trip', () {
    expect(
      findChannelConflicts(saved: [slot(9, 'Far', 1)], radio: [], slots: 8),
      isEmpty,
    );
    final back = decodeSlots(encodeSlots([slot(4, 'Team', 7)])).single;
    expect(back.sameAs(slot(4, 'Team', 7)), isTrue);
    expect(decodeSlots('nope'), isEmpty);
    expect(back.fingerprint, matches(RegExp(r'^[0-9a-f]{4} [0-9a-f]{4}$')));
  });
}
