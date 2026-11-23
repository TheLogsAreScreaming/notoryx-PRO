import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/coverage_mapper.dart';
import '../app/radio_connection.dart';
import '../mesh/coverage.dart';
import '../mesh/mesh.dart';
import 'common.dart';
import 'map_tiles.dart';

/// Coverage mapping: a start/stop switch, the hexagons this phone recorded
/// and opt-in sharing with the NOTORYX coverage map. MeshCore radios only.
class CoverageScreen extends StatelessWidget {
  const CoverageScreen({
    super.key,
    required this.coverage,
    this.app,
    this.tiles,
  });

  final CoverageMapper coverage;

  /// For telling the user when no MeshCore radio is connected.
  final AppController? app;
  final MapTiles? tiles;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.covTitle)),
      body: ListenableBuilder(
        listenable: Listenable.merge([coverage, ?app]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _mappingSwitch(context),
            SizedBox(
              height: 280,
              child: _HexMap(coverage: coverage, tiles: tiles),
            ),
            const Divider(height: 32),
            ..._sharing(context),
          ],
        ),
      ),
    );
  }

  bool get _hasMeshCore =>
      app?.connections.any((c) => c is MeshCoreConnection) ?? true;

  Widget _mappingSwitch(BuildContext context) {
    final l = context.l10n;
    final cells = coverage.log.bestSnrByCell().length;
    final String status;
    if (!coverage.mapping) {
      status = l.covAbout;
    } else if (coverage.problem == CoverageProblem.locationOff) {
      status = l.covLocationOff;
    } else if (coverage.fix == null) {
      status = l.covWaitingGps;
    } else {
      status = l.covRecording(cells);
    }
    return Column(
      children: [
        SwitchListTile(
          key: const Key('coverage-mapping'),
          secondary: const Icon(Icons.hexagon_outlined),
          title: Text(l.covMapSwitch),
          subtitle: Text(status),
          value: coverage.mapping,
          onChanged: (on) => unawaited(coverage.setMapping(on)),
        ),
        if (!_hasMeshCore)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l.covNoMeshCore),
          ),
      ],
    );
  }

  List<Widget> _sharing(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(l.covShareTitle, style: theme.textTheme.titleMedium),
    );
    final openMap = ListTile(
      key: const Key('coverage-open-map'),
      leading: const Icon(Icons.public),
      title: Text(l.covOpenMap),
      onTap: () => launchUrl(Uri.parse(coverageSiteUrl)),
    );
    if (!coverage.sharing) {
      return [
        heading,
        ListTile(
          key: const Key('coverage-share'),
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(l.covShareTitle),
          subtitle: Text(l.covShareOff),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(_askToShare(context)),
        ),
        openMap,
      ];
    }
    return [
      heading,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(_uploadStatus(context)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(l.covPrivacy, style: theme.textTheme.labelLarge),
      ),
      RadioGroup<CoveragePrivacy>(
        groupValue: coverage.privacy,
        onChanged: (p) {
          if (p != null) unawaited(coverage.setPrivacy(p));
        },
        child: Column(
          children: [
            for (final p in CoveragePrivacy.values)
              RadioListTile<CoveragePrivacy>(
                key: Key('coverage-privacy-${p.name}'),
                value: p,
                title: Text(_privacyName(context, p)),
                subtitle: Text(_privacyHelp(context, p)),
              ),
          ],
        ),
      ),
      SwitchListTile(
        key: const Key('coverage-wifi-only'),
        title: Text(l.covWifiOnly),
        value: coverage.wifiOnly,
        onChanged: (v) => unawaited(coverage.setWifiOnly(v)),
      ),
      SwitchListTile(
        key: const Key('coverage-hide-ends'),
        title: Text(l.covHideEnds),
        subtitle: Text(l.covHideEndsSub),
        value: coverage.hideEnds,
        onChanged: (v) => unawaited(coverage.setHideEnds(v)),
      ),
      if (coverage.privacy != CoveragePrivacy.anonymous)
        ListTile(
          key: const Key('coverage-mapper-name'),
          leading: const Icon(Icons.badge_outlined),
          title: Text(l.covMapperName),
          subtitle: Text(
            coverage.mapperName.isEmpty
                ? l.covMapperNameSub
                : '${coverage.mapperName}\n${l.covMapperNameSub}',
          ),
          onTap: () => unawaited(_editName(context)),
        ),
      ListTile(
        key: const Key('coverage-erase'),
        leading: const Icon(Icons.delete_sweep_outlined),
        title: Text(l.covErase),
        subtitle: Text(l.covEraseSub),
        onTap: () => unawaited(_erase(context)),
      ),
      ListTile(
        key: const Key('coverage-stop-sharing'),
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(l.covStopSharing),
        subtitle: Text(l.covStopSharingSub),
        onTap: () => unawaited(coverage.stopSharing()),
      ),
      openMap,
    ];
  }

  String _uploadStatus(BuildContext context) {
    final l = context.l10n;
    final waiting = l.covWaiting(coverage.waiting);
    final last = switch (coverage.lastUpload) {
      null => null,
      CoverageUploaded(:final cells, :final at) => l.covLastSent(
        cells,
        ago(context, at),
      ),
      CoverageRefused(:final status) => l.covLastRefused(status),
      CoverageUnreachable() => l.covLastUnreachable,
      CoverageWaitingForWifi() => l.covLastWifi,
    };
    return last == null ? waiting : '$waiting\n$last';
  }

  static String _privacyName(BuildContext context, CoveragePrivacy p) {
    final l = context.l10n;
    return switch (p) {
      CoveragePrivacy.live => l.covPrivacyLive,
      CoveragePrivacy.delayed => l.covPrivacyDelayed,
      CoveragePrivacy.anonymous => l.covPrivacyAnonymous,
    };
  }

  static String _privacyHelp(BuildContext context, CoveragePrivacy p) {
    final l = context.l10n;
    return switch (p) {
      CoveragePrivacy.live => l.covPrivacyLiveSub,
      CoveragePrivacy.delayed => l.covPrivacyDelayedSub,
      CoveragePrivacy.anonymous => l.covPrivacyAnonymousSub,
    };
  }

  Future<void> _askToShare(BuildContext context) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.covConsentTitle),
        content: SingleChildScrollView(child: Text(l.covConsentBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const Key('coverage-agree'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.covAgree),
          ),
        ],
      ),
    );
    if (ok == true) await coverage.startSharing();
  }

  Future<void> _editName(BuildContext context) async {
    final l = context.l10n;
    final name = await showTextPrompt(
      context,
      title: l.covMapperName,
      confirm: MaterialLocalizations.of(context).saveButtonLabel,
      initial: coverage.mapperName,
      hint: l.covMapperNameSub,
      fieldKey: const Key('coverage-mapper-field'),
    );
    if (name != null) await coverage.setMapperName(name);
  }

  Future<void> _erase(BuildContext context) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.covErase),
        content: Text(l.covEraseConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const Key('coverage-erase-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.covErase),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await coverage.erase();
    messenger.showSnackBar(
      SnackBar(content: Text(n == null ? l.covEraseFailed : l.covErased(n))),
    );
  }
}

