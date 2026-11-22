import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../radio/radio.dart';
import '../store/mesh_store.dart';
import 'backdrop.dart';
import 'common.dart';
import 'themes.dart';
import 'list_insets.dart';

/// Picks one of the themes, with a live preview of each.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key, required this.store});

  final MeshStore store;

  static String nameOf(BuildContext context, AppThemeId id) {
    final l = context.l10n;
    return switch (id) {
      AppThemeId.blackout => l.themeBlackout,
      AppThemeId.blaze => l.themeBlaze,
      AppThemeId.neonAnarchy => l.themeNeonAnarchy,
      AppThemeId.tactical => l.themeTactical,
      AppThemeId.bareBeauty => l.themeBareBeauty,
      AppThemeId.okabeIto => l.themeOkabeIto,
      AppThemeId.nightOps => l.themeNightOps,
    };
  }

  static String _about(BuildContext context, AppThemeId id) {
    final l = context.l10n;
    return switch (id) {
      AppThemeId.blackout => l.themeBlackoutAbout,
      AppThemeId.blaze => l.themeBlazeAbout,
      AppThemeId.neonAnarchy => l.themeNeonAnarchyAbout,
      AppThemeId.tactical => l.themeTacticalAbout,
      AppThemeId.bareBeauty => l.themeBareBeautyAbout,
      AppThemeId.okabeIto => l.themeOkabeItoAbout,
      AppThemeId.nightOps => l.themeNightOpsAbout,
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
                padding: withBottomInset(context, const EdgeInsets.all(8)),
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
                  BackdropOptions(store: store),
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

/// Background behind the main screens: theme default, colours or a photo.
class BackdropOptions extends StatefulWidget {
  const BackdropOptions({
    super.key,
    required this.store,
    this.pick = pickBackdropPhoto,
  });

  final MeshStore store;

  /// Asks for a photo; replaced in tests.
  final Future<Uint8List?> Function() pick;

  @override
  State<BackdropOptions> createState() => _BackdropOptionsState();
}

class _BackdropOptionsState extends State<BackdropOptions> {
  late final Stream<BackdropState> _saved = watchBackdrop(widget.store);
  double? _dim;
  double? _blur;

  Future<void> _pickPhoto(BackdropChoice choice) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.bgPhotoFailed;
    final png = await widget.pick();
    if (png == null) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    await saveBackdropPhoto(widget.store, choice, png);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return StreamBuilder<BackdropState>(
      stream: _saved,
      builder: (context, snap) {
        final saved =
            snap.data ?? (choice: const BackdropChoice(), photo: null);
        final c = saved.choice.copyWith(dim: _dim, blur: _blur);
        void save(BackdropChoice next) => unawaited(next.save(widget.store));
        String kindName(BackdropKind k) => switch (k) {
          BackdropKind.theme => l.bgTheme,
          BackdropKind.solid => l.bgSolid,
          BackdropKind.linear => l.bgLinear,
          BackdropKind.mesh => l.bgMesh,
          BackdropKind.photo => l.bgPhoto,
        };
        final names = l.bgColourNames.split(',');
        Widget swatches(
          String title,
          int selected,
          void Function(int) on,
        ) => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final (i, colour) in backdropColors.indexed)
                    Semantics(
                      button: true,
                      selected: colour.toARGB32() == selected,
                      label: names[i],
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => on(colour.toARGB32()),
                        child: SizedBox.square(
                          dimension: 48,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colour,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colour.toARGB32() == selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                  width: colour.toARGB32() == selected ? 4 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
        final theme = Theme.of(context);
        final fill = glassFill(
          theme,
          dim: c.kind == BackdropKind.photo ? c.dim : 0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(l.bgTitle, style: text.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l.bgHelp, style: text.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final k in BackdropKind.values)
                    ChoiceChip(
                      key: Key('bg-${k.name}'),
                      label: Text(kindName(k)),
                      selected: c.kind == k,
                      onSelected: (_) =>
                          k == BackdropKind.photo && saved.photo == null
                          ? unawaited(_pickPhoto(c))
                          : save(c.copyWith(kind: k)),
                    ),
                ],
              ),
            ),
            if (c.kind
                case BackdropKind.solid ||
                    BackdropKind.linear ||
                    BackdropKind.mesh)
              swatches(
                c.kind == BackdropKind.solid ? l.bgColour : l.bgFirst,
                c.first,
                (v) => save(c.copyWith(first: v)),
              ),
            if (c.kind case BackdropKind.linear || BackdropKind.mesh)
              swatches(
                l.bgSecond,
                c.second,
                (v) => save(c.copyWith(second: v)),
              ),
            if (c.kind == BackdropKind.photo) ...[
              Padding(
                padding: const EdgeInsets.all(8),
                child: OutlinedButton.icon(
                  key: const Key('bg-pick'),
                  icon: const Icon(Icons.photo_outlined),
                  label: Text(l.bgPickPhoto),
                  onPressed: () => unawaited(_pickPhoto(c)),
                ),
              ),
              _slider(
                label: l.bgDim,
                value: c.dim,
                max: BackdropChoice.maxDim,
                shown: '${(c.dim * 100).round()}%',
                onChanged: (v) => setState(() => _dim = v),
                onEnd: (v) {
                  save(saved.choice.copyWith(dim: v, blur: c.blur));
                  _dim = null;
                },
              ),
              _slider(
                label: l.bgBlur,
                value: c.blur,
                max: BackdropChoice.maxBlur,
                shown: c.blur.round().toString(),
                onChanged: (v) => setState(() => _blur = v),
                onEnd: (v) {
                  save(saved.choice.copyWith(blur: v, dim: c.dim));
                  _blur = null;
                },
              ),
            ],
            if (c.glass)
              Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 160,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BackdropView(choice: c, photo: saved.photo),
                        Center(
                          child: GlassPanel(
                            fill: fill,
                            margin: const EdgeInsets.all(24),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(l.bgSample, style: text.bodyLarge),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double max,
    required String shown,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            divisions: 20,
            label: shown,
            semanticFormatterCallback: (_) => shown,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(width: 40, child: Text(shown, textAlign: TextAlign.end)),
      ],
    ),
  );
}
