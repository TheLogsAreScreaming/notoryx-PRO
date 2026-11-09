import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/message_scheduler.dart';
import '../mesh/model.dart';
import 'common.dart';

/// Writes messages to send later, and lists those waiting in a conversation.
Future<void> showScheduleSheet(
  BuildContext context, {
  required MessageScheduler scheduler,
  required Conversation conversation,
  required int maxBytes,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _ScheduleSheet(
    scheduler: scheduler,
    conversation: conversation,
    maxBytes: maxBytes,
  ),
);

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({
    required this.scheduler,
    required this.conversation,
    required this.maxBytes,
  });

  final MessageScheduler scheduler;
  final Conversation conversation;
  final int maxBytes;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final _text = TextEditingController();
  late final _list = widget.scheduler.watch();
  DateTime? _at;
  int? _preset;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _preset = null;
      _at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final at = _preset == null
        ? _at!
        : DateTime.now().add(Duration(minutes: _preset!));
    await widget.scheduler.add(widget.conversation, _text.text.trim(), at);
    if (!mounted) return;
    setState(() {
      _text.clear();
      _at = null;
      _preset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final used = utf8.encode(_text.text.trim()).length;
    final tooLong = used > widget.maxBytes;
    final when = _preset != null || (_at?.isAfter(DateTime.now()) ?? false);
    final at = _at;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.scheduleTitle, style: text.titleLarge),
              Text(l.scheduleHelp),
              TextField(
                key: const Key('schedule-text'),
                controller: _text,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l.composerHint,
                  errorText: tooLong
                      ? l.composerBytes(used, widget.maxBytes)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (minutes, label) in [
                    (15, l.scheduleIn15),
                    (60, l.scheduleIn60),
                    (240, l.scheduleIn240),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _preset == minutes,
                      onSelected: (_) => setState(() {
                        _preset = minutes;
                        _at = null;
                      }),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(
                      at == null
                          ? l.schedulePick
                          : MaterialLocalizations.of(
                              context,
                            ).formatShortDate(at),
                    ),
                    onPressed: _pick,
                  ),
                ],
              ),
              FilledButton(
                key: const Key('schedule-save'),
                onPressed: !when || tooLong || _text.text.trim().isEmpty
                    ? null
                    : _save,
                child: Text(l.scheduleSave),
              ),
              StreamBuilder<List<ScheduledMessage>>(
                stream: _list,
                builder: (context, snap) => Column(
                  children: [
                    for (final m in snap.data ?? const <ScheduledMessage>[])
                      if (m.conversation == widget.conversation)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(m.text),
                          subtitle: Text(_status(context, m)),
                          trailing: IconButton(
                            tooltip: l.scheduleCancel,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => widget.scheduler.remove(m.id),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _status(BuildContext context, ScheduledMessage m) {
    final l = context.l10n;
    final loc = MaterialLocalizations.of(context);
    final time =
        '${loc.formatShortDate(m.at)} '
        '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(m.at))}';
    return switch (m.state) {
      ScheduleState.waiting => time,
      ScheduleState.missed => l.scheduleMissed(time),
      ScheduleState.failed => l.scheduleFailed(time),
    };
  }
}
