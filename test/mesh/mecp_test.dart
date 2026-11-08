import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/mesh/mecp_codes.dart';

void main() {
  test('reads the spec example', () {
    final m = MecpMessage.tryParse(
      'MECP/0/M01 M07 P01 2pax 47.3769,12.1048 @0845 @de',
    )!;
    expect(m.severity, MecpSeverity.mayday);
    expect(m.codes, ['M01', 'M07', 'P01']);
    expect(m.people, 2);
    expect(m.position, (47.3769, 12.1048));
    expect(m.time, '08:45');
    expect(m.note, isEmpty);
    expect(m.isDrill, isFalse);
  });

  test('free text, negative coordinates, drills, unknown codes', () {
    final a = MecpMessage.tryParse('MECP/3/L02 L10 Great view! @en')!;
    expect(a.note, 'Great view!');
    expect(a.position, isNull);
    expect(MecpMessage.tryParse('MECP/0/M01 P05 56.68,-5.02')!.position, (
      56.68,
      -5.02,
    ));
    expect(MecpMessage.tryParse('MECP/0/M01 P05 91.0,5.0')!.position, isNull);
    expect(MecpMessage.tryParse('MECP/3/D01 M01')!.isDrill, isTrue);
    expect(MecpMessage.tryParse('MECP/3/D03')!.isDrill, isFalse);
    final z = MecpMessage.tryParse('MECP/1/Z99')!;
    expect(z.codes, ['Z99']);
    expect(MecpMessage.label('Z99'), isNull);
  });

  test('anything else is not MECP', () {
    for (final t in [
      'hello',
      'MECP/4/M01',
      'MECP/0/',
      'MECP/0/hello there',
      'mecp/0/M01',
      'see MECP/0/M01',
    ]) {
      expect(MecpMessage.tryParse(t), isNull, reason: t);
    }
  });

  test('encodes and reads back', () {
    const m = MecpMessage(
      severity: MecpSeverity.urgent,
      codes: ['W01', 'P03'],
      freetext: '15pax',
    );
    expect(m.encode(), 'MECP/1/W01 P03 15pax');
    expect(m.bytes, 20);
    final back = MecpMessage.tryParse(m.encode())!;
    expect(back.severity, m.severity);
    expect(back.codes, m.codes);
    expect(back.freetext, m.freetext);
    expect(
      const MecpMessage(
        severity: MecpSeverity.routine,
        codes: ['L01'],
      ).encode(),
      'MECP/3/L01',
    );
  });

  test('every code belongs to a known category', () {
    expect(mecpCodes, hasLength(108));
    for (final c in mecpCodes.keys) {
      expect(mecpCategories.keys, contains(c[0]));
      expect(c, matches(RegExp(r'^[A-Z]\d\d$')));
    }
  });
}
