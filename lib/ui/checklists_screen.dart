import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/checklists.dart';
import '../l10n/app_localizations.dart';
import 'common.dart';

/// The starter checklists, in the user's language.
List<ChecklistTemplate> starterChecklists(AppLocalizations l) => [
  ChecklistTemplate(
    id: 'starter-pre-trip',
    name: l.ckPreTrip,
    items: [
      l.ckPreTrip1,
      l.ckPreTrip2,
      l.ckPreTrip3,
      l.ckPreTrip4,
      l.ckPreTrip5,
      l.ckPreTrip6,
    ],
  ),
  ChecklistTemplate(
    id: 'starter-deployment',
    name: l.ckDeployment,
    items: [
      l.ckDeploy1,
      l.ckDeploy2,
      l.ckDeploy3,
      l.ckDeploy4,
      l.ckDeploy5,
      l.ckDeploy6,
    ],
  ),
];

String _when(BuildContext context, DateTime t) {
  final m = MaterialLocalizations.of(context);
  return '${m.formatMediumDate(t)} '
      '${m.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
}

/// Your checklists, the one in progress and the saved records.
class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key, required this.book});

  final ChecklistBook book;

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs the user's language for the starter lists.
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final starters = starterChecklists(context.l10n);
    await widget.book.load();
    await widget.book.seed(starters);
  }

  Future<void> _start(ChecklistTemplate t) async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    if (widget.book.active != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.ckReplaceActive),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.radiosCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.ckStart),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.book.start(t);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ChecklistRunScreen(book: widget.book),
      ),
    );
  }

  Future<void> _edit(ChecklistTemplate? t) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChecklistEditScreen(book: widget.book, template: t),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final book = widget.book;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.ckTitle),
        actions: [
          ListenableBuilder(
            listenable: book,
            builder: (context, _) => IconButton(
              tooltip: l.ckExportAll,
              icon: const Icon(Icons.ios_share),
              onPressed: book.records.isEmpty
                  ? null
                  : () => showChecklistExport(context, book.records),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text(l.ckNew),
      ),
      body: ListenableBuilder(
        listenable: book,
        builder: (context, _) {
          if (!book.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final templates = book.templates ?? const [];
          final active = book.active;
          Widget header(String text) => Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(text, style: Theme.of(context).textTheme.titleSmall),
            ),
          );
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  l.ckIntro,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (active != null) ...[
                header(l.ckInProgress),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text(active.name),
                    subtitle: Text(
                      l.ckProgress(active.doneCount, active.items.length),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChecklistRunScreen(book: book),
                      ),
                    ),
                  ),
                ),
              ],
              header(l.ckChecklists),
              if (templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(l.ckNoChecklists),
                ),
              for (final t in templates)
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(t.name),
                  subtitle: Text(l.ckItemCount(t.items.length)),
                  onTap: () => _edit(t),
                  trailing: TextButton(
                    onPressed: t.items.isEmpty ? null : () => _start(t),
                    child: Text(l.ckStart),
                  ),
                ),
              header(l.ckRecords),
              if (book.records.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(l.ckNoRecords),
                ),
              for (final r in book.records)
                ListTile(
                  leading: Icon(r.complete ? Icons.task_alt : Icons.rule),
                  title: Text(r.name),
                  subtitle: Text(
                    '${_when(context, r.finishedAt!)} · '
                    '${l.ckProgress(r.doneCount, r.items.length)}',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ChecklistRecordScreen(book: book, record: r),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Working through the checklist in progress.
class ChecklistRunScreen extends StatefulWidget {
  const ChecklistRunScreen({super.key, required this.book});

  final ChecklistBook book;

  @override
  State<ChecklistRunScreen> createState() => _ChecklistRunScreenState();
}

class _ChecklistRunScreenState extends State<ChecklistRunScreen> {
  late final _note = TextEditingController(text: widget.book.active?.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final run = widget.book.active;
    if (run == null) return;
    await widget.book.setNote(_note.text);
    if (!run.complete) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.ckFinishIncomplete(run.items.length - run.doneCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.radiosCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.ckFinish),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.book.finish();
    messenger.showSnackBar(SnackBar(content: Text(l.ckSaved)));
    navigator.pop();
  }

  Future<void> _discard() async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.ckDiscardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.ckDiscard),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.book.discard();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: widget.book,
      builder: (context, _) {
        final run = widget.book.active;
        if (run == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l.ckTitle)),
            body: EmptyState(l.ckNothingActive, icon: Icons.checklist),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(run.name),
            actions: [
              IconButton(
                tooltip: l.ckDiscard,
                icon: const Icon(Icons.delete_outline),
                onPressed: _discard,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l.ckProgress(run.doneCount, run.items.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: run.items.isEmpty
                      ? 0
                      : run.doneCount / run.items.length,
                  semanticsLabel: l.ckProgress(run.doneCount, run.items.length),
                ),
              ),
              for (final (i, item) in run.items.indexed)
                CheckboxListTile(
                  value: item.done,
                  onChanged: (_) => widget.book.toggle(i),
                  title: Text(item.text),
                  subtitle: item.checkedAt == null
                      ? null
                      : Text(l.ckCheckedAt(_when(context, item.checkedAt!))),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('checklist-note'),
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: widget.book.setNote,
                  decoration: InputDecoration(
                    labelText: l.ckNote,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: FilledButton.icon(
                  key: const Key('checklist-finish'),
                  onPressed: _finish,
                  icon: const Icon(Icons.task_alt),
                  label: Text(l.ckFinish),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Creating or changing a checklist.
class ChecklistEditScreen extends StatefulWidget {
  const ChecklistEditScreen({super.key, required this.book, this.template});

  final ChecklistBook book;

  /// Null for a new checklist.
  final ChecklistTemplate? template;

  @override
  State<ChecklistEditScreen> createState() => _ChecklistEditScreenState();
}

class _ChecklistEditScreenState extends State<ChecklistEditScreen> {
  late final _name = TextEditingController(text: widget.template?.name);
  late final _items = TextEditingController(
    text: widget.template?.items.join('\n'),
  );
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _items.dispose();
    super.dispose();
  }

  List<String> get _lines => [
    for (final s in _items.text.split('\n'))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final t = widget.template;
    await widget.book.saveTemplate(
      t == null
          ? ChecklistTemplate(
              id: widget.book.newId(),
              name: _name.text.trim(),
              items: _lines,
            )
          : t.copyWith(name: _name.text.trim(), items: _lines),
    );
    navigator.pop();
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.ckDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.ckDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.book.deleteTemplate(widget.template!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template == null ? l.ckNew : l.ckEdit),
        actions: [
          if (widget.template != null)
            IconButton(
              tooltip: l.ckDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('checklist-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l.ckName),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l.ckNameNeeded : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('checklist-items'),
              controller: _items,
              minLines: 6,
              maxLines: 20,
              decoration: InputDecoration(
                labelText: l.ckItems,
                helperText: l.ckItemsHelp,
                border: const OutlineInputBorder(),
              ),
              validator: (_) => _lines.isEmpty ? l.ckItemsNeeded : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('checklist-save'),
              onPressed: _save,
              child: Text(l.ckSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// One finished run.
class ChecklistRecordScreen extends StatelessWidget {
  const ChecklistRecordScreen({
    super.key,
    required this.book,
    required this.record,
  });

  final ChecklistBook book;
  final ChecklistRun record;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = record;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          IconButton(
            tooltip: l.ckExport,
            icon: const Icon(Icons.ios_share),
            onPressed: () => showChecklistExport(context, [r]),
          ),
          IconButton(
            tooltip: l.ckDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  content: Text(l.ckDeleteRecordConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l.radiosCancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(l.ckDelete),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              await book.deleteRecord(r.id);
              navigator.pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l.ckStarted(_when(context, r.startedAt))),
            subtitle: Text(l.ckFinished(_when(context, r.finishedAt!))),
          ),
          ListTile(
            leading: Icon(r.complete ? Icons.task_alt : Icons.rule),
            title: Text(l.ckProgress(r.doneCount, r.items.length)),
          ),
          const Divider(),
          for (final item in r.items)
            ListTile(
              leading: Icon(
                item.done ? Icons.check_box : Icons.check_box_outline_blank,
                semanticLabel: item.done ? l.ckDone : l.ckNotDone,
              ),
              title: Text(item.text),
              subtitle: item.checkedAt == null
                  ? null
                  : Text(l.ckCheckedAt(_when(context, item.checkedAt!))),
            ),
          if (r.note.isNotEmpty) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(l.ckNote),
              subtitle: Text(r.note),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks text or JSON, then shares [records] as a file.
Future<void> showChecklistExport(
  BuildContext context,
  List<ChecklistRun> records,
) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final asJson = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l.ckExportText),
            subtitle: Text(l.ckExportTextHelp),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: Text(l.ckExportJson),
            subtitle: Text(l.ckExportJsonHelp),
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ),
  );
  if (asJson == null || !context.mounted) return;
  final now = DateTime.now();
  final content = asJson
      ? checklistRecordsJson(records, exportedAt: now)
      : checklistRecordsText(
          records,
          ChecklistTextLabels(
            started: l.ckStarted,
            finished: l.ckFinished,
            note: l.ckNoteLine,
            done: l.ckProgress,
          ),
          (t) => _when(context, t),
        );
  try {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/checklists');
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final stamp = now.toIso8601String().substring(0, 10);
    final file = File(
      '${dir.path}/notoryx-pro-checklists-$stamp.${asJson ? 'json' : 'txt'}',
    );
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.ckExportFailed('$e'))));
  }
}
