import 'package:flutter/material.dart';

import '../app/regional_presets.dart';
import '../meshtastic/admin.dart';
import 'common.dart';

/// Lets the person pick MeshCore settings for their country or local mesh.
/// [latitude]/[longitude] (the radio's position, when set) put nearby
/// meshes first.
Future<MeshCorePreset?> showMeshCorePresets(
  BuildContext context, {
  double? latitude,
  double? longitude,
}) => showModalBottomSheet<MeshCorePreset>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.8,
    builder: (context, scroll) {
      final l = context.l10n;
      final known =
          latitude != null &&
          longitude != null &&
          (latitude != 0 || longitude != 0);
      final near = known
          ? MeshCorePresets.near(latitude, longitude)
          : const <MeshCorePreset>[];
      final local = MeshCorePresets.localSorted(
        lat: latitude,
        lon: longitude,
      ).where((p) => !near.contains(p));
      Widget header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
      return ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l.presetsIntro),
          ),
          if (near.isNotEmpty) header(l.presetsNear),
          for (final p in near) _PresetTile(p),
          header(l.presetsSuggested),
          for (final p in MeshCorePresets.suggestedSorted()) _PresetTile(p),
          header(l.presetsLocal),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l.presetsLocalHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final p in local) _PresetTile(p),
          const SizedBox(height: 16),
        ],
      );
    },
  ),
);

class _PresetTile extends StatelessWidget {
  const _PresetTile(this.preset);

  final MeshCorePreset preset;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = preset;
    final values = l.presetValues(
      p.frequencyMHz.toStringAsFixed(3),
      _trim(p.bandwidthKHz),
      p.spreadingFactor,
      p.codingRate,
    );
    return ListTile(
      title: Text(p.retired ? l.presetRetired(p.name) : p.name),
      subtitle: Text(
        [values, if (p.notes.isNotEmpty) p.notes].join('\n'),
        maxLines: 4,
      ),
      isThreeLine: p.notes.isNotEmpty,
      onTap: () => Navigator.pop(context, p),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

/// Lets the person pick a Meshtastic region; the standard setup (Long Fast,
/// automatic slot) goes with it.
Future<int?> showMeshtasticRegions(BuildContext context, {int? current}) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, scroll) {
          final l = context.l10n;
          final regions = MeshtasticRegion.names.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          return ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l.presetsMeshtasticIntro),
              ),
              for (final MapEntry(key: code, value: name) in regions)
                ListTile(
                  title: Text(name),
                  trailing: code == current ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, code),
                ),
            ],
          );
        },
      ),
    );
