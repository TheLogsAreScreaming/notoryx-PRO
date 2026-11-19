import 'dart:convert';

import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// Nodes you chose to ignore.
///
/// An ignored node is hidden from the node lists and the map and never
/// notifies, but its messages are still saved. The list is kept on the
/// phone for both meshes, as node keys ([NodeKey.toString]), so it follows
/// the node across radios; a Meshtastic radio's own ignored flag is set
/// alongside it where the firmware supports that.
abstract final class IgnoredNodes {
  /// Preference names in the store: the ignored keys, and the keys you
  /// stopped ignoring that a radio may still flag (so a radio reporting
  /// its old flag doesn't hide the node again).
  static const pref = 'ignore.nodes';
  static const clearedPref = 'ignore.cleared';

  static Set<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final list = jsonDecode(raw);
      return list is List
          ? {
              for (final k in list)
                if (k is String) k,
            }
          : const {};
    } on FormatException {
      return const {};
    }
  }

  static String encode(Set<String> keys) => jsonEncode(keys.toList()..sort());

  /// The ignored keys now.
  static Future<Set<String>> read(MeshStore store) async =>
      decode(await store.preference(pref));

  /// The ignored keys as they change.
  static Stream<Set<String>> watch(MeshStore store) =>
      store.watchPreference(pref).map(decode);

  /// Whether [key] is in [ignored].
  static bool has(Set<String> ignored, NodeKey key) =>
      ignored.contains(key.toString());

  /// Keys you stopped ignoring that a radio may still flag.
  static Future<Set<String>> readCleared(MeshStore store) async =>
      decode(await store.preference(clearedPref));

  /// Ignores or stops ignoring [key] on the phone.
  static Future<void> set(
    MeshStore store,
    NodeKey key, {
    required bool ignored,
  }) async {
    final k = key.toString();
    final now = {...await read(store)};
    final cleared = {...await readCleared(store)};
    final changed = ignored ? now.add(k) : now.remove(k);
    final clearedChanged = ignored ? cleared.remove(k) : cleared.add(k);
    if (changed) await store.setPreference(pref, encode(now));
    if (clearedChanged) {
      await store.setPreference(clearedPref, encode(cleared));
    }
  }

  /// Forgets that [key] was un-ignored, once no radio flags it any more.
  static Future<void> forgetCleared(MeshStore store, NodeKey key) async {
    final cleared = {...await readCleared(store)};
    if (cleared.remove(key.toString())) {
      await store.setPreference(clearedPref, encode(cleared));
    }
  }

  /// Adds [keys] (the nodes a radio reports as ignored), except those
  /// you stopped ignoring in the app.
  static Future<void> addAll(MeshStore store, Iterable<NodeKey> keys) async {
    final cleared = await readCleared(store);
    final now = {...await read(store)};
    final before = now.length;
    now.addAll([
      for (final k in keys)
        if (!cleared.contains(k.toString())) k.toString(),
    ]);
    if (now.length != before) await store.setPreference(pref, encode(now));
  }
}
