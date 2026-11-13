import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/timeline.dart';
import '../mesh/mesh.dart';
import '../mesh/places.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'conversation_screen.dart';

/// One feed of everything that happened: messages, nodes heard for the
/// first time, signal changes and new waypoints, newest first, with chips
/// to show only some kinds.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.app});

  final AppController app;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  Set<TimelineKind> _kinds = {...TimelineKind.values};
  late final Stream<List<StoredMessage>> _messages = widget.app.store
      .watchRecentMessages();
  final Map<String, String> _titles = {};

  Future<void> _title(Conversation c) async {
    if (_titles.containsKey(c.key)) return;
    _titles[c.key] = '';
    final t = await widget.app.store.conversationTitle(c);
    if (mounted) setState(() => _titles[c.key] = t);
  }

  Future<void> _clear() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.tlClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.tlClear),
          ),
        ],
      ),
    );
    if (ok == true) await widget.app.timeline.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final recorder = widget.app.timeline;
    String kindName(TimelineKind k) => switch (k) {
      TimelineKind.message => l.tlMessages,
      TimelineKind.nodeJoined => l.tlNewNodes,
      TimelineKind.signalChanged => l.tlSignal,
      TimelineKind.waypoint => l.tlWaypoints,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tlTitle),
        actions: [
          IconButton(
            tooltip: l.tlClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final k in TimelineKind.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: Text(kindName(k)),
                      selected: _kinds.contains(k),
                      onSelected: (on) => setState(() {
                        _kinds = on ? {..._kinds, k} : ({..._kinds}..remove(k));
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: recorder,
              builder: (context, _) => StreamBuilder<List<StoredMessage>>(
                stream: _messages,
                builder: (context, snap) {
                  final items = mergeTimeline(
                    recorder.events,
                    snap.data ?? const [],
                    _kinds,
                  );
                  if (items.isEmpty) {
                    return EmptyState(l.tlEmpty, icon: Icons.timeline);
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final day = DateUtils.dateOnly(e.time.toLocal());
                      final newDay =
                          i == 0 ||
                          DateUtils.dateOnly(items[i - 1].time.toLocal()) !=
                              day;
                      if (e.message case final m?) {
                        _title(m.message.conversation);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (newDay) _DayHeader(day),
                          _EventTile(
                            event: e,
                            conversationTitle: e.message == null
                                ? null
                                : _titles[e.message!.message.conversation.key],
                            onOpen: e.message == null
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ConversationScreen(
                                        app: widget.app,
                                        conversation:
                                            e.message!.message.conversation,
                                        title:
                                            _titles[e
                                                .message!
                                                .message
                                                .conversation
                                                .key] ??
                                            '',
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);

  final DateTime day;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        MaterialLocalizations.of(context).formatFullDate(day),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, this.conversationTitle, this.onOpen});

  final TimelineEvent event;
  final String? conversationTitle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final e = event;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(e.time.toLocal()));
    final (IconData icon, String title, String detail) = switch (e.kind) {
      TimelineKind.message => () {
        final m = e.message!.message;
        final who = m.outgoing
            ? l.tlYou
            : (e.title.isEmpty ? l.tlSomeone : e.title);
        final where = conversationTitle ?? '';
        return (
          m.outgoing ? Icons.north_east : Icons.chat_bubble_outline,
          where.isEmpty ? who : l.tlMessageIn(who, where),
          m.text,
        );
      }(),
      TimelineKind.nodeJoined => (
        Icons.person_add_alt_outlined,
        l.tlNodeJoined(e.title),
        e.snr == null ? '' : l.pathSnr(e.snr!.toStringAsFixed(1)),
      ),
      TimelineKind.signalChanged => (
        (e.barsAfter ?? 0) > (e.barsBefore ?? 0)
            ? Icons.signal_cellular_alt
            : Icons.signal_cellular_alt_1_bar,
        l.tlSignalChanged(e.title),
        [
          l.tlBars(e.barsBefore ?? 0, e.barsAfter ?? 0),
          if (e.snr != null) l.pathSnr(e.snr!.toStringAsFixed(1)),
        ].join(' · '),
      ),
      TimelineKind.waypoint => (
        switch (e.placeKind) {
          PlaceKind.route => Icons.route,
          PlaceKind.geofence => Icons.fence,
          _ => Icons.place_outlined,
        },
        switch (e.placeKind) {
          PlaceKind.route => l.tlRouteAdded(e.title),
          PlaceKind.geofence => l.tlGeofenceAdded(e.title),
          _ => l.tlWaypointAdded(e.title),
        },
        '',
      ),
    };
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: detail.isEmpty
          ? null
          : Text(detail, maxLines: 2, overflow: TextOverflow.fade),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time, style: Theme.of(context).textTheme.bodySmall),
          if (e.protocol case final p?)
            Text(
              protocolName(context, p),
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
      onTap: onOpen,
    );
  }
}
