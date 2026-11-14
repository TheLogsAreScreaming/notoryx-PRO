import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/mesh.dart';
import '../mesh/topology.dart';
import '../radio/radio_link.dart';
import 'common.dart';
import 'conversation_screen.dart';

/// Where each dot goes.
class TopologyLayout {
  const TopologyLayout({
    required this.centers,
    required this.radii,
    required this.center,
    required this.ringGap,
    required this.rings,
  });

  final Map<String, Offset> centers;
  final Map<String, double> radii;
  final Offset center;
  final double ringGap;
  final int rings;

  /// The dot under [p], allowing a finger-sized margin.
  String? hit(Offset p, {double slop = 16}) {
    String? best;
    var bestD = double.infinity;
    for (final e in centers.entries) {
      final d = (e.value - p).distance;
      if (d <= (radii[e.key] ?? 0) + slop && d < bestD) {
        best = e.key;
        bestD = d;
      }
    }
    return best;
  }
}

/// You in the middle, each node on the ring for its hops. Rings after the
/// first are ordered by where their linked dots sit on the ring inside, so
/// links cross less.
TopologyLayout layoutTopology(Topology t, Size size) {
  final rings = t.rings;
  final center = Offset(size.width / 2, size.height / 2);
  final maxR = math.max(0.0, math.min(size.width, size.height) / 2 - 18);
  final gap = rings == 0 ? 0.0 : maxR / rings;
  final maxRoutes = t.nodes.values.fold(1, (m, n) => math.max(m, n.routes));
  final neighbours = <String, Map<String, int>>{};
  for (final l in t.links) {
    (neighbours[l.a] ??= {})[l.b] = l.count;
    (neighbours[l.b] ??= {})[l.a] = l.count;
  }
  final angle = <String, double>{topologyYou: 0};
  final centers = <String, Offset>{topologyYou: center};
  final radii = <String, double>{topologyYou: 11};
  for (var r = 1; r <= rings; r++) {
    final ids = [for (final n in t.ring(r)) n.id];
    if (r > 1) {
      double score(String id) {
        var x = 0.0, y = 0.0;
        for (final e in (neighbours[id] ?? const <String, int>{}).entries) {
          final a = angle[e.key];
          if (a == null) continue;
          x += math.cos(a) * e.value;
          y += math.sin(a) * e.value;
        }
        if (x == 0 && y == 0) return double.infinity;
        final a = math.atan2(y, x);
        return a < 0 ? a + 2 * math.pi : a;
      }

      final s = {for (final id in ids) id: score(id)};
      ids.sort((a, b) => s[a]!.compareTo(s[b]!));
    }
    for (var i = 0; i < ids.length; i++) {
      final a =
          -math.pi / 2 + (i + (r.isEven ? .5 : 0)) * 2 * math.pi / ids.length;
      angle[ids[i]] = a < 0 ? a + 2 * math.pi : a;
      centers[ids[i]] =
          center + Offset(math.cos(a) * gap * r, math.sin(a) * gap * r);
      radii[ids[i]] =
          5 + 6 * math.sqrt((t.nodes[ids[i]]?.routes ?? 0) / maxRoutes);
    }
  }
  return TopologyLayout(
    centers: centers,
    radii: radii,
    center: center,
    ringGap: gap,
    rings: rings,
  );
}

class _Painter extends CustomPainter {
  _Painter(this.t, this.layout, this.scheme, this.labelStyle, this.you);

