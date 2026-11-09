import 'package:flutter/material.dart';

import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'themes.dart';

/// Picks one of the eight themes, with a live preview of each.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key, required this.store});

  final MeshStore store;

  static String nameOf(BuildContext context, AppThemeId id) {
    final l = context.l10n;
    return switch (id) {
      AppThemeId.blaze => l.themeBlaze,
      AppThemeId.neonAnarchy => l.themeNeonAnarchy,
      AppThemeId.tactical => l.themeTactical,
      AppThemeId.pinkOverload => l.themePinkOverload,
      AppThemeId.bareBeauty => l.themeBareBeauty,
      AppThemeId.okabeIto => l.themeOkabeIto,
      AppThemeId.nightOps => l.themeNightOps,
      AppThemeId.seasonal => l.themeSeasonal,
    };
  }

  static String _about(BuildContext context, AppThemeId id) {
    final l = context.l10n;
    return switch (id) {
      AppThemeId.blaze => l.themeBlazeAbout,
      AppThemeId.neonAnarchy => l.themeNeonAnarchyAbout,
      AppThemeId.tactical => l.themeTacticalAbout,
      AppThemeId.pinkOverload => l.themePinkOverloadAbout,
      AppThemeId.bareBeauty => l.themeBareBeautyAbout,
      AppThemeId.okabeIto => l.themeOkabeItoAbout,
      AppThemeId.nightOps => l.themeNightOpsAbout,
      AppThemeId.seasonal => l.themeSeasonalAbout,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.themeTitle)),
      body: StreamBuilder<String?>(
        stream: store.watchPreference(ThemeChoice.prefName),
        builder: (context, snap) {
          final choice = ThemeChoice.decode(snap.data);
          return LayoutBuilder(
            builder: (context, box) {
              final across = box.maxWidth >= 840 ? 4 : 2;
              final width = (box.maxWidth - 16 - 8 * (across - 1)) / across;
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in AppThemeId.values)
                        SizedBox(
                          width: width,
                          child: _ThemeCard(
                            id: id,
                            choice: choice,
                            selected: choice.id == id,
                            onTap: () => choice.copyWith(id: id).save(store),
                          ),
                        ),
                    ],
                  ),
                  if (choice.id == AppThemeId.seasonal)
                    _SeasonalOptions(store: store, choice: choice),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.id,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AppThemeId id;
  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final brightness = Theme.of(context).brightness;
    final theme = buildTheme(choice.copyWith(id: id), brightness);
    final s = theme.colorScheme;
    final name = ThemeScreen.nameOf(context, id);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: Theme(
        data: theme,
        child: Material(
          key: Key('theme-${id.name}'),
          color: s.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? s.primary : s.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: s.onSurface,
                          ),
                        ),
                      ),
                      if (selected) Icon(Icons.check_circle, color: s.primary),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ThemeScreen._about(context, id),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: s.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: s.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l.themePreviewMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: s.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ProtocolBadge(RadioProtocol.meshcore),
                      ProtocolBadge(RadioProtocol.meshtastic),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonalOptions extends StatelessWidget {
  const _SeasonalOptions({required this.store, required this.choice});

  final MeshStore store;
  final ThemeChoice choice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String name(Season s) => switch (s) {
      Season.spring => l.themeSpring,
      Season.summer => l.themeSummer,
      Season.autumn => l.themeAutumn,
      Season.winter => l.themeWinter,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l.themeSeasonPick,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l.themeSeasonAuto),
                selected: choice.season == null,
                onSelected: (_) =>
                    choice.copyWith(season: () => null).save(store),
              ),
              for (final s in Season.values)
                ChoiceChip(
                  label: Text(name(s)),
                  selected: choice.season == s,
                  onSelected: (_) =>
                      choice.copyWith(season: () => s).save(store),
                ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('theme-holidays'),
          title: Text(l.themeHolidays),
          subtitle: Text(l.themeHolidaysHelp),
          value: choice.holidays,
          onChanged: choice.season == null
              ? (v) => choice.copyWith(holidays: v).save(store)
              : null,
        ),
      ],
    );
  }
}