/// The hexagons this phone recorded, shaded by the best SNR in each.
class _HexMap extends StatelessWidget {
  const _HexMap({required this.coverage, this.tiles});

  final CoverageMapper coverage;
  final MapTiles? tiles;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final best = coverage.log.bestSnrByCell();
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final polygons = <Polygon>[];
    for (final MapEntry(key: cell, value: snr) in best.entries) {
      final List<(double, double)> outline;
      try {
        outline = coverage.sources.cellOutline(cell);
      } on Object {
        continue;
      }
      if (outline.length < 3) continue;
      // Stronger signal, more solid fill: 0-4 bars as in the rest of the app.
      final bars = signalBars(PathFacts(snr: snr)) ?? 0;
      polygons.add(
        Polygon(
          points: [for (final (lat, lon) in outline) LatLng(lat, lon)],
          color: scheme.primary.withValues(alpha: 0.15 + bars * 0.15),
          borderColor: scheme.primary,
          borderStrokeWidth: 1,
        ),
      );
    }
    final fix = coverage.fix;
    final points = [
      for (final p in polygons) ...p.points,
      if (fix != null) LatLng(fix.latitude, fix.longitude),
    ];
    if (points.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.covNoHexagons, textAlign: TextAlign.center),
        ),
      );
    }
    return Semantics(
      label: l.covHexagons(polygons.length),
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: points.length > 1
              ? CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.all(24),
                  maxZoom: 15,
                )
              : null,
          initialCenter: points.first,
          initialZoom: 14,
        ),
        children: [
          if (tiles case final tiles?)
            TileLayer(
              urlTemplate: MapTiles.urlTemplate,
              userAgentPackageName: MapTiles.userAgentPackageName,
              tileProvider: tiles.provider,
              reset: tiles.reload,
              tileBuilder: dark ? darkModeTileBuilder : null,
            ),
          PolygonLayer(polygons: polygons),
          if (fix != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(fix.latitude, fix.longitude),
                  width: 14,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          if (tiles != null)
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
        ],
      ),
    );
  }
}
