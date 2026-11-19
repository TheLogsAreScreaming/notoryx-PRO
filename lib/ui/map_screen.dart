import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/app_controller.dart';
import '../app/radio_connection.dart';
import '../app/ignored_nodes.dart';
import '../app/trusted_nodes.dart';
import '../mesh/mesh.dart';
import '../radio/radio.dart';
import 'admin_screens.dart';
import '../mesh/node_merge.dart';
import '../mesh/places.dart';
import '../mesh/range_rings.dart';
import '../mesh/stale.dart';
import 'common.dart';
import 'compass_screen.dart';
import 'node_avatar.dart';
import 'node_visibility.dart';
import 'places_screen.dart';
import 'range_rings_layer.dart';
import 'route_screen.dart';
import 'themes.dart';
import 'conversation_screen.dart';
import 'diagnostics_screen.dart';
import 'line_of_sight_sheet.dart';
import 'verify_screen.dart';
import 'map_tiles.dart';
import 'meshtastic_admin_screen.dart';
import 'telemetry_screen.dart';
import 'replay_screen.dart';
import 'traffic_layer.dart';

/// Every node with a position, from both meshes, on one map.
///
/// Tap a node for its details, signal and (MeshCore) the route our radio
/// would use to reach it, drawn through the repeaters along the way.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.app, this.tiles});

  final AppController app;

  /// Map tiles; null draws the nodes on a plain background (tests).
  final MapTiles? tiles;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _map = MapController();
  late final Stream<List<Node>> _nodes = widget.app.store.watchAllNodes();

  /// Traffic mode: heard packets drawn hop by hop.
  bool _traffic = false;
  bool _hopLabels = true;
  Set<TrafficKind> _kinds = TrafficKind.values.toSet();
  TrafficRoute? _latest;
  late final TrafficPlayer _player = TrafficPlayer(vsync: this);
  Timer? _clock;

  /// How many packets of each radio's log have been looked at.
  final Map<TrafficLog, int> _seen = {};

  /// The nodes last drawn, for matching heard packets' hops.
  List<Node> _all = const [];

  @override
  void initState() {
    super.initState();
    widget.app.hopNaming.addListener(_namesChanged);
    widget.app.addListener(_wireTraffic);
    _wireTraffic();
  }

  @override
  void dispose() {
    widget.app.hopNaming.removeListener(_namesChanged);
    widget.app.removeListener(_wireTraffic);
    for (final log in _seen.keys) {
      log.removeListener(_onTraffic);
    }
    _clock?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Follows the traffic logs of the radios connected now.
  void _wireTraffic() {
    final logs = {for (final c in widget.app.connections) c.traffic};
    for (final gone in _seen.keys.where((l) => !logs.contains(l)).toList()) {
      gone.removeListener(_onTraffic);
      _seen.remove(gone);
    }
    for (final log in logs) {
      if (_seen.containsKey(log)) continue;
      _seen[log] = log.count;
      log.addListener(_onTraffic);
    }
  }

  void _onTraffic() {
    if (!mounted) return;
    final now = DateTime.now();
    TrafficRoute? newest;
    for (final c in widget.app.connections) {
      final log = c.traffic;
      final fresh = log.since(_seen[log] ?? log.count);
      _seen[log] = log.count;
      if (!_traffic) continue;
      for (final p in fresh) {
        if (!_kinds.contains(p.kind)) continue;
        final radio = c.radio;
        final route = buildTrafficRoute(
          p,
          _all,
          selfLabel: radio == null || radio.name.isEmpty
              ? context.l10n.mapYourRadio
              : radio.name,
          self: radio?.self,
          selfAt: radio?.position,
          naming: widget.app.hopNaming.value,
          now: now,
        );
        _player.play(route);
        newest = route;
      }
    }
    if (widget.app.hopNaming.value.unsaved) {
      widget.app.hopNaming.value.unsaved = false;
      widget.app.hopNaming.picksChanged();
    }
    if (newest != null) setState(() => _latest = newest);
  }

  void _setTraffic(bool on) {
    setState(() {
      _traffic = on;
      if (!on) {
        _player.clear();
        _latest = null;
      }
    });
    _clock?.cancel();
    // The card's "seconds ago" ticks while traffic is shown.
    _clock = on
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted && _latest != null) setState(() {});
          })
        : null;
  }

  void _namesChanged() {
    if (mounted) setState(() {});
  }

  late final Stream<List<Place>> _places = widget.app.store.watchPlaces();
  late final Stream<TrustState> _trust = TrustedNodes.watch(widget.app.store);
  late final Stream<Set<String>> _ignored = IgnoredNodes.watch(
    widget.app.store,
  );
  late final Stream<Duration?> _staleAfter = watchStaleAfter(widget.app);
  late final Stream<String?> _ringsPref = widget.app.store.watchPreference(
    rangeRingsPref,
  );
  Node? _route;

  /// Preference name for the range-rings switch (`1` on).
  static const rangeRingsPref = 'map.rangeRings';

  Future<void> _setRings(bool on) async {
    await widget.app.store.setPreference(rangeRingsPref, on ? '1' : '0');
    if (on && _ownPositions().isEmpty && mounted) {
      _say(context.l10n.mapRingsNoPosition);
    }
  }

  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  List<GeoPoint> _ownPositions() => [
    for (final c in widget.app.connections) ?c.radio?.position,
  ];

  void _fit(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.single, 12);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
        maxZoom: 15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: _ignored,
    builder: (context, iSnap) => StreamBuilder<Duration?>(
      stream: _staleAfter,
      builder: (context, sSnap) => StreamBuilder<String?>(
        stream: _ringsPref,
        builder: (context, rSnap) => _build(
          context,
          ignored: iSnap.data ?? const {},
          staleAfter: sSnap.connectionState == ConnectionState.waiting
              ? StaleAfter.fallback
              : sSnap.data,
          rings: rSnap.data == '1',
        ),
      ),
    ),
  );

  Widget _build(
    BuildContext context, {
    required Set<String> ignored,
    required Duration? staleAfter,
    required bool rings,
  }) {
    final l = context.l10n;
    return StreamBuilder<TrustState>(
      stream: _trust,
      builder: (context, tSnap) => StreamBuilder<List<Node>>(
        stream: _nodes,
        builder: (context, snap) {
          final all = snap.data ?? const <Node>[];
          final trust = tSnap.data ?? const TrustState();
          final favorites = favoriteKeys(all);
          final now = DateTime.now();
          // One pin per node, even when several of your radios hear it.
          final placed = [
            for (final m in mergeAcrossRadios(all))
              if (m.node.position != null &&
                  !IgnoredNodes.has(ignored, m.node.key) &&
                  (!trust.onlyTrusted ||
                      trust.trusts(m.node, favorites: favorites)))
                m.node,
          ];
          final own = _ownPositions();
          final points = [
            ...placed.map((n) => _ll(n.position!)),
            ...own.map(_ll),
          ];
          final route = _route == null ? null : _routeLine(_route!, all);
          _all = all;
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Stack(
            children: [
              Semantics(
                label: l.mapDescription(placed.length),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: points.isEmpty
                        ? const LatLng(39.5, -98.35)
                        : points.first,
                    initialZoom: points.isEmpty ? 3 : 10,
                    onMapReady: () => _fit(points),
                  ),
                  children: [
                    if (widget.tiles case final tiles?)
                      TileLayer(
                        urlTemplate: MapTiles.urlTemplate,
                        userAgentPackageName: MapTiles.userAgentPackageName,
                        tileProvider: tiles.provider,
                        reset: tiles.reload,
                        tileBuilder: dark ? darkModeTileBuilder : null,
                      ),
                    _placesLayer(),
                    if (rings && own.isNotEmpty)
                      RangeRingsLayer(
                        center: _ll(own.first),
                        imperial: usesMiles(
                          WidgetsBinding
                              .instance
                              .platformDispatcher
                              .locale
                              .countryCode,
                        ),
                      ),
                    if (route != null && route.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route,
                            strokeWidth: 4,
                            color: Theme.of(context).colorScheme.primary,
                            pattern: const StrokePattern.dotted(),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final p in own)
                          Marker(
                            point: _ll(p),
                            width: 40,
                            height: 40,
                            child: Tooltip(
                              message: l.mapYourRadio,
                              child: Icon(
                                Icons.my_location,
                                semanticLabel: l.mapYourRadio,
                                color: Theme.of(context).colorScheme.primary,
                                size: 32,
                              ),
                            ),
                          ),
                        for (final n in placed)
                          Marker(
                            point: _ll(n.position!),
                            width: 44,
                            height: 44,
                            child: _NodeMarker(
                              app: widget.app,
                              node: n,
                              stale: isStale(
                                plausibleTime(n.lastHeard),
                                now,
                                staleAfter,
                              ),
                              onTap: () => _openNode(n, all),
                            ),
                          ),
                      ],
                    ),
                    if (_traffic)
                      TrafficMapLayer(player: _player, showLabels: _hopLabels),
                    if (widget.tiles != null)
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                  ],
                ),
              ),
              if (placed.isEmpty && own.isEmpty)
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.mapNoPositions,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              if (widget.tiles?.status.offline ?? false)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(l.mapOffline, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                bottom: _traffic ? 200 : 8,
                child: Align(
                  alignment: Alignment.topRight,
                  child: MapToolbar(
                    items: _tools(placed, all, points, rings: rings),
                  ),
                ),
              ),
              if (_traffic)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: TrafficCard(route: _latest, now: DateTime.now()),
                ),
            ],
          );
        },
      ),
    );
  }

  List<MapToolItem> _tools(
    List<Node> placed,
    List<Node> all,
    List<LatLng> points, {
    required bool rings,
  }) {
    final l = context.l10n;
    final own = _ownPositions();
    final meshCore = [
      for (final c in widget.app.connections)
        if (c is MeshCoreConnection &&
            c.status.phase == SupervisorPhase.connected)
          c,
    ];
    return [
      MapToolItem(
        key: const Key('map-locate'),
        icon: Icons.near_me_outlined,
        label: l.mapLocate,
        onPressed: own.isEmpty
            ? () => _say(l.mapNoOwnPosition)
            : () => _map.move(
                _ll(own.first),
                _map.camera.zoom < 12 ? 12 : _map.camera.zoom,
              ),
      ),
      MapToolItem(
        key: const Key('map-advert'),
        icon: Icons.campaign_outlined,
        label: l.mapAdvert,
        onPressed: meshCore.isEmpty
            ? () => _say(l.mapAdvertNeedsMeshCore)
            : () => _sendAdvert(meshCore),
      ),
      MapToolItem(
        key: const Key('map-filter'),
        icon: Icons.filter_list,
        label: l.mapFilter,
        selected: _kinds.length < TrafficKind.values.length,
        onPressed: _pickKinds,
      ),
      MapToolItem(
        key: const Key('map-traffic'),
        icon: Icons.route,
        label: l.trafficTitle,
        selected: _traffic,
        onPressed: () => _setTraffic(!_traffic),
      ),
      MapToolItem(
        key: const Key('map-rings'),
        icon: Icons.track_changes,
        label: l.mapRangeRings,
        showLabel: false,
        selected: rings,
        onPressed: () => unawaited(_setRings(!rings)),
      ),
      MapToolItem(
        key: const Key('map-search'),
        icon: Icons.search,
        label: l.mapSearch,
        onPressed: placed.isEmpty ? null : () => _search(placed, all),
      ),
      MapToolItem(
        key: const Key('map-fit'),
        icon: Icons.open_in_full,
        label: l.mapFitAll,
        showLabel: false,
        onPressed: () => _fit(points),
      ),
      MapToolItem(
        key: const Key('map-options'),
        icon: Icons.more_horiz,
        label: l.mapOptions,
        onPressed: _options,
      ),
    ];
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _sendAdvert(List<MeshCoreConnection> radios) async {
    final l = context.l10n;
    final flood = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: Text(l.settingsAdvertNeighbours),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: Text(l.settingsAdvertEveryone),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (flood == null) return;
    try {
      for (final c in radios) {
        await c.sendAdvert(flood: flood);
      }
      if (mounted) _say(l.settingsAdvertSent);
    } on Object catch (e) {
      if (mounted) _say(RadioConnection.describeError(e));
    }
  }

  Future<void> _pickKinds() async {
    final l = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l.trafficFilterTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final k in TrafficKind.values)
                  CheckboxListTile(
                    key: Key('traffic-kind-${k.name}'),
                    value: _kinds.contains(k),
                    secondary: Icon(Icons.circle, color: trafficColor(k)),
                    title: Text(trafficKindName(context, k)),
                    onChanged: (on) {
                      final next = {..._kinds};
                      on == true ? next.add(k) : next.remove(k);
                      setState(() => _kinds = next);
                      setSheet(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _search(List<Node> placed, List<Node> all) async {
    final picked = await showModalBottomSheet<Node>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NodeSearchSheet(nodes: placed),
    );
    if (picked == null || !mounted) return;
    _map.move(
      _ll(picked.position!),
      _map.camera.zoom < 13 ? 13 : _map.camera.zoom,
    );
    await _openNode(picked, all);
  }

  Future<void> _options() async {
    final l = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('map-hop-labels'),
              secondary: const Icon(Icons.label_outline),
              title: Text(l.trafficHopLabels),
              value: _hopLabels,
              onChanged: (v) =>
                  Navigator.pop(context, v ? 'labels-on' : 'labels-off'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l.drTitle),
              onTap: () => Navigator.pop(context, 'replay'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: Text(l.placesTitle),
              onTap: () => Navigator.pop(context, 'places'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'labels-on' || 'labels-off':
        setState(() => _hopLabels = choice == 'labels-on');
      case 'replay':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReplayScreen(app: widget.app, tiles: widget.tiles),
          ),
        );
      case 'places':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlacesScreen(app: widget.app),
          ),
        );
    }
  }

  /// Saved routes, geofences and waypoints.
  Widget _placesLayer() => StreamBuilder<List<Place>>(
    stream: _places,
    builder: (context, snap) {
      final color = Theme.of(context).colorScheme.tertiary;
      final places = snap.data ?? const <Place>[];
      List<Place> of(PlaceKind k) => [
        for (final p in places)
          if (p.kind == k) p,
      ];
      if (places.isEmpty) return const SizedBox.shrink();
      return MobileLayerTransformer(
        child: Stack(
          children: [
            CircleLayer(
              circles: [
                for (final f in of(PlaceKind.geofence))
                  CircleMarker(
                    point: _ll(f.points.first),
                    radius: f.radiusM!,
                    useRadiusInMeter: true,
                    color: color.withValues(alpha: .15),
                    borderColor: color,
                    borderStrokeWidth: 2,
                  ),
              ],
            ),
            PolylineLayer(
              polylines: [
                for (final r in of(PlaceKind.route))
                  Polyline(
                    points: r.points.map(_ll).toList(),
                    strokeWidth: 3,
                    color: color,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final w in of(PlaceKind.waypoint))
                  Marker(
                    point: _ll(w.points.first),
                    width: 36,
                    height: 36,
                    child: Tooltip(
                      message: w.name,
                      child: Icon(
                        Icons.place,
                        color: color,
                        semanticLabel: w.name,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );

  /// Where the radio that knows [n] is, if it has a position.
  GeoPoint? _radioAt(Node n) => widget.app.connections
      .where((c) => c.radio?.id == n.radioId)
      .map((c) => c.radio?.position)
      .nonNulls
      .firstOrNull;

  /// Our radio → known repeaters → the node; hops without a known position
  /// are skipped. Null when there is nothing to draw.
  List<LatLng>? _routeLine(Node target, List<Node> all) {
    final start = widget.app.connections
        .where((c) => c.radio?.id == target.radioId)
        .map((c) => c.radio?.position)
        .nonNulls
        .firstOrNull;
    final hops = widget.app.hopNaming.resolve(target, all, from: start);
    final points = [
      if (start != null) _ll(start),
      for (final h in hops)
        if (h.node?.position case final p?) _ll(p),
      if (target.position case final p?) _ll(p),
    ];
    return points.length > 1 ? points : null;
  }

  Future<void> _openNode(Node n, List<Node> all) async {
    final showRoute = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NodeSheet(
        app: widget.app,
        node: n,
        hops: widget.app.hopNaming.resolve(n, all, from: _radioAt(n)),
        routeShown: _route?.key == n.key,
        tiles: widget.tiles,
        others: [for (final m in mergeAcrossRadios(all)) m.node],
      ),
    );
    if (showRoute == null || !mounted) return;
    setState(() => _route = showRoute ? n : null);
  }
}

/// How long a node counts as recently heard (green ring on its pin).
const recentlyHeard = Duration(hours: 1);

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({
    required this.app,
    required this.node,
    required this.onTap,
    this.stale = false,
  });

  final AppController app;
  final Node node;
  final VoidCallback onTap;

  /// Not heard for a while: drawn faded.
  final bool stale;

  /// How opaque a stale node's pin is.
  static const staleOpacity = .45;

  @override
  Widget build(BuildContext context) {
    final color = meshColor(node.protocol, Theme.of(context));
    final repeater = node.kind == NodeKind.relay;
    final heard = plausibleTime(node.lastHeard);
    final recent =
        heard != null && DateTime.now().difference(heard) < recentlyHeard;
    final pin = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: repeater ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: repeater ? BorderRadius.circular(10) : null,
        border: Border.all(color: color, width: 3),
      ),
      child: Center(
        child: NodeAvatar(
          app: app,
          nodeKey: node.key.toString(),
          icon: nodeKindIcon(node.kind),
          size: recent ? 26 : 32,
          iconColor: color,
        ),
      ),
    );
    final age = heard == null ? null : DateTime.now().difference(heard);
    return Semantics(
      button: true,
      label: [
        node.displayName,
        protocolName(context, node.protocol),
        if (stale && age != null) context.l10n.staleAge(shortAge(context, age)),
      ].join(', '),
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          key: stale ? const Key('pin-stale') : null,
          opacity: stale ? staleOpacity : 1,
          child: recent
              ? Container(
                  key: const Key('pin-recent'),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: repeater ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: repeater ? BorderRadius.circular(13) : null,
                    border: Border.all(color: recentRing, width: 2.5),
                  ),
                  child: pin,
                )
              : pin,
        ),
      ),
    );
  }
}

/// Details for one node; pops `true`/`false` to show or hide its route.
class NodeSheet extends StatelessWidget {
  const NodeSheet({
    super.key,
    required this.app,
    required this.node,
    required this.hops,
    required this.routeShown,
    this.tiles,
    this.others = const [],
  });

  final AppController app;
  final Node node;
  final List<RouteHop> hops;
  final bool routeShown;

  /// Map background for trace cards.
  final MapTiles? tiles;

  /// Other nodes on the map, offered as ends for line of sight.
  final List<Node> others;

  /// Places line of sight can run between: your radio (if it has a
  /// position), this node, then the other nodes with positions.
  List<(String, GeoPoint)> _losEnds(BuildContext context) => [
    if (_connection()?.radio?.position case final p?)
      (context.l10n.losYourRadio, p),
    if (node.position case final p?) (node.displayName, p),
    for (final o in others)
      if (o.position case final p? when o.key != node.key) (o.displayName, p),
  ];

  /// The connected radio that knows this node, if any.
  RadioConnection? _connection() {
    final c = app.connectionForRadio(node.radioId);
    return c != null &&
            c.radio?.id == node.radioId &&
            c.status.phase == SupervisorPhase.connected
        ? c
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final n = node;
    final bars = signalBars(n.path);
    final details = [
      nodeKindName(context, n.kind),
      if (plausibleTime(n.lastHeard) case final t?)
        l.lastHeard(ago(context, t)),
      if (pathSummary(context, n.path) case final p when p.isNotEmpty) p,
    ].join(' · ');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                NodeAvatar(
                  app: app,
                  nodeKey: n.key.toString(),
                  icon: nodeKindIcon(n.kind),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    n.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ProtocolBadge(n.protocol),
              ],
            ),
            const SizedBox(height: 8),
            Text(details),
            const SizedBox(height: 8),
            Row(
              children: [
                SignalBars(bars, size: 20),
                const SizedBox(width: 8),
                Text(bars == null ? l.signalUnknown : l.signalBars(bars)),
              ],
            ),
            if ((n.path.hops ?? 0) > 0 && bars != null)
              Text(l.mapLastHop, style: Theme.of(context).textTheme.bodySmall),
            if (n.protocol == RadioProtocol.meshcore) ...[
              const SizedBox(height: 12),
              Text(l.mapRoute, style: Theme.of(context).textTheme.titleSmall),
              if (hops.isEmpty)
                Text(l.mapRouteFlood)
              else
                for (final h in hops)
                  Text(
                    '• ${h.node?.displayName ?? switch (h.onlineName) {
                          final name? => l.mapRouteOnlineHop(name),
                          null => l.mapRouteUnknownHop(h.prefix),
                        }}',
                  ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (n.position != null)
                  OutlinedButton.icon(
                    key: const Key('node-compass'),
                    icon: const Icon(Icons.explore_outlined),
                    label: Text(l.compassButton),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CompassScreen(app: app, node: n),
                        ),
                      );
                    },
                  ),
                OutlinedButton.icon(
                  key: const Key('node-look'),
                  icon: const Icon(Icons.palette_outlined),
                  label: Text(l.lookButton),
                  onPressed: () => showNodeLookSheet(
                    context,
                    app: app,
                    nodeKey: n.key.toString(),
                    name: n.displayName,
                  ),
                ),
                if (_connection() case final MeshCoreConnection c
                    when n.kind == NodeKind.relay || n.kind == NodeKind.room)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(l.manage),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ServerScreen(connection: c, node: n),
                        ),
                      );
                    },
                  ),
                if (_connection() case final MeshtasticConnection c
                    when n.protocol == RadioProtocol.meshtastic)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(l.manage),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MeshtasticSettingsScreen(connection: c, node: n),
                        ),
                      );
                    },
                  ),
                if (n.protocol == RadioProtocol.meshtastic)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.battery_charging_full),
                    label: Text(l.telemetryButton),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TelemetryScreen(
                            store: app.store,
                            radioId: n.radioId,
                            node: n.key,
                            name: n.displayName,
                          ),
                        ),
                      );
                    },
                  ),
                StreamBuilder<TrustState>(
                  stream: TrustedNodes.watch(app.store),
                  builder: (context, t) {
                    final marked = t.data?.isMarked(n.key) ?? false;
                    return OutlinedButton.icon(
                      key: const Key('sheet-trust'),
                      icon: Icon(marked ? Icons.star : Icons.star_border),
                      label: Text(marked ? l.trustedUnmark : l.trustedMark),
                      onPressed: () => TrustedNodes.setMarked(
                        app.store,
                        n.key,
                        trusted: !marked,
                      ),
                    );
                  },
                ),
                StreamBuilder<Set<String>>(
                  stream: IgnoredNodes.watch(app.store),
                  builder: (context, i) {
                    final ignored = IgnoredNodes.has(i.data ?? const {}, n.key);
                    return OutlinedButton.icon(
                      key: const Key('sheet-ignore'),
                      icon: Icon(
                        ignored
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      label: Text(ignored ? l.unignoreNode : l.ignoreNode),
                      onPressed: () => unawaited(
                        setNodeIgnored(
                          context,
                          app,
                          n.key,
                          n.displayName,
                          ignored: !ignored,
                        ),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(l.verify),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => VerifyScreen(app: app, node: n),
                      ),
                    );
                  },
                ),
                if (n.canMessage && n.kind != NodeKind.relay)
                  FilledButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(l.mapMessage),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ConversationScreen(
                            app: app,
                            conversation: DirectConversation(n.radioId, n.key),
                            title: n.displayName,
                          ),
                        ),
                      );
                    },
                  ),
                if (hops.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.route),
                    label: Text(routeShown ? l.mapHideRoute : l.mapShowRoute),
                    onPressed: () => Navigator.pop(context, !routeShown),
                  ),
                if (_connection() case final MeshCoreConnection c
                    when n.protocol == RadioProtocol.meshcore &&
                        n.publicKey.length == 32)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.alt_route),
                    label: Text(l.rpButton),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RouteScreen(connection: c, node: n),
                        ),
                      );
                    },
                  ),
                if (_connection() case final c? when c.canTrace(n))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.timeline),
                    label: Text(l.traceRoute),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) =>
                          TraceSheet(connection: c, node: n, tiles: tiles),
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: Text(l.traceHistory),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => SavedTracesSheet(
                      store: app.store,
                      node: n,
                      tiles: tiles,
                    ),
                  ),
                ),
                if (_losEnds(context) case final ends
                    when ends.length >= 2 && n.position != null)
                  OutlinedButton.icon(
                    key: const Key('node-line-of-sight'),
                    icon: const Icon(Icons.landscape_outlined),
                    label: Text(l.lineOfSight),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => LineOfSightSheet(
                        ends: ends,
                        frequencyMHz: _connection()?.frequencyMHz ?? 915,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Finds a node on the map by name or ID.
class _NodeSearchSheet extends StatefulWidget {
  const _NodeSearchSheet({required this.nodes});

  final List<Node> nodes;

  @override
  State<_NodeSearchSheet> createState() => _NodeSearchSheetState();
}

class _NodeSearchSheetState extends State<_NodeSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final hits = [
      for (final n in widget.nodes)
        if (q.isEmpty ||
            n.displayName.toLowerCase().contains(q) ||
            n.shortName.toLowerCase().contains(q) ||
            n.key.native.startsWith(q))
          n,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('map-search-field'),
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.l10n.mapSearchHint,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final n in hits.take(100))
                    ListTile(
                      leading: Icon(nodeKindIcon(n.kind)),
                      title: Text(n.displayName),
                      subtitle: Text(protocolName(context, n.protocol)),
                      onTap: () => Navigator.pop(context, n),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
