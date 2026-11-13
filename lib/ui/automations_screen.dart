import 'package:flutter/material.dart' hide Radio;
import 'package:intl/intl.dart';

import '../app/app_controller.dart';
import '../app/automations.dart';
import '../l10n/app_localizations.dart';
import '../mesh/model.dart';
import '../mesh/places.dart';
import 'common.dart';

/// What the editors can pick from: nodes, conversations, geofences and
/// radios, loaded once when a screen opens.
class AutomationChoices {
  const AutomationChoices({
    this.nodes = const [],
    this.conversations = const {},
    this.fences = const [],
    this.radios = const [],
  });

  final List<Node> nodes;

  /// Conversations by key, with their titles.
  final Map<String, (Conversation, String)> conversations;
  final List<Place> fences;
  final List<Radio> radios;

  static Future<AutomationChoices> load(AppController app) async {
    final store = app.store;
    final radios = await store.radios();
    final nodes = [for (final r in radios) ...await store.nodes(r.id)]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final conversations = <String, (Conversation, String)>{};
    for (final s in await store.conversations()) {
      final c = s.conversation;
      conversations[c.key] = (c, await store.conversationTitle(c));
    }
    final fences = [
      for (final p in await store.places())
        if (p.kind == PlaceKind.geofence && p.radiusM != null) p,
    ];
    return AutomationChoices(
      nodes: nodes,
      conversations: conversations,
      fences: fences,
      radios: radios,
    );
  }

  String nodeName(RadioId radio, NodeKey key) =>
      nodes
          .where((n) => n.radioId == radio && n.key == key)
          .firstOrNull
          ?.displayName ??
      key.short;

  String conversationName(Conversation c) => conversations[c.key]?.$2 ?? c.key;

  String fenceName(int id) =>
      fences.where((p) => p.id == id).firstOrNull?.name ?? '#$id';

  String radioName(RadioId id) =>
      radios.where((r) => r.id == id).firstOrNull?.name ?? id.toString();
}

/// Words for a trigger, e.g. "Battery of Peak below 20%".
String describeTrigger(
  AppLocalizations l,
  MaterialLocalizations m,
  AutomationChoices c,
  AutoTrigger t,
) => switch (t) {
  BatteryTrigger(:final radio, :final node, :final below) => l.auBatteryDesc(
    c.nodeName(radio, node),
    below,
  ),
  TimeTrigger(:final hour, :final minute, :final weekdays) => [
    l.auTimeDesc(m.formatTimeOfDay(TimeOfDay(hour: hour, minute: minute))),
    if (weekdays.isNotEmpty)
      (weekdays.toList()..sort()).map((d) => m.narrowWeekdays[d % 7]).join(' '),
  ].join(' · '),
  GeofenceTrigger(:final place, :final enter, :final radio, :final node) =>
    (enter ? l.auEnterDesc : l.auLeaveDesc)(
      node == null || radio == null ? l.auAnyNode : c.nodeName(radio, node),
      c.fenceName(place),
    ),
  MessageTrigger(:final contains, :final conversation, :final directOnly) => [
    contains.isEmpty ? l.auMessageAny : l.auMessageHas(contains),
    if (conversation != null) c.conversationName(conversation),
    if (directOnly) l.auDirectOnly,
  ].join(' · '),
  PresenceTrigger(:final radio, :final node, :final online, :final after) =>
    (online ? l.auOnlineDesc : l.auOfflineDesc)(
      c.nodeName(radio, node),
      after.inMinutes,
    ),
};

/// Words for an action.
String describeAction(AppLocalizations l, AutomationChoices c, AutoAction a) =>
    switch (a) {
      SendAction(:final conversation, :final text) => l.auSendDesc(
        c.conversationName(conversation),
        text,
      ),
      AlertAction(:final text) => l.auAlertDesc(text),
      JoinChannelAction(:final radio) => l.auChannelDesc(c.radioName(radio)),
      SoundAction() => l.auSound,
      WebhookAction(:final url) => l.auWebhookDesc(
        Uri.tryParse(url)?.host ?? url,
      ),
    };

