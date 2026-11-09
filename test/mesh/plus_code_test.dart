import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/distress_beacon.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/mesh/model.dart';
import 'package:notoryx_pro/mesh/plus_code.dart';

void main() {
  test('matches the published test vectors', () {
    expect(PlusCode.encode(20.3700625, 2.7821875), '7FG49QCJ+2V');
    expect(PlusCode.encode(47.0000625, 8.0000625), '8FVC2222+22');
    final (lat, lon) = PlusCode.decode('7FG49QCJ+2V')!;
    expect(lat, closeTo(20.3700625, 1e-7));
    expect(lon, closeTo(2.7821875, 1e-7));
  });

  test('round trips, including the awkward corners', () {
    for (final (la, lo) in [(0.0, 0.0), (-33.8, 151.2), (89.9999, 179.9999)]) {
      final (a, b) = PlusCode.decode(PlusCode.encode(la, lo))!;
      expect(a, closeTo(la, .0002));
      expect(b, closeTo(lo, .0002));
    }
    expect(() => PlusCode.encode(90, 180), returnsNormally);
  });

  test('rejects anything else', () {
    expect(PlusCode.decode('hello'), isNull);
    expect(PlusCode.decode('7FG49QCJ2V'), isNull);
    expect(PlusCode.decode('AAAAAAAA+AA'), isNull);
  });

  test('a beacon can carry one, MECP reads it, and it is shorter', () {
    DistressBeacon b(bool short) => DistressBeacon(
      conversation: ChannelConversation(RadioId.meshtastic(1), 0),
      send: (_) async {},
      position: () async => null,
      incoming: const Stream.empty(),
      maxBytes: 160,
      shortPosition: short,
    );
    const at = (-33.86785, 151.20732);
    final short = b(true).textFor(at);
    expect(short.length, lessThan(b(false).textFor(at).length));
    final p = MecpMessage.tryParse(short)!;
    expect(p.position!.$1, closeTo(at.$1, .001));
    expect(p.note, isEmpty);
  });
}
