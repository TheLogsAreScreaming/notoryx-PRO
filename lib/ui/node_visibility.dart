import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/ignored_nodes.dart';
import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../mesh/node_merge.dart';
import '../mesh/stale.dart';
import '../radio/radio.dart';
import 'common.dart';

/// A short age such as "5 min", "3 h" or "2 d".
String shortAge(BuildContext context, Duration d) {
  final l = context.l10n;
  if (d.inHours < 1) return l.ageMinutes(d.inMinutes < 1 ? 1 : d.inMinutes);
  if (d.inDays < 1) return l.ageHours(d.inHours);
  return l.ageDays(d.inDays);
}

/// The name of a "Mark nodes stale after" choice.
String staleChoiceName(BuildContext context, Duration? after) {
  final l = context.l10n;
  if (after == null) return l.staleOff;
  return after.inHours <= 24
      ? l.ageHours(after.inHours)
      : l.ageDays(after.inDays);
}

/// The "Mark nodes stale after" setting as it changes.
Stream<Duration?> watchStaleAfter(AppController app) =>
    app.store.watchPreference(StaleAfter.pref).map(StaleAfter.decode);

/// "stale · 3 d" with a clock icon, so the state isn't shown by colour.
class StaleBadge extends StatelessWidget {
  const StaleBadge(this.age, {super.key});

  /// How long since the node was heard.
  final Duration age;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final text = context.l10n.staleAge(shortAge(context, age));
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off, size: 16, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Lets the person pick how long until nodes are marked stale.
Future<void> pickStaleAfter(BuildContext context, AppController app) async {
  final current = StaleAfter.decode(
    await app.store.preference(StaleAfter.pref),
  );
  if (!context.mounted) return;
  final picked = await showDialog<(Duration?,)>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.l10n.staleAfterTitle),
      children: [
        for (final c in StaleAfter.choices)
          SimpleDialogOption(
            key: Key('stale-${c?.inMinutes ?? 0}'),
            onPressed: () => Navigator.pop(context, (c,)),
            child: Semantics(
              selected: c == current,
              child: Row(
                children: [
                  Icon(
                    c == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(staleChoiceName(context, c)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  if (picked == null) return;
  await app.store.setPreference(StaleAfter.pref, StaleAfter.encode(picked.$1));
}

/// Asks before ignoring [key] (called [name]), then ignores it on the phone and, where
/// they support it, on every connected Meshtastic radio. Stopping needs
/// no confirmation.
Future<void> setNodeIgnored(
  BuildContext context,
  AppController app,
  NodeKey key,
  String name, {
  required bool ignored,
}) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (ignored) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.ignoreConfirmTitle(name)),
        content: Text(l.ignoreConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('ignore-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.ignoreNode),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await IgnoredNodes.set(app.store, key, ignored: ignored);
  if (key.protocol != RadioProtocol.meshtastic) return;
  for (final c in app.connections) {
    if (c is! MeshtasticConnection || !c.canIgnoreNodes) continue;
    try {
      await c.setNodeIgnored(key, ignored: ignored);
    } on Object catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.ignoreRadioFailed(RadioConnection.describeError(e)),
            ),
          ),
        );
    }
  }
}

/// Every ignored node, each with "Show again".
class IgnoredNodesScreen extends StatelessWidget {
  const IgnoredNodesScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.ignoredTitle)),
      body: StreamBuilder<Set<String>>(
        stream: IgnoredNodes.watch(app.store),
        builder: (context, iSnap) => StreamBuilder<List<Node>>(
          stream: app.store.watchAllNodes(),
          builder: (context, nSnap) {
            final ignored = iSnap.data ?? const <String>{};
            if (ignored.isEmpty) {
              return EmptyState(l.ignoredEmpty, icon: Icons.visibility_off);
            }
            final known = {
              for (final m in mergeAcrossRadios(nSnap.data ?? const []))
                m.node.key.toString(): m.node,
            };
            final keys = ignored.toList()
              ..sort(
                (a, b) => (known[a]?.displayName ?? a).toLowerCase().compareTo(
                  (known[b]?.displayName ?? b).toLowerCase(),
                ),
              );
            return ListView(
              children: [
                for (final k in keys)
                  if (NodeKey.tryParse(k) case final key?)
                    _IgnoredTile(app: app, nodeKey: key, node: known[k]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IgnoredTile extends StatelessWidget {
  const _IgnoredTile({required this.app, required this.nodeKey, this.node});

  final AppController app;
  final NodeKey nodeKey;
  final Node? node;

  @override
  Widget build(BuildContext context) {
    final n = node;
    return ListTile(
      leading: Icon(
        n == null ? Icons.visibility_off_outlined : nodeKindIcon(n.kind),
      ),
      title: Text(n?.displayName ?? nodeKey.short),
      subtitle: Text(protocolName(context, nodeKey.protocol)),
      trailing: TextButton(
        key: Key('show-again-$nodeKey'),
        onPressed: () => setNodeIgnored(
          context,
          app,
          nodeKey,
          n?.displayName ?? nodeKey.short,
          ignored: false,
        ),
        child: Text(context.l10n.ignoredShowAgain),
      ),
    );
  }
}
