/// When a node counts as stale: not heard for a while.
library;

import 'model.dart';

/// How far ahead of the phone a last-heard time may be and still be
/// believed; radio and phone clocks drift and time zones get mixed up.
const futureSlack = Duration(days: 1);

/// [lastHeard] if it can be trusted at [now], else null (unknown).
///
/// A clock that was never set reports 0 (1970) or a time before 2020; a
/// wrong one can report the future. Ages measured from either are
/// nonsense ("20771 days"), so both count as not knowing when the node
/// was heard.
DateTime? knownHeard(DateTime? lastHeard, DateTime now) {
  final t = plausibleTime(lastHeard);
  if (t == null || t.isAfter(now.add(futureSlack))) return null;
  return t;
}

/// Whether a node last heard at [lastHeard] is stale at [now].
///
/// [after] is how long a node may go unheard; null turns marking off. A
/// node whose last-heard time is missing or can't be trusted
/// ([knownHeard]) is never stale, since there is nothing to measure from.
bool isStale(DateTime? lastHeard, DateTime now, Duration? after) {
  final t = knownHeard(lastHeard, now);
  if (t == null || after == null) return false;
  return now.difference(t) >= after;
}

/// The choices for "Mark nodes stale after", and how they are saved.
abstract final class StaleAfter {
  /// Preference name in the store; the value is minutes, `0` for off.
  static const pref = 'view.staleAfterMinutes';

  /// Used until the person picks something.
  static const fallback = Duration(hours: 24);

  /// The choices offered, in order; null is Off.
  static const choices = <Duration?>[
    null,
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 7),
  ];

  /// Reads a saved value; anything unreadable means [fallback].
  static Duration? decode(String? raw) {
    final minutes = raw == null ? null : int.tryParse(raw);
    if (minutes == null || minutes < 0) return fallback;
    return minutes == 0 ? null : Duration(minutes: minutes);
  }

  /// The saved form of [after].
  static String encode(Duration? after) => '${after?.inMinutes ?? 0}';
}
