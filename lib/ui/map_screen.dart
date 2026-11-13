import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/app_controller.dart';
import '../app/radio_connection.dart';
import '../app/trusted_nodes.dart';
import '../mesh/mesh.dart';
import '../radio/radio.dart';
import 'admin_screens.dart';
import '../mesh/node_merge.dart';
import '../mesh/places.dart';
import 'common.dart';
import 'places_screen.dart';
import 'route_screen.dart';
import 'themes.dart';
import 'conversation_screen.dart';
import 'diagnostics_screen.dart';
import 'verify_screen.dart';
import 'map_tiles.dart';
import 'meshtastic_admin_screen.dart';
import 'telemetry_screen.dart';

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

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  late final Stream<List<Node>> _nodes = widget.app.store.watchAllNodes();
  late final Stream<List<Place>> _places = widget.app.store.watchPlaces();
  late final Stream<TrustState> _trust = TrustedNodes.watch(widget.app.store);
  Node? _route;

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
  Widget build(BuildContext context) {
    final l = context.l10n;
    return StreamBuilder<TrustState>(
      stream: _trust,
      builder: (context, tSnap) => StreamBuilder<List<Node>>(
        stream: _nodes,
        builder: (context, snap) {
          final all = snap.data ?? const <Node>[];
          final trust = tSnap.data ?? const TrustState();
          final favorites = favoriteKeys(all);
          // One pin per node, even when several of your radios hear it.
          final placed = [
            for (final m in mergeAcrossRadios(all))
              if (m.node.position != null &&
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
                      ),
                    _placesLayer(),
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
                              node: n,
                              onTap: () => _openNode(n, all),
                            ),
                          ),
                      ],
                    ),
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
                right: 16,
                bottom: 72,
                child: FloatingActionButton.small(
                  heroTag: 'map-places',
                  tooltip: l.placesTitle,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlacesScreen(app: widget.app),
                    ),
                  ),
                  child: const Icon(Icons.bookmark_border),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  heroTag: 'map-fit',
                  tooltip: l.mapFitAll,
                  onPressed: () => _fit(points),
                  child: const Icon(Icons.fit_screen),
                ),
              ),
            ],
          );
        },
      ),
    );
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

  /// Our radio → known repeaters → the node; hops without a known position
  /// are skipped. Null when there is nothing to draw.
  List<LatLng>? _routeLine(Node target, List<Node> all) {
    final start = widget.app.connections
        .where((c) => c.radio?.id == target.radioId)
        .map((c) => c.radio?.position)
        .nonNulls
        .firstOrNull;
    final hops = resolveRoute(target, all);
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
        hops: resolveRoute(n, all),
        routeShown: _route?.key == n.key,
        tiles: widget.tiles,
      ),
    );
    if (showRoute == null || !mounted) return;
    setState(() => _route = showRoute ? n : null);
  }
}

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({required this.node, required this.onTap});

  final Node node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = meshColor(node.protocol, Theme.of(context));
    return Semantics(
      button: true,
      label: '${node.displayName}, ${protocolName(context, node.protocol)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
          child: Icon(nodeKindIcon(node.kind), color: color, size: 22),
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
  });

  final AppController app;
  final Node node;
  final List<RouteHop> hops;
  final bool routeShown;

  /// Map background for trace cards.
  final MapTiles? tiles;

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
      if (n.lastHeard != null) l.lastHeard(ago(context, n.lastHeard!)),
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
                Icon(nodeKindIcon(n.kind)),
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
                    '• ${h.node?.displayName ?? l.mapRouteUnknownHop(h.prefix)}',
                  ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
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
                if ((_connection()?.radio?.position, n.position) case (
                  final from?,
                  final to?,
                ))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.landscape_outlined),
                    label: Text(l.lineOfSight),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => LineOfSightSheet(
                        from: from,
                        to: to,
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
