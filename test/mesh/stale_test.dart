import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/stale.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18, 12);
  const day = Duration(hours: 24);

  test('stale once unheard for the whole period', () {
    expect(isStale(now.subtract(const Duration(hours: 23)), now, day), isFalse);
    expect(isStale(now.subtract(day), now, day), isTrue);
    expect(isStale(now.subtract(const Duration(days: 9)), now, day), isTrue);
  });

  test('never stale without a last-heard time or with marking off', () {
    expect(isStale(null, now, day), isFalse);
    expect(isStale(now.subtract(const Duration(days: 30)), now, null), isFalse);
  });

  test('a time in the future is not stale', () {
    expect(isStale(now.add(const Duration(hours: 2)), now, day), isFalse);
  });

  test('the setting is saved as minutes, 24 h until picked', () {
    expect(StaleAfter.decode(null), StaleAfter.fallback);
    expect(StaleAfter.fallback, day);
    expect(StaleAfter.decode('junk'), StaleAfter.fallback);
    expect(StaleAfter.decode('-5'), StaleAfter.fallback);
    expect(StaleAfter.decode('0'), isNull);
    expect(StaleAfter.decode('60'), const Duration(hours: 1));
    for (final c in StaleAfter.choices) {
      expect(StaleAfter.decode(StaleAfter.encode(c)), c);
    }
    expect(StaleAfter.choices, [
      null,
      const Duration(hours: 1),
      const Duration(hours: 6),
      day,
      const Duration(days: 3),
      const Duration(days: 7),
    ]);
  });
}