  final Topology t;
  final TopologyLayout layout;
  final ColorScheme scheme;
  final TextStyle labelStyle;
  final String you;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = scheme.outlineVariant.withValues(alpha: .6);
    for (var i = 1; i <= layout.rings; i++) {
      canvas.drawCircle(layout.center, layout.ringGap * i, ring);
    }
    final maxCount = t.links.fold(1, (m, l) => math.max(m, l.count));
    for (final l in t.links) {
      final f = l.count / maxCount;
      canvas.drawLine(
        layout.centers[l.a]!,
        layout.centers[l.b]!,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1 + 4 * f
          ..color = scheme.primary.withValues(alpha: .25 + .55 * f),
      );
    }
    for (final n in t.nodes.values) {
      final c = layout.centers[n.id]!;
      final r = layout.radii[n.id]!;
      final color = n.id == topologyYou
          ? scheme.tertiary
          : n.unknown
          ? scheme.outline
          : n.node?.protocol == RadioProtocol.meshtastic
          ? scheme.secondary
          : scheme.primary;
      canvas.drawCircle(c, r, Paint()..color = color);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = scheme.surface,
      );
    }
    final labelled = t.nodes.values.toList()
      ..sort((a, b) => b.routes.compareTo(a.routes));
    for (final n in [
      t.nodes[topologyYou]!,
      ...labelled.where((n) => n.id != topologyYou).take(14),
    ]) {
      final tp = TextPainter(
        text: TextSpan(
          text: n.id == topologyYou ? you : n.label,
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 110);
      final c = layout.centers[n.id]!;
      final r = layout.radii[n.id]!;
      final dx = (c.dx - tp.width / 2)
          .clamp(2.0, math.max(2.0, size.width - tp.width - 2))
          .toDouble();
      var dy = c.dy + r + 2;
      if (dy + tp.height > size.height) dy = c.dy - r - tp.height - 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dx - 3, dy - 1, tp.width + 6, tp.height + 2),
          const Radius.circular(4),
        ),
        Paint()..color = scheme.surface.withValues(alpha: .85),
      );
      tp.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.t != t || old.scheme != scheme || old.you != you;
}

/// How your radios see the mesh: you in the middle, nodes on rings by
/// hops, links from known routes.
class TopologyScreen extends StatelessWidget {
  const TopologyScreen({super.key, required this.app});

  final AppController app;

  void _open(BuildContext context, TopoNode n) {
    final node = n.node;
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.label, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  if (node != null) nodeKindName(sheet, node.kind),
                  if (n.unknown) l.topologyUnknownHop,
                  l.topologyHops(n.ring - 1),
                  if (n.routes > 0) l.topologyRoutes(n.routes),
                ].join(' · '),
              ),
              if (node != null &&
                  node.canMessage &&
                  node.kind != NodeKind.relay) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(l.topologyMessage),
                  onPressed: () {
                    Navigator.pop(sheet);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ConversationScreen(
                          app: app,
                          conversation: DirectConversation(
                            node.radioId,
                            node.key,
                          ),
                          title: node.displayName,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.topologyTitle)),
      body: ListenableBuilder(
        listenable: app.hopNaming,
        builder: (context, _) => StreamBuilder<List<Node>>(
          stream: app.store.watchAllNodes(),
          builder: (context, snap) {
            final t = Topology.build(
              snap.data ?? const [],
              resolve: (n, known) => app.hopNaming.resolve(
                n,
                known,
                from: app.connections
                    .where((c) => c.radio?.id == n.radioId)
                    .map((c) => c.radio?.position)
                    .nonNulls
                    .firstOrNull,
              ),
            );
            if (t.nodes.length <= 1) {
              return EmptyState(l.topologyEmpty, icon: Icons.hub_outlined);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final side = box.maxWidth.clamp(220.0, 560.0);
                    final size = Size(box.maxWidth, side);
                    final layout = layoutTopology(t, size);
                    return Semantics(
                      label: l.topologySemantics(t.nodes.length - 1, t.rings),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final id = layout.hit(d.localPosition);
                          if (id != null && id != topologyYou) {
                            _open(context, t.nodes[id]!);
                          }
                        },
                        child: SizedBox.fromSize(
                          key: const Key('topology'),
                          size: size,
                          child: CustomPaint(
                            painter: _Painter(
                              t,
                              layout,
                              scheme,
                              (Theme.of(context).textTheme.labelSmall ??
                                      const TextStyle())
                                  .copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                              l.topologyYou,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  l.topologyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                for (var r = 1; r <= t.rings; r++) ...[
                  Text(
                    l.topologyRing(r - 1),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final n in t.ring(r))
                    ListTile(
                      key: Key('topo-${n.id}'),
                      dense: true,
                      leading: Icon(
                        n.node == null
                            ? Icons.help_outline
                            : nodeKindIcon(n.node!.kind),
                      ),
                      title: Text(n.label),
                      subtitle: n.routes > 0
                          ? Text(l.topologyRoutes(n.routes))
                          : null,
                      onTap: () => _open(context, n),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
