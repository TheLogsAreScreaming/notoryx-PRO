import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/model.dart';

void main() {
  group('radio clocks that were never set', () {
    test('a 1970 timestamp counts as unknown', () {
      // A repeater that has been up ~105 days with no clock set.
      expect(radioSeconds(105 * 86400), isNull);
      expect(plausibleTime(DateTime.utc(1970, 4, 16)), isNull);
    });

    test('zero and negative times are unknown', () {
      expect(radioSeconds(0), isNull);
      expect(radioSeconds(-5), isNull);
      expect(plausibleTime(null), isNull);
    });

    test('a real time is kept', () {
      // 2025-11-01, a clock that was set.
      final t = radioSeconds(1761955200);
      expect(t, DateTime.utc(2025, 11, 1));
      expect(plausibleTime(DateTime.utc(2020)), DateTime.utc(2020));
    });
  });
}
