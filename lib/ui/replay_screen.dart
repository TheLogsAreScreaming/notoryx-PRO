import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/app_controller.dart';
import '../app/trusted_nodes.dart';
import '../mesh/model.dart';
import '../mesh/replay.dart';
import 'common.dart';
import 'map_tiles.dart';

/// Plays back where nodes went over one day, on the map, with a time
/// scrubber. Shows your team (trusted nodes) by default, or everyone.
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.app, this.tiles, this.day});

  final AppController app;
  final MapTiles? tiles;

  /// The day to open on; today when null.
  final DateTime? day;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

/// How fast playback runs: replayed minutes per real second.
const replaySpeeds = [1, 5, 15, 60];

class _ReplayScreenState extends State<ReplayScreen> {
  late DateTime _day = DateUtils.dateOnly(widget.day ?? DateTime.now());
  List<Track> _tracks = const [];
  Map<String, Node> _nodes = const {};
  Set<String> _team = const {};
  Set<DateTime> _daysWithData = const {};
  bool _teamOnly = true;
  final Set<String> _hidden = {};
  bool _loading = true;
  Object? _error;
  DateTime? _t;
  bool _playing = false;
  int _speed = 5;
  Timer? _timer;

  static String _id(RadioId r, NodeKey k) => '$r/$k';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final store = widget.app.store;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = dayBounds(_day);
      final tracks = await store.tracks(from, to);
      final nodes = <String, Node>{};
      for (final r in await store.radios()) {
        for (final n in await store.nodes(r.id)) {
          nodes[_id(n.radioId, n.key)] = n;
        }
      }
      final trust = TrustState(
        marked: TrustedNodes.decode(
          await store.preference(TrustedNodes.markedPref),
        ),
        verifications: await store.verifications(),
      );
      final favorites = favoriteKeys(nodes.values);
      final days = await store.daysWithPositions();
      if (!mounted) return;
      final span = timeSpan(tracks);
      setState(() {
        _tracks = tracks;
        _nodes = nodes;
        _team = {
          for (final e in nodes.entries)
            if (trust.trusts(e.value, favorites: favorites)) e.key,
        };
        _daysWithData = {for (final d in days) DateUtils.dateOnly(d)};
        _t = span?.$2;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<Track> get _shown => [
    for (final t in _tracks)
      if ((!_teamOnly || _team.contains(_id(t.radio, t.node))) &&
          t.points.isNotEmpty)
        t,
  ];

  String _name(Track t) =>
      _nodes[_id(t.radio, t.node)]?.displayName ?? t.node.short;

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: today.subtract(const Duration(days: 31)),
      lastDate: today,
      selectableDayPredicate: (d) =>
          DateUtils.isSameDay(d, today) ||
          DateUtils.isSameDay(d, _day) ||
          _daysWithData.contains(DateUtils.dateOnly(d)),
    );
    if (picked == null || !mounted) return;
    _stop();
    setState(() => _day = DateUtils.dateOnly(picked));
    await _load();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _playing = false);
  }

  void _play((DateTime, DateTime) span) {
    if (_playing) {
      _stop();
      return;
    }
    var t = _t ?? span.$1;
    if (!t.isBefore(span.$2)) t = span.$1;
    setState(() {
      _playing = true;
      _t = t;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final next = _t!.add(Duration(seconds: _speed * 6));
      if (!next.isBefore(span.$2)) {
        setState(() => _t = span.$2);
        _stop();
      } else {
        setState(() => _t = next);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    final shown = _shown;
    final span = timeSpan(shown);
    final t = _t == null || span == null
        ? null
        : (_t!.isBefore(span.$1)
              ? span.$1
              : _t!.isAfter(span.$2)
              ? span.$2
              : _t!);
    final palette = _palette(Theme.of(context).colorScheme);
    final visible = [
      for (final (i, tr) in shown.indexed)
        if (!_hidden.contains(_id(tr.radio, tr.node))) (i, tr),
    ];
    String clock(DateTime d) =>
        m.formatTimeOfDay(TimeOfDay.fromDateTime(d.toLocal()));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.drTitle),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(m.formatMediumDate(_day)),
            onPressed: _pickDay,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? EmptyState(l.drFailed('$_error'), icon: Icons.error_outline)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(value: true, label: Text(l.drTeam)),
                          ButtonSegment(value: false, label: Text(l.drAll)),
                        ],
                        selected: {_teamOnly},
                        onSelectionChanged: (v) =>
                            setState(() => _teamOnly = v.single),
                      ),
                      const SizedBox(width: 8),
                      for (final (i, tr) in shown.indexed)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: FilterChip(
                            avatar: _Dot(
                              color: palette[i % palette.length],
                              label: _initials(_name(tr)),
                            ),
                            label: Text(_name(tr)),
                            selected: !_hidden.contains(_id(tr.radio, tr.node)),
                            onSelected: (on) => setState(() {
                              final id = _id(tr.radio, tr.node);
                              on ? _hidden.remove(id) : _hidden.add(id);
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                if (span == null || t == null)
                  Expanded(
                    child: EmptyState(
                      _teamOnly && _tracks.isNotEmpty ? l.drNoTeam : l.drEmpty,
                      icon: Icons.history_toggle_off,
                    ),
                  )
                else ...[
                  Expanded(
                    child: Semantics(
                      label: l.drMapLabel(clock(t), visible.length),
                      child: ExcludeSemantics(
                        child: _ReplayMap(
                          key: ValueKey(_day),
                          tiles: widget.tiles,
                          time: t,
                          tracks: [
                            for (final (i, tr) in visible)
                              (tr, palette[i % palette.length], _name(tr)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: [
                        IconButton.filled(
                          tooltip: _playing ? l.drPause : l.drPlay,
                          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                          onPressed: () => _play(span),
                        ),
                        Expanded(
                          child: Slider(
                            value: t.millisecondsSinceEpoch.toDouble(),
                            min: span.$1.millisecondsSinceEpoch.toDouble(),
                            max: span.$1 == span.$2
                                ? span.$1.millisecondsSinceEpoch + 1.0
                                : span.$2.millisecondsSinceEpoch.toDouble(),
                            label: clock(t),
                            semanticFormatterCallback: (v) => clock(
                              DateTime.fromMillisecondsSinceEpoch(v.round()),
                            ),
                            onChanged: (v) {
                              _stop();
                              setState(
                                () => _t = DateTime.fromMillisecondsSinceEpoch(
                                  v.round(),
                                ),
                              );
                            },
                          ),
                        ),
                        Text(clock(t)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text(l.drSpeed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: [
                                for (final s in replaySpeeds)
                                  ButtonSegment(
                                    value: s,
                                    label: Text(l.drSpeedValue(s)),
                                    tooltip: l.drSpeedHelp(s),
                                  ),
                              ],
                              selected: {_speed},
                              onSelectionChanged: (v) =>
                                  setState(() => _speed = v.single),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 132,
                    child: ListView(
                      children: [
                        for (final (i, tr) in visible)
                          _WhereRow(
                            color: palette[i % palette.length],
                            name: _name(tr),
                            point: tr.at(t),
                            clock: clock,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final s = parts.length > 1
        ? '${parts[0].characters.first}${parts[1].characters.first}'
        : name.characters.take(2).toString();
    return s.toUpperCase();
  }

  /// Distinct track colours from the theme; names and initials carry the
  /// identity too, so colour is never the only cue.
  static List<Color> _palette(ColorScheme s) => [
    s.primary,
    s.tertiary,
    s.error,
    s.secondary,
    Color.alphaBlend(s.primary.withValues(alpha: 0.5), s.tertiary),
    s.inversePrimary,
  ];
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});

  final Color color;
  final String label;

  /// Of the theme's surface and on-surface colours, the one that stands
  /// out more against [background].
  static Color readableOn(Color background, ColorScheme s) {
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
    }

    return contrast(background, s.surface) >= contrast(background, s.onSurface)
        ? s.surface
        : s.onSurface;
  }

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: color,
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: readableOn(color, Theme.of(context).colorScheme),
      ),
    ),
  );
}

class _WhereRow extends StatelessWidget {
  const _WhereRow({
    required this.color,
    required this.name,
    required this.point,
    required this.clock,
  });

  final Color color;
  final String name;
  final TrackPoint? point;
  final String Function(DateTime) clock;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = point;
    return MergeSemantics(
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle, color: color, size: 14),
        title: Text(name),
        subtitle: Text(
          p == null
              ? l.drNotYet
              : l.drSeenAt(
                  clock(p.time),
                  '${p.position.latitude.toStringAsFixed(5)}, '
                  '${p.position.longitude.toStringAsFixed(5)}',
                ),
        ),
      ),
    );
  }
}

class _ReplayMap extends StatelessWidget {
  const _ReplayMap({
    super.key,
    required this.tiles,
    required this.time,
    required this.tracks,
  });

  final MapTiles? tiles;
  final DateTime time;
  final List<(Track, Color, String)> tracks;

  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = [
      for (final (t, _, _) in tracks)
        for (final p in t.points) _ll(p.position),
    ];
    if (all.isEmpty) return ColoredBox(color: scheme.surfaceContainerHighest);
    final distinct = {for (final p in all) '${p.latitude},${p.longitude}'};
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: distinct.length > 1
            ? CameraFit.coordinates(
                coordinates: all,
                padding: const EdgeInsets.all(40),
                maxZoom: 16,
              )
            : null,
        initialCenter: all.first,
        initialZoom: 14,
      ),
      children: [
        if (tiles case final t?)
          TileLayer(
            urlTemplate: MapTiles.urlTemplate,
            userAgentPackageName: MapTiles.userAgentPackageName,
            tileProvider: t.provider,
          )
        else
          ColoredBox(color: scheme.surfaceContainerHighest),
        PolylineLayer(
          polylines: [
            for (final (t, color, _) in tracks)
              if (t.trailUntil(time) case final trail when trail.length > 1)
                Polyline(
                  points: trail.map(_ll).toList(),
                  strokeWidth: 3,
                  color: color.withValues(alpha: 0.8),
                ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final (t, color, name) in tracks)
              if (t.at(time) case final p?)
                Marker(
                  point: _ll(p.position),
                  width: 120,
                  height: 46,
                  child: Column(
                    children: [
                      Icon(Icons.location_on, color: color, size: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        if (tiles != null)
          const RichAttributionWidget(
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
      ],
    );
  }
}