/// Lists automations, the switch that allows web requests, and what ran.
class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key, required this.app});

  final AppController app;

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  late final Future<AutomationChoices> _choices = AutomationChoices.load(
    widget.app,
  );

  AutomationEngine get _engine => widget.app.automations;

  Future<void> _edit(AutomationChoices c, [Automation? rule]) async {
    final s = _engine.settings;
    final result = await Navigator.of(context).push<_EditResult>(
      MaterialPageRoute(
        builder: (_) => AutomationEditor(
          choices: c,
          rule: rule ?? Automation(id: s.nextId, name: ''),
          isNew: rule == null,
        ),
      ),
    );
    if (result == null) return;
    final next = _engine.settings;
    final rules = [
      for (final r in next.rules)
        if (r.id != result.rule.id) r,
      if (!result.delete) result.rule,
    ]..sort((a, b) => a.id.compareTo(b.id));
    await _engine.save(next.copyWith(rules: rules));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    return FutureBuilder<AutomationChoices>(
      future: _choices,
      builder: (context, snap) {
        final c = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(l.auTitle)),
          floatingActionButton: c == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: Text(l.auAdd),
                  onPressed: () => _edit(c),
                ),
          body: c == null
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: _engine,
                  builder: (context, _) {
                    final s = _engine.settings;
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(l.auHelp),
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.public),
                          title: Text(l.auWebhooksAllow),
                          subtitle: Text(l.auWebhooksHelp),
                          value: s.webhooks,
                          onChanged: (v) =>
                              _engine.save(s.copyWith(webhooks: v)),
                        ),
                        const Divider(),
                        if (s.rules.isEmpty) ListTile(title: Text(l.auEmpty)),
                        for (final r in s.rules)
                          ListTile(
                            title: Text(r.name.isEmpty ? l.auUnnamed : r.name),
                            subtitle: Text(
                              [
                                (r.matchAll ? l.auWhenAll : l.auWhenAny)(
                                  r.triggers
                                      .map((t) => describeTrigger(l, m, c, t))
                                      .join('; '),
                                ),
                                l.auThen(
                                  r.actions
                                      .map((a) => describeAction(l, c, a))
                                      .join('; '),
                                ),
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            onTap: () => _edit(c, r),
                            trailing: Switch(
                              value: r.enabled,
                              onChanged: (v) => _engine.save(
                                s.copyWith(
                                  rules: [
                                    for (final x in s.rules)
                                      x.id == r.id ? x.copyWith(enabled: v) : x,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_engine.log.isNotEmpty) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              l.auRecent,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          for (final run in _engine.log.take(20))
                            ListTile(
                              dense: true,
                              leading: Icon(
                                run.ok
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                semanticLabel: run.ok
                                    ? l.auRunOk
                                    : l.auRunFailed,
                              ),
                              title: Text(
                                '${run.rule}: ${describeAction(l, c, run.action)}',
                              ),
                              subtitle: Text(
                                [
                                  m.formatTimeOfDay(
                                    TimeOfDay.fromDateTime(run.time),
                                  ),
                                  ?run.note,
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

class _EditResult {
  const _EditResult(this.rule, {this.delete = false});

  final Automation rule;
  final bool delete;
}

/// Edits one automation: its name, AND/OR, triggers, actions and cooldown.
class AutomationEditor extends StatefulWidget {
  const AutomationEditor({
    super.key,
    required this.choices,
    required this.rule,
    this.isNew = false,
  });

  final AutomationChoices choices;
  final Automation rule;
  final bool isNew;

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  late final _name = TextEditingController(text: widget.rule.name);
  late bool _all = widget.rule.matchAll;
  late List<AutoTrigger> _triggers = [...widget.rule.triggers];
  late List<AutoAction> _actions = [...widget.rule.actions];
  late Duration _cooldown = widget.rule.cooldown;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _triggers.isNotEmpty &&
      _actions.isNotEmpty;

  void _save() => Navigator.pop(
    context,
    _EditResult(
      widget.rule.copyWith(
        name: _name.text.trim(),
        matchAll: _all,
        triggers: _triggers,
        actions: _actions,
        cooldown: _cooldown,
      ),
    ),
  );

  Future<void> _addTrigger(String kind) async {
    final t = await showDialog<AutoTrigger>(
      context: context,
      builder: (_) => _TriggerDialog(kind: kind, choices: widget.choices),
    );
    if (t != null) setState(() => _triggers = [..._triggers, t]);
  }

  Future<void> _addAction(String kind) async {
    if (kind == 'sound') {
      setState(() => _actions = [..._actions, const SoundAction()]);
      return;
    }
    final a = await showDialog<AutoAction>(
      context: context,
      builder: (_) => _ActionDialog(kind: kind, choices: widget.choices),
    );
    if (a != null) setState(() => _actions = [..._actions, a]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    final c = widget.choices;
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? l.auAdd : l.auEdit),
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: l.auDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(
                context,
                _EditResult(widget.rule, delete: true),
              ),
            ),
          TextButton(onPressed: _valid ? _save : null, child: Text(l.auSave)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l.auName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(l.auWhen, style: title),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l.auAny)),
              ButtonSegment(value: true, label: Text(l.auAll)),
            ],
            selected: {_all},
            onSelectionChanged: (v) => setState(() => _all = v.single),
          ),
          for (final (i, t) in _triggers.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt),
              title: Text(describeTrigger(l, m, c, t)),
              trailing: IconButton(
                tooltip: l.auRemove(describeTrigger(l, m, c, t)),
                icon: const Icon(Icons.close),
                onPressed: () =>
                    setState(() => _triggers = [..._triggers]..removeAt(i)),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PopupMenuButton<String>(
              tooltip: l.auAddTrigger,
              onSelected: _addTrigger,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'battery', child: Text(l.auTBattery)),
                PopupMenuItem(value: 'time', child: Text(l.auTTime)),
                PopupMenuItem(
                  value: 'fence',
                  enabled: c.fences.isNotEmpty,
                  child: Text(l.auTFence),
                ),
                PopupMenuItem(value: 'message', child: Text(l.auTMessage)),
                PopupMenuItem(value: 'online', child: Text(l.auTPresence)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add),
                    const SizedBox(width: 8),
                    Text(l.auAddTrigger),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l.auDo, style: title),
          for (final (i, a) in _actions.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.needsInternet ? Icons.public : Icons.play_arrow),
              title: Text(describeAction(l, c, a)),
              subtitle: a.needsInternet ? Text(l.auNeedsInternet) : null,
              trailing: IconButton(
                tooltip: l.auRemove(describeAction(l, c, a)),
                icon: const Icon(Icons.close),
                onPressed: () =>
                    setState(() => _actions = [..._actions]..removeAt(i)),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PopupMenuButton<String>(
              tooltip: l.auAddAction,
              onSelected: _addAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'send',
                  enabled: c.conversations.isNotEmpty,
                  child: Text(l.auASend),
                ),
                PopupMenuItem(value: 'alert', child: Text(l.auAAlert)),
                PopupMenuItem(
                  value: 'channel',
                  enabled: c.radios.isNotEmpty,
                  child: Text(l.auAChannel),
                ),
                PopupMenuItem(value: 'sound', child: Text(l.auSound)),
                PopupMenuItem(value: 'webhook', child: Text(l.auAWebhook)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add),
                    const SizedBox(width: 8),
                    Text(l.auAddAction),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _cooldown.inMinutes,
            decoration: InputDecoration(labelText: l.auCooldown),
            items: [
              for (final min in {1, 5, 15, 60, 240, _cooldown.inMinutes})
                DropdownMenuItem(value: min, child: Text(l.auMinutes(min))),
            ],
            onChanged: (v) =>
                setState(() => _cooldown = Duration(minutes: v ?? 5)),
          ),
          const SizedBox(height: 8),
          Text(l.auLimits, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TriggerDialog extends StatefulWidget {
  const _TriggerDialog({required this.kind, required this.choices});

  final String kind;
  final AutomationChoices choices;

  @override
  State<_TriggerDialog> createState() => _TriggerDialogState();
}

class _TriggerDialogState extends State<_TriggerDialog> {
  Node? _node;
  int _below = 20;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  final Set<int> _days = {};
  Place? _fence;
  bool _enter = true;
  bool _online = true;
  int _after = 30;
  bool _dm = false;
  String? _conv;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  AutoTrigger? get _result => switch (widget.kind) {
    'battery' when _node != null => BatteryTrigger(
      radio: _node!.radioId,
      node: _node!.key,
      below: _below,
    ),
    'time' => TimeTrigger(
      hour: _time.hour,
      minute: _time.minute,
      weekdays: {..._days},
    ),
    'fence' when _fence != null => GeofenceTrigger(
      place: _fence!.id,
      enter: _enter,
      radio: _node?.radioId,
      node: _node?.key,
    ),
    'message' => MessageTrigger(
      contains: _text.text.trim(),
      conversation: _conv == null
          ? null
          : widget.choices.conversations[_conv]!.$1,
      directOnly: _dm,
    ),
    'online' when _node != null => PresenceTrigger(
      radio: _node!.radioId,
      node: _node!.key,
      online: _online,
      after: Duration(minutes: _after),
    ),
    _ => null,
  };

  Widget _nodePicker(AppLocalizations l, {bool any = false}) =>
      DropdownButtonFormField<Node?>(
        initialValue: _node,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.auNode),
        items: [
          if (any) DropdownMenuItem(value: null, child: Text(l.auAnyNode)),
          for (final n in widget.choices.nodes)
            DropdownMenuItem(
              value: n,
              child: Text(
                '${n.displayName} · ${protocolName(context, n.protocol)}',
              ),
            ),
        ],
        onChanged: (n) => setState(() => _node = n),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = MaterialLocalizations.of(context);
    final c = widget.choices;
    final body = switch (widget.kind) {
      'battery' => [
        _nodePicker(l),
        const SizedBox(height: 12),
        Text(l.auBelowPercent(_below)),
        Slider(
          value: _below.toDouble(),
          min: 5,
          max: 95,
          divisions: 18,
          label: '$_below%',
          semanticFormatterCallback: (v) => l.auBelowPercent(v.round()),
          onChanged: (v) => setState(() => _below = v.round()),
        ),
      ],
      'time' => [
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule),
          label: Text(m.formatTimeOfDay(_time)),
          onPressed: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: _time,
            );
            if (t != null) setState(() => _time = t);
          },
        ),
        const SizedBox(height: 8),
        Text(l.auDaysHelp),
        Wrap(
          spacing: 4,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Semantics(
                  label: _weekdayName(context, d),
                  child: ExcludeSemantics(child: Text(m.narrowWeekdays[d % 7])),
                ),
                tooltip: _weekdayName(context, d),
                selected: _days.contains(d),
                onSelected: (on) =>
                    setState(() => on ? _days.add(d) : _days.remove(d)),
              ),
          ],
        ),
      ],
      'fence' => [
        DropdownButtonFormField<Place>(
          initialValue: _fence,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.auFence),
          items: [
            for (final p in c.fences)
              DropdownMenuItem(value: p, child: Text(p.name)),
          ],
          onChanged: (p) => setState(() => _fence = p),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(l.auEnters)),
            ButtonSegment(value: false, label: Text(l.auLeaves)),
          ],
          selected: {_enter},
          onSelectionChanged: (v) => setState(() => _enter = v.single),
        ),
        const SizedBox(height: 12),
        _nodePicker(l, any: true),
      ],
      'message' => [
        TextField(
          controller: _text,
          decoration: InputDecoration(
            labelText: l.auContains,
            helperText: l.auContainsHelp,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _conv,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.auConversation),
          items: [
            DropdownMenuItem(value: null, child: Text(l.auAnyConversation)),
            for (final e in c.conversations.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value.$2)),
          ],
          onChanged: (v) => setState(() => _conv = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.auDirectOnly),
          value: _dm,
          onChanged: (v) => setState(() => _dm = v),
        ),
      ],
      _ => [
        _nodePicker(l),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(l.auComesOnline)),
            ButtonSegment(value: false, label: Text(l.auGoesOffline)),
          ],
          selected: {_online},
          onSelectionChanged: (v) => setState(() => _online = v.single),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _after,
          decoration: InputDecoration(labelText: l.auQuietFor),
          items: [
            for (final min in const [15, 30, 60, 120, 360])
              DropdownMenuItem(value: min, child: Text(l.auMinutes(min))),
          ],
          onChanged: (v) => setState(() => _after = v ?? 30),
        ),
      ],
    };
    final result = _result;
    return AlertDialog(
      title: Text(switch (widget.kind) {
        'battery' => l.auTBattery,
        'time' => l.auTTime,
        'fence' => l.auTFence,
        'message' => l.auTMessage,
        _ => l.auTPresence,
      }),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: body),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(
          onPressed: result == null
              ? null
              : () => Navigator.pop(context, _result),
          child: Text(l.auSave),
        ),
      ],
    );
  }

  /// The full name of weekday [d] (1 = Monday): 1 January 2024 was one.
  static String _weekdayName(BuildContext context, int d) => DateFormat.EEEE(
    Localizations.localeOf(context).toString(),
  ).format(DateTime(2024, 1, d));
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({required this.kind, required this.choices});

  final String kind;
  final AutomationChoices choices;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  static const _tokens = '{node}, {battery}, {place}, {time}, {text}, {rule}';

  final _text = TextEditingController();
  String? _conv;
  RadioId? _radio;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  AutoAction? get _result {
    final t = _text.text.trim();
    return switch (widget.kind) {
      'send' when _conv != null && t.isNotEmpty => SendAction(
        conversation: widget.choices.conversations[_conv]!.$1,
        text: t,
      ),
      'alert' when t.isNotEmpty => AlertAction(t),
      'channel' when _radio != null && t.isNotEmpty => JoinChannelAction(
        radio: _radio!,
        link: t,
      ),
      'webhook' when WebhookAction.validUrl(t) => WebhookAction(t),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.choices;
    final body = switch (widget.kind) {
      'send' => [
        DropdownButtonFormField<String>(
          initialValue: _conv,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.auConversation),
          items: [
            for (final e in c.conversations.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value.$2)),
          ],
          onChanged: (v) => setState(() => _conv = v),
        ),
        TextField(
          controller: _text,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            labelText: l.auText,
            helperText: l.auPlaceholders(_tokens),
            helperMaxLines: 3,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
      'alert' => [
        TextField(
          controller: _text,
          decoration: InputDecoration(
            labelText: l.auText,
            helperText: l.auPlaceholders(_tokens),
            helperMaxLines: 3,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
      'channel' => [
        Text(l.auChannelHelp),
        DropdownButtonFormField<RadioId>(
          initialValue: _radio,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.auRadio),
          items: [
            for (final r in c.radios)
              DropdownMenuItem(value: r.id, child: Text(r.name)),
          ],
          onChanged: (v) => setState(() => _radio = v),
        ),
        TextField(
          controller: _text,
          decoration: InputDecoration(labelText: l.auChannelLink),
          onChanged: (_) => setState(() {}),
        ),
      ],
      _ => [
        Row(
          children: [
            const Icon(Icons.public),
            const SizedBox(width: 8),
            Expanded(child: Text(l.auWebhookHelp)),
          ],
        ),
        TextField(
          controller: _text,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: l.auUrl, hintText: 'https://'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    };
    final result = _result;
    return AlertDialog(
      title: Text(switch (widget.kind) {
        'send' => l.auASend,
        'alert' => l.auAAlert,
        'channel' => l.auAChannel,
        _ => l.auAWebhook,
      }),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: body),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(
          onPressed: result == null
              ? null
              : () => Navigator.pop(context, _result),
          child: Text(l.auSave),
        ),
      ],
    );
  }
}
