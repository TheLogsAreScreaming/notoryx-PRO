import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/model.dart';
import '../mesh/node_journal.dart';
import 'common.dart';

/// The name of a journal label.
String journalLabelName(BuildContext context, JournalLabel label) {
  final l = context.l10n;
  return switch (label) {
    JournalLabel.alwaysOnRelay => l.njLabelAlwaysOnRelay,
    JournalLabel.roamer => l.njLabelRoamer,
    JournalLabel.fixedSite => l.njLabelFixedSite,
    JournalLabel.regular => l.njLabelRegular,
    JournalLabel.rarelyHeard => l.njLabelRarelyHeard,
    JournalLabel.newArrival => l.njLabelNewArrival,
    JournalLabel.nearby => l.njLabelNearby,
  };
}

IconData journalLabelIcon(JournalLabel label) => switch (label) {
  JournalLabel.alwaysOnRelay => Icons.cell_tower,
  JournalLabel.roamer => Icons.directions_walk,
  JournalLabel.fixedSite => Icons.place_outlined,
  JournalLabel.regular => Icons.event_repeat,
  JournalLabel.rarelyHeard => Icons.hourglass_empty,
  JournalLabel.newArrival => Icons.fiber_new_outlined,
  JournalLabel.nearby => Icons.near_me_outlined,
};

/// One line of evidence, in words.
String evidenceText(BuildContext context, JournalEvidence e) {
  final l = context.l10n;
  return switch (e.kind) {
    EvidenceKind.hoursCovered => l.njEvHours(e.value.toInt()),
    EvidenceKind.daysHeard => l.njEvDays(e.value.toInt(), e.of.toInt()),
    EvidenceKind.relayRole => l.njEvRelay,
    EvidenceKind.areaKm => l.njEvArea(e.value.toStringAsFixed(1)),
    EvidenceKind.samePlace => l.njEvSamePlace(e.value.toInt()),
    EvidenceKind.directShare => l.njEvDirect(e.value.toInt(), e.of.toInt()),
    EvidenceKind.firstHeardHours => l.njEvFirst(e.value.toInt()),
  };
}

/// A node's generated mark. Decorative unless [label] is given.
class NodeMarkView extends StatelessWidget {
  const NodeMarkView(this.nodeKey, {super.key, this.size = 40, this.label});

