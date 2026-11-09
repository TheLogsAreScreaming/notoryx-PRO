import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_controller.dart';
import '../mesh/diagnostics.dart' show haversineKm;
import '../mesh/gpx.dart';
import '../mesh/model.dart';
import '../mesh/places.dart';
import 'common.dart';
import 'restore_sheet.dart' show pickTextFile;

/// Saved waypoints, routes and geofences; GPX in and out; the link planner.
class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key, required this.app, this.pick});

  final AppController app;

  /// Returns a chosen file's text; replaceable in tests.
  final Future<String?> Function()? pick;

  Future<void> _import(BuildContext context) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = await (pick ?? () => pickTextFile(const ['gpx']))();
      if (text == null) return;
      final places = parseGpx(text);
      await app.store.addPlaces(places);
      messenger.showSnackBar(
        SnackBar(content: Text(l.placesImported(places.length))),
      );
    } on NotGpx {
      messenger.showSnackBar(SnackBar(content: Text(l.placesNotGpx)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.exportFailed('$e'))));
    }
  }

  Future<void> _export(BuildContext context, List<Place> places) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/notoryx-pro-places.gpx');
      await file.writeAsString(writeGpx(places), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.exportFailed('$e'))));
    }
  }

  Future<void> _addGeofence(BuildContext context) async {
    final own = [for (final c in app.connections) ?c.radio?.position];
    await showDialog<void>(
      context: context,
      builder: (_) => _GeofenceDialog(app: app, start: own.firstOrNull),
    );
  }

  /// Everywhere the planner can measure between.
  List<(String, GeoPoint)> _endpoints(List<Place> places, List<Node> nodes) => [
    for (final p in places)
      if (p.kind != PlaceKind.route) (p.name, p.points.first),
    for (final n in nodes)
      if (n.position case final at?) (n.name, at),
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return StreamBuilder<List<Place>>(
      stream: app.store.watchPlaces(),
      builder: (context, snap) {
        final places = snap.data ?? const <Place>[];
        return Scaffold(
          appBar: AppBar(title: Text(l.placesTitle)),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: Text(l.placesImport),
                onTap: () => _import(context),
              ),
              if (places.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text(l.placesExport),
                  onTap: () => _export(context, places),
                ),
              ListTile(
                key: const Key('add-geofence'),
                leading: const Icon(Icons.radar),
                title: Text(l.placesAddGeofence),
                onTap: () => _addGeofence(context),
              ),
              StreamBuilder<List<Node>>(
                stream: app.store.watchAllNodes(),
                builder: (context, nodes) {
                  final ends = _endpoints(places, nodes.data ?? const []);
                  return ListTile(
                    key: const Key('plan-link'),
                    leading: const Icon(Icons.settings_input_antenna),
                    title: Text(l.placesPlanner),
                    enabled: ends.length >= 2,
                    subtitle: ends.length < 2
                        ? Text(l.placesPlannerNeed)
                        : null,
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => _LinkPlanner(ends: ends),
                    ),
                  );
                },
              ),
              const Divider(),
              if (places.isEmpty) ListTile(title: Text(l.placesEmpty)),
              for (final p in places)
                ListTile(
                  leading: Icon(switch (p.kind) {
                    PlaceKind.waypoint => Icons.place_outlined,
                    PlaceKind.route => Icons.route,
                    PlaceKind.geofence => Icons.radar,
                  }),
                  title: Text(p.name),
                  subtitle: Text(switch (p.kind) {
                    PlaceKind.waypoint => l.placesWaypoint,
                    PlaceKind.route => l.placesRoute(p.points.length),
                    PlaceKind.geofence => l.placesGeofence(p.radiusM!.round()),
                  }),
                  trailing: IconButton(
                    tooltip: l.placesDelete(p.name),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => app.store.deletePlace(p.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GeofenceDialog extends StatefulWidget {
  const _GeofenceDialog({required this.app, this.start});

  final AppController app;
  final GeoPoint? start;

  @override
  State<_GeofenceDialog> createState() => _GeofenceDialogState();
}

class _GeofenceDialogState extends State<_GeofenceDialog> {
  final _name = TextEditingController();
  late final _at = TextEditingController(
    text: widget.start == null
        ? ''
        : '${widget.start!.latitude.toStringAsFixed(5)},'
              '${widget.start!.longitude.toStringAsFixed(5)}',
  );
  final _radius = TextEditingController(text: '500');

  @override
  void dispose() {
    _name.dispose();
    _at.dispose();
    _radius.dispose();
    super.dispose();
  }

  GeoPoint? get _point {
    final p = _at.text.split(',');
    if (p.length != 2) return null;
    final lat = double.tryParse(p[0].trim());
    final lon = double.tryParse(p[1].trim());
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      return null;
    }
    return GeoPoint(lat, lon);
  }

  double? get _metres {
    final r = double.tryParse(_radius.text.trim());
    return r != null && r >= 10 && r <= 100000 ? r : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final point = _point;
    final metres = _metres;
    final ok = _name.text.trim().isNotEmpty && point != null && metres != null;
    void changed(String _) => setState(() {});
    return AlertDialog(
      title: Text(l.placesAddGeofence),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('fence-name'),
              controller: _name,
              onChanged: changed,
              decoration: InputDecoration(labelText: l.placesName),
            ),
            TextField(
              key: const Key('fence-at'),
              controller: _at,
              onChanged: changed,
              decoration: InputDecoration(
                labelText: l.placesCentre,
                hintText: '45.12345,-122.54321',
                errorText: _at.text.isNotEmpty && point == null
                    ? l.placesBadCentre
                    : null,
              ),
            ),
            TextField(
              key: const Key('fence-radius'),
              controller: _radius,
              onChanged: changed,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.placesRadius,
                errorText: metres == null ? l.placesBadRadius : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(
          key: const Key('fence-save'),
          onPressed: !ok
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await widget.app.store.addPlaces([
                    Place(
                      kind: PlaceKind.geofence,
                      name: _name.text.trim(),
                      points: [point],
                      radiusM: metres,
                    ),
                  ]);
                  navigator.pop();
                },
          child: Text(l.channelsAdd),
        ),
      ],
    );
  }
}

class _LinkPlanner extends StatefulWidget {
  const _LinkPlanner({required this.ends});

  final List<(String, GeoPoint)> ends;

  @override
  State<_LinkPlanner> createState() => _LinkPlannerState();
}

class _LinkPlannerState extends State<_LinkPlanner> {
  int _a = 0;
  int _b = 1;
  final _freq = TextEditingController(text: '915');
  final _tx = TextEditingController(text: '22');
  final _gain = TextEditingController(text: '4');
  final _sens = TextEditingController(text: '-124');

  @override
  void dispose() {
    for (final c in [_freq, _tx, _gain, _sens]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label) => Expanded(
    child: TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _end(String label, int value, void Function(int) set) =>
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var i = 0; i < widget.ends.length; i++)
            DropdownMenuItem(value: i, child: Text(widget.ends[i].$1)),
        ],
        onChanged: (v) => setState(() => set(v!)),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final f = double.tryParse(_freq.text);
    final tx = double.tryParse(_tx.text);
    final gain = double.tryParse(_gain.text);
    final sens = double.tryParse(_sens.text);
    final budget =
        f == null || f <= 0 || tx == null || gain == null || sens == null
        ? null
        : LinkBudget.estimate(
            distanceKm: haversineKm(widget.ends[_a].$2, widget.ends[_b].$2),
            frequencyMHz: f,
            txDbm: tx,
            antennaGainDb: gain,
            sensitivityDbm: sens,
          );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.placesPlanner,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _end(l.placesFrom, _a, (v) => _a = v),
              _end(l.placesTo, _b, (v) => _b = v),
              Row(
                children: [
                  _field(_freq, l.placesFreq),
                  const SizedBox(width: 8),
                  _field(_tx, l.placesTx),
                ],
              ),
              Row(
                children: [
                  _field(_gain, l.placesGain),
                  const SizedBox(width: 8),
                  _field(_sens, l.placesSens),
                ],
              ),
              const SizedBox(height: 12),
              if (budget != null) ...[
                Text(l.placesDistance(budget.distanceKm.toStringAsFixed(2))),
                Text(l.placesLoss(budget.pathLossDb.toStringAsFixed(1))),
                Text(l.placesReceived(budget.receivedDbm.toStringAsFixed(1))),
                Text(
                  l.placesMargin(budget.marginDb.toStringAsFixed(1)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 8),
              Text(l.placesPlannerWarning),
            ],
          ),
        ),
      ),
    );
  }
}
