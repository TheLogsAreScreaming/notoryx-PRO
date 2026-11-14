import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../store/mesh_store.dart';

/// A reusable checklist, such as a pre-trip or deployment list.
@immutable
class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.name,
    required this.items,
  });

  final String id;
  final String name;

  /// The steps, in order.
  final List<String> items;

  ChecklistTemplate copyWith({String? name, List<String>? items}) =>
      ChecklistTemplate(
        id: id,
        name: name ?? this.name,
        items: items ?? this.items,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'items': items};

  static ChecklistTemplate? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final id = j['id'];
    final name = j['name'];
    final items = j['items'];
    if (id is! String || name is! String || items is! List) return null;
    return ChecklistTemplate(
      id: id,
      name: name,
      items: [
        for (final i in items)
          if (i is String) i,
      ],
    );
  }
}

/// One step in a run.
@immutable
class RunItem {
  const RunItem(this.text, {this.checkedAt});

  final String text;

  /// When it was ticked, or null.
  final DateTime? checkedAt;

  bool get done => checkedAt != null;

  Map<String, Object?> toJson() => {
    'text': text,
    'done': done,
    if (checkedAt != null) 'checkedAt': checkedAt!.toUtc().toIso8601String(),
  };

  static RunItem? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final text = j['text'];
    if (text is! String) return null;
    final at = j['checkedAt'];
    return RunItem(
      text,
      checkedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}

/// A checklist being worked through, or a finished one (a record).
@immutable
class ChecklistRun {
  const ChecklistRun({
    required this.id,
    required this.templateId,
    required this.name,
    required this.startedAt,
    required this.items,
    this.finishedAt,
    this.note = '',
  });

  /// Starts [t] at [now].
  factory ChecklistRun.start(ChecklistTemplate t, DateTime now) => ChecklistRun(
    id: 'r${now.microsecondsSinceEpoch}',
    templateId: t.id,
    name: t.name,
    startedAt: now,
    items: [for (final i in t.items) RunItem(i)],
  );

  final String id;
  final String templateId;

  /// The checklist's name when the run started.
  final String name;
  final DateTime startedAt;

  /// Null while the run is in progress.
  final DateTime? finishedAt;
  final List<RunItem> items;
  final String note;

  int get doneCount => items.where((i) => i.done).length;
  bool get complete => doneCount == items.length;

  /// Ticks or unticks item [index] at [now].
  ChecklistRun toggle(int index, DateTime now) => _copy(
    items: [
      for (final (i, item) in items.indexed)
        i == index
            ? RunItem(item.text, checkedAt: item.done ? null : now)
            : item,
    ],
  );

  ChecklistRun withNote(String note) => _copy(note: note);

  /// This run finished at [now], with its note trimmed.
  ChecklistRun finish(DateTime now) =>
      _copy(finishedAt: now, note: note.trim());

  ChecklistRun _copy({
    List<RunItem>? items,
    String? note,
    DateTime? finishedAt,
  }) => ChecklistRun(
    id: id,
    templateId: templateId,
    name: name,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    items: items ?? this.items,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'templateId': templateId,
    'name': name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    'items': [for (final i in items) i.toJson()],
    if (note.isNotEmpty) 'note': note,
  };

  static ChecklistRun? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final id = j['id'];
    final templateId = j['templateId'];
    final name = j['name'];
    final started = switch (j['startedAt']) {
      final String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    };
    final items = j['items'];
    if (id is! String ||
        templateId is! String ||
        name is! String ||
        started == null ||
        items is! List) {
      return null;
    }
    return ChecklistRun(
      id: id,
      templateId: templateId,
      name: name,
      startedAt: started,
      finishedAt: switch (j['finishedAt']) {
        final String s => DateTime.tryParse(s)?.toLocal(),
        _ => null,
      },
      items: [for (final i in items) ?RunItem.fromJson(i)],
      note: j['note'] is String ? j['note']! as String : '',
    );
  }
}