  final NodeKey nodeKey;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final mark = NodeMark.of(nodeKey);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = HSLColor.fromAHSL(
      1,
      mark.hue.toDouble(),
      0.65,
      dark ? 0.65 : 0.38,
    ).toColor();
    final bg = HSLColor.fromAHSL(
      1,
      mark.hue.toDouble(),
      0.35,
      dark ? 0.16 : 0.92,
    ).toColor();
    final paint = CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(mark, fg, bg),
    );
    final l = label;
    return l == null
        ? ExcludeSemantics(child: paint)
        : Semantics(
            image: true,
            label: l,
            child: ExcludeSemantics(child: paint),
          );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark, this.fg, this.bg);

  final NodeMark mark;
  final Color fg;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width / 6),
    );
    canvas.drawRRect(r, Paint()..color = bg);
    final pad = size.width / 8;
    final cell = (size.width - 2 * pad) / 5;
    final on = Paint()..color = fg;
    for (var i = 0; i < 25; i++) {
      if (!mark.cells[i]) continue;
      canvas.drawRect(
        Rect.fromLTWH(pad + (i % 5) * cell, pad + (i ~/ 5) * cell, cell, cell),
        on,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.fg != fg || old.bg != bg;
}

/// Every node ever heard on either mesh, with what each seems to be.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.app, this.clock});

  final AppController app;

  /// For tests.
  final DateTime Function()? clock;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late final Stream<List<JournalEntry>> _entries = widget.app.store
      .watchJournal();
  Map<NodeKey, List<JournalDay>> _days = const {};
  final _search = TextEditingController();
  JournalLabel? _label;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadDays() async {
    final days = await widget.app.store.journalDays(
      _now.subtract(const Duration(days: journalWindowDays)),
    );
    if (mounted) setState(() => _days = days);
  }

  bool _matches(JournalEntry e, String q) {
    if (q.isEmpty) return true;
    return e.name.toLowerCase().contains(q) ||
        e.key.native.contains(q) ||
        e.note.toLowerCase().contains(q) ||
        e.tags.any((t) => t.contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.njTitle)),
      body: StreamBuilder<List<JournalEntry>>(
        stream: _entries,
        builder: (context, snap) {
          final all = snap.data ?? const <JournalEntry>[];
          final now = _now;
          final q = _search.text.trim().toLowerCase();
          final rows = [
            for (final e in all)
              if (_matches(e, q))
                (e, describeNode(e, _days[e.key] ?? const [], now: now)),
          ];
          final shown = _label == null
              ? rows
              : [
                  for (final r in rows)
                    if (r.$2.any((g) => g.label == _label)) r,
                ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  key: const Key('journal-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: l.njSearch,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(l.njAll),
                        selected: _label == null,
                        onSelected: (_) => setState(() => _label = null),
                      ),
                    ),
                    for (final label in JournalLabel.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          avatar: Icon(journalLabelIcon(label), size: 18),
                          label: Text(journalLabelName(context, label)),
                          selected: _label == label,
                          onSelected: (on) =>
                              setState(() => _label = on ? label : null),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        all.isEmpty ? l.njEmpty : l.njNoMatch,
                        icon: Icons.menu_book_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDays,
                        child: ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (context, i) {
                            final (e, guesses) = shown[i];
                            final top = guesses.firstOrNull;
                            return ListTile(
                              leading: NodeMarkView(e.key),
                              title: Text(e.displayName),
                              subtitle: Text(
                                [
                                  protocolName(context, e.key.protocol),
                                  if (top != null)
                                    '${journalLabelName(context, top.label)} '
                                        '(${l.njConfidence(top.percent)})',
                                  if (e.tags.isNotEmpty)
                                    l.njTagged(e.tags.join(', ')),
                                  l.njLastHeard(
                                    ago(context, e.lastHeard, now: now),
                                  ),
                                ].join(' · '),
                              ),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => JournalNodeScreen(
                                      app: widget.app,
                                      nodeKey: e.key,
                                      clock: widget.clock,
                                    ),
                                  ),
                                );
                                await _loadDays();
                              },
                            );
                          },
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

/// One node's journal page: its mark, labels with evidence, history, tags
/// and note.
class JournalNodeScreen extends StatefulWidget {
  const JournalNodeScreen({
    super.key,
    required this.app,
    required this.nodeKey,
    this.clock,
  });

  final AppController app;
  final NodeKey nodeKey;
  final DateTime Function()? clock;

  @override
  State<JournalNodeScreen> createState() => _JournalNodeScreenState();
}

class _JournalNodeScreenState extends State<JournalNodeScreen> {
  JournalEntry? _entry;
  List<JournalDay> _days = const [];
  bool _loaded = false;
  final _note = TextEditingController();

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load(fillNote: true);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load({bool fillNote = false}) async {
    final store = widget.app.store;
    final entry = await store.journalEntry(widget.nodeKey);
    final days = await store.journalDays(
      _now.subtract(const Duration(days: journalWindowDays)),
      only: widget.nodeKey,
    );
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _days = days[widget.nodeKey] ?? const [];
      _loaded = true;
      if (fillNote) _note.text = entry?.note ?? '';
    });
  }

  Future<void> _addTag() async {
    final l = context.l10n;
    final entry = _entry;
    if (entry == null) return;
    final tag = await showTextPrompt(
      context,
      title: l.njAddTag,
      confirm: l.njAddTag,
      hint: l.njTagHint,
      fieldKey: const Key('journal-tag-field'),
    );
    if (tag == null || tag.trim().isEmpty) return;
    await widget.app.store.setJournalTags(entry.key, [...entry.tags, tag]);
    await _load();
  }

  Future<void> _removeTag(String tag) async {
    final entry = _entry;
    if (entry == null) return;
    await widget.app.store.setJournalTags(entry.key, [
      for (final t in entry.tags)
        if (t != tag) t,
    ]);
    await _load();
  }

  Future<void> _saveNote() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.l10n.njNoteSaved;
    await widget.app.store.setJournalNote(widget.nodeKey, _note.text);
    await _load();
    messenger.showSnackBar(SnackBar(content: Text(saved)));
  }

  Future<void> _forget() async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.njForgetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.njForget),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.app.store.forgetJournalNode(widget.nodeKey);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entry = _entry;
    final theme = Theme.of(context);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.njTitle)),
        body: _loaded
            ? EmptyState(l.njGone, icon: Icons.menu_book_outlined)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final now = _now;
    final guesses = describeNode(entry, _days, now: now);
    final dates = MaterialLocalizations.of(context);
    String when(DateTime t) =>
        '${dates.formatMediumDate(t.toLocal())} '
        '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()))}';
    Widget header(String text) => Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.displayName),
        actions: [
          IconButton(
            tooltip: l.njForget,
            icon: const Icon(Icons.delete_outline),
            onPressed: _forget,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                NodeMarkView(
                  entry.key,
                  size: 72,
                  label: l.njMarkLabel(entry.key.short),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(l.njNodeId(entry.key.native)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ProtocolBadge(entry.key.protocol),
                          Text(nodeKindName(context, entry.kind)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          header(l.njSeemsHeader),
          if (guesses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l.njNoLabels),
            ),
          for (final g in guesses)
            ListTile(
              leading: Icon(journalLabelIcon(g.label)),
              title: Text(
                '${journalLabelName(context, g.label)} · '
                '${l.njConfidence(g.percent)}',
              ),
              subtitle: Text(
                g.evidence.map((e) => evidenceText(context, e)).join('\n'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(l.njAbout, style: theme.textTheme.bodySmall),
          ),
          header(l.njHistoryHeader),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l.njFirstHeard(when(entry.firstHeard))),
            subtitle: Text(l.njLastHeard(when(entry.lastHeard))),
          ),
          ListTile(
            leading: const Icon(Icons.hearing),
            title: Text(l.njHeardCount(entry.heardCount)),
          ),
          header(l.njTagsHeader),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in entry.tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: () => _removeTag(t),
                    deleteButtonTooltipMessage: l.njRemoveTag(t),
                  ),
                ActionChip(
                  key: const Key('journal-add-tag'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(l.njAddTag),
                  onPressed: _addTag,
                ),
              ],
            ),
          ),
          header(l.njNoteHeader),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('journal-note'),
              controller: _note,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l.njNoteHeader,
                hintText: l.njNoteHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: _saveNote,
                child: Text(l.njSaveNote),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
