import '../store/mesh_store.dart';

/// Runs [MeshStore.clearPreAppMeshCoreHeard] once per install.
abstract final class HeardCleanup {
  /// Preference set once the cleanup has run.
  static const pref = 'fix.meshcoreHeardBeforeApp.v1';

  /// Clears impossible MeshCore last-heard times the first time it is
  /// called; later calls do nothing. Returns how many nodes changed.
  static Future<int> runOnce(MeshStore store) async {
    if (await store.preference(pref) != null) return 0;
    final changed = await store.clearPreAppMeshCoreHeard();
    await store.setPreference(pref, '1');
    return changed;
  }
}