/// Checklists, the run in progress and finished records, kept as
/// preferences on this device. Everything works with no radio and no
/// network.
class ChecklistBook extends ChangeNotifier {
  ChecklistBook(this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Preference names.
  static const templatesPref = 'checklists.templates';
  static const activePref = 'checklists.active';
  static const recordsPref = 'checklists.records';

  /// Finished records kept, newest first.
  static const recordsKept = 500;

  final MeshStore store;
  final DateTime Function() _clock;

  List<ChecklistTemplate>? _templates;
  ChecklistRun? _active;
  List<ChecklistRun> _records = const [];
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Null until loaded, or when no checklist was ever saved (so the
  /// starter lists can be added in the user's language).
  List<ChecklistTemplate>? get templates => _templates;

  /// The run in progress, kept across restarts.
  ChecklistRun? get active => _active;

  /// Finished runs, newest first.
  List<ChecklistRun> get records => _records;

  Future<void> load() async {
    _templates = _decodeList(
      await store.preference(templatesPref),
      ChecklistTemplate.fromJson,
    );
    _active = switch (await store.preference(activePref)) {
      final String s when s.isNotEmpty => _decode(s, ChecklistRun.fromJson),
      _ => null,
    };
    final saved =
        _decodeList(
          await store.preference(recordsPref),
          ChecklistRun.fromJson,
        ) ??
        const <ChecklistRun>[];
    _records = List.unmodifiable(
      [
        for (final r in saved)
          if (r.finishedAt != null) r,
      ]..sort((a, b) => b.finishedAt!.compareTo(a.finishedAt!)),
    );
    _loaded = true;
    notifyListeners();
  }

  static T? _decode<T>(String s, T? Function(Object?) read) {
    try {
      return read(jsonDecode(s));
    } on FormatException {
      return null;
    }
  }

  static List<T>? _decodeList<T>(String? s, T? Function(Object?) read) {
    if (s == null) return null;
    final list = _decode<List<Object?>>(s, (j) => j is List ? j : null);
    if (list == null) return null;
    return [for (final j in list) ?read(j)];
  }

  /// A fresh ID for a new checklist.
  String newId() => 't${_clock().microsecondsSinceEpoch}';

  /// Adds the starter checklists when none were ever saved.
  Future<void> seed(List<ChecklistTemplate> starters) async {
    if (_templates != null) return;
    await _saveTemplates(starters);
  }

  /// Adds [t], or replaces the checklist with its ID.
  Future<void> saveTemplate(ChecklistTemplate t) async {
    final list = [...?_templates];
    final i = list.indexWhere((x) => x.id == t.id);
    if (i < 0) {
      list.add(t);
    } else {
      list[i] = t;
    }
    await _saveTemplates(list);
  }

  Future<void> deleteTemplate(String id) =>
      _saveTemplates([...?_templates]..removeWhere((t) => t.id == id));

  Future<void> _saveTemplates(List<ChecklistTemplate> list) async {
    _templates = List.unmodifiable(list);
    notifyListeners();
    await store.setPreference(
      templatesPref,
      jsonEncode([for (final t in list) t.toJson()]),
    );
  }

  /// Starts [t], replacing any run in progress.
  Future<ChecklistRun> start(ChecklistTemplate t) async {
    final run = ChecklistRun.start(t, _clock());
    await _setActive(run);
    return run;
  }

  /// Ticks or unticks an item of the active run.
  Future<void> toggle(int index) async {
    final run = _active;
    if (run == null) return;
    await _setActive(run.toggle(index, _clock()));
  }

  Future<void> setNote(String note) async {
    final run = _active;
    if (run == null || run.note == note) return;
    await _setActive(run.withNote(note));
  }

  /// Drops the run in progress without keeping a record.
  Future<void> discard() => _setActive(null);

  /// Finishes the active run and saves it as a timestamped record.
  Future<ChecklistRun?> finish() async {
    final run = _active;
    if (run == null) return null;
    final record = run.finish(_clock());
    final list = [record, ..._records];
    if (list.length > recordsKept) list.removeRange(recordsKept, list.length);
    _records = List.unmodifiable(list);
    await _saveRecords();
    await _setActive(null);
    return record;
  }

  Future<void> deleteRecord(String id) async {
    _records = List.unmodifiable([..._records]..removeWhere((r) => r.id == id));
    notifyListeners();
    await _saveRecords();
  }

  Future<void> _saveRecords() => store.setPreference(
    recordsPref,
    jsonEncode([for (final r in _records) r.toJson()]),
  );

  Future<void> _setActive(ChecklistRun? run) async {
    _active = run;
    notifyListeners();
    await store.setPreference(
      activePref,
      run == null ? '' : jsonEncode(run.toJson()),
    );
  }
}

/// Words used when writing a record as plain text.
class ChecklistTextLabels {
  const ChecklistTextLabels({
    required this.started,
    required this.finished,
    required this.note,
    required this.done,
  });

  /// Each takes the already formatted value.
  final String Function(String when) started;
  final String Function(String when) finished;
  final String Function(String note) note;

  /// "{done} of {total} done".
  final String Function(int done, int total) done;
}

/// [records] as plain text, one block per record, for reading or printing.
/// [when] formats a time.
String checklistRecordsText(
  List<ChecklistRun> records,
  ChecklistTextLabels labels,
  String Function(DateTime) when,
) {
  final out = StringBuffer();
  for (final (i, r) in records.indexed) {
    if (i > 0) out.writeln();
    out
      ..writeln(r.name)
      ..writeln(labels.started(when(r.startedAt)));
    if (r.finishedAt case final f?) out.writeln(labels.finished(when(f)));
    out.writeln(labels.done(r.doneCount, r.items.length));
    for (final item in r.items) {
      final at = item.checkedAt;
      out.writeln(
        item.done ? '[x] ${item.text} (${when(at!)})' : '[ ] ${item.text}',
      );
    }
    if (r.note.isNotEmpty) out.writeln(labels.note(r.note));
  }
  return out.toString();
}

/// [records] as JSON with a versioned header, times in UTC ISO 8601.
String checklistRecordsJson(
  List<ChecklistRun> records, {
  required DateTime exportedAt,
}) => const JsonEncoder.withIndent('  ').convert({
  'format': 'notoryx-pro-checklists',
  'formatVersion': 1,
  'exportedAt': exportedAt.toUtc().toIso8601String(),
  'records': [for (final r in records) r.toJson()],
});
