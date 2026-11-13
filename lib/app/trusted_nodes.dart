import 'dart:async';
import 'dart:convert';

import '../mesh/identity.dart';
import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// Which nodes you trust, and whether views show only them.
///
/// A node is trusted when you marked it in the app, when one of your radios
/// has it as a favourite, or when you verified its key and the key still
/// matches. Marks are kept as a preference, so they follow the node across
/// radios and need no schema change.
class TrustState {
  const TrustState({
    this.marked = const {},
    this.onlyTrusted = false,
    this.verifications = const {},
  });

  /// Node keys (as [NodeKey.toString]) marked trusted in the app.
  final Set<String> marked;

  /// Lists and the map show trusted nodes only.
  final bool onlyTrusted;
  final Map<NodeKey, Verification> verifications;

  bool isMarked(NodeKey key) => marked.contains(key.toString());

  /// Whether [node] counts as trusted. [favorites] is every key starred on
  /// any of your radios, since each radio keeps its own favourites.
  bool trusts(Node node, {Set<NodeKey> favorites = const {}}) =>
      isMarked(node.key) ||
      node.isFavorite ||
      favorites.contains(node.key) ||
      trustOf(node, verifications[node.key]) == TrustStatus.verified;
}

/// Keys starred as favourites on any radio.
Set<NodeKey> favoriteKeys(Iterable<Node> nodes) => {
  for (final n in nodes)
    if (n.isFavorite) n.key,
};

abstract final class TrustedNodes {
  /// Preference names in the store.
  static const markedPref = 'trust.nodes';
  static const onlyPref = 'view.trustedOnly';

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

  /// Marks or unmarks [key] as trusted.
  static Future<void> setMarked(
    MeshStore store,
    NodeKey key, {
    required bool trusted,
  }) async {
    final now = {...decode(await store.preference(markedPref))};
    if (trusted) {
      now.add(key.toString());
    } else {
      now.remove(key.toString());
    }
    await store.setPreference(markedPref, jsonEncode(now.toList()..sort()));
  }

  static Future<void> setOnlyTrusted(MeshStore store, bool on) =>
      store.setPreference(onlyPref, on ? '1' : '0');

  /// The trust state as it changes; first emits once all three sources
  /// have reported.
  static Stream<TrustState> watch(MeshStore store) {
    String? marked, only;
    Map<NodeKey, Verification> verifications = const {};
    var gotMarked = false, gotOnly = false, gotVerifications = false;
    final subs = <StreamSubscription<Object?>>[];
    late final StreamController<TrustState> out;
    void emit() {
      if (!gotMarked || !gotOnly || !gotVerifications) return;
      out.add(
        TrustState(
          marked: decode(marked),
          onlyTrusted: only == '1',
          verifications: verifications,
        ),
      );
    }

    out = StreamController<TrustState>(
      onListen: () {
        subs.addAll([
          store.watchPreference(markedPref).listen((v) {
            marked = v;
            gotMarked = true;
            emit();
          }),
          store.watchPreference(onlyPref).listen((v) {
            only = v;
            gotOnly = true;
            emit();
          }),
          store.watchVerifications().listen((v) {
            verifications = v;
            gotVerifications = true;
            emit();
          }),
        ]);
      },
      onCancel: () => Future.wait([for (final s in subs) s.cancel()]),
    );
    return out.stream;
  }
}
