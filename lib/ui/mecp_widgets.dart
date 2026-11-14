import 'package:flutter/material.dart';

import '../mesh/mecp.dart';
import '../mesh/mecp_codes.dart';
import '../mesh/mecp_labels.dart';
import '../mesh/model.dart';
import 'common.dart';
import 'themes.dart';

/// Labels in the phone's own language, which may be one MECP covers even
/// when the rest of the app has fallen back to English.
MecpLabels _labels() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  return MecpLabels.forLocale(
    locale.languageCode,
    script: locale.scriptCode,
    country: locale.countryCode,
  );
}

String _severityName(BuildContext context, MecpSeverity s) {
  final l = context.l10n;
  final translated = _labels().severity(s);
  if (translated != null) return translated;
  return switch (s) {
    MecpSeverity.mayday => l.mecpMayday,
    MecpSeverity.urgent => l.mecpUrgent,
    MecpSeverity.safety => l.mecpSafety,
    MecpSeverity.routine => l.mecpRoutine,
  };
}

IconData _severityIcon(MecpSeverity s) => switch (s) {
  MecpSeverity.mayday => Icons.sos,
  MecpSeverity.urgent => Icons.priority_high,
  MecpSeverity.safety => Icons.warning_amber,
  MecpSeverity.routine => Icons.chat_outlined,
};

/// A received or sent MECP message, spelled out.
class MecpCard extends StatelessWidget {
  const MecpCard(this.message, {super.key, required this.raw});

  final MecpMessage message;

  /// The text as it came over the air.
  final String raw;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final m = message;
    final serious = m.severity.index < 2 && !m.isDrill;
    final color = serious ? meshColors(Theme.of(context)).sos : scheme.primary;
    final position = m.position;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_severityIcon(m.severity), size: 18, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                m.isDrill
                    ? l.mecpDrillOf(_severityName(context, m.severity))
                    : _severityName(context, m.severity),
                style: text.titleSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
        for (final c in m.codes)
          Text('• ${_labels().code(c) ?? l.mecpUnknownCode(c)}'),
        if (m.people != null) Text(l.mecpPeople(m.people!)),
        if (position != null)
          SelectableText(l.mecpPosition('${position.$1}, ${position.$2}')),
        if (m.time != null) Text(l.mecpTime(m.time!)),
        if (m.note.isNotEmpty) Text(m.note),
        const SizedBox(height: 2),
        Text(
          raw,
          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Lets someone build an MECP message; returns its text, or null if
/// cancelled. It doesn't send: the text goes in the message box first.
Future<String?> showMecpComposer(
  BuildContext context, {
  required int maxBytes,
  GeoPoint? position,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _MecpComposer(maxBytes: maxBytes, position: position),
);

class _MecpComposer extends StatefulWidget {
  const _MecpComposer({required this.maxBytes, this.position});

  final int maxBytes;
  final GeoPoint? position;

  @override
  State<_MecpComposer> createState() => _MecpComposerState();
}

class _MecpComposerState extends State<_MecpComposer> {
  final _note = TextEditingController();
  final _codes = <String>[];
  MecpSeverity? _severity;
  late bool _withPosition = widget.position != null;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  MecpMessage? get _message {
    final severity = _severity;
    if (severity == null) return null;
    final p = widget.position;
    final located = _withPosition && p != null;
    final codes = [..._codes, if (located && !_codes.contains('P05')) 'P05'];
    if (codes.isEmpty) return null;
    return MecpMessage(
      severity: severity,
      codes: codes,
      freetext: [
        if (located)
          '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
        if (_note.text.trim().isNotEmpty) _note.text.trim(),
      ].join(' '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final message = _message;
    final limit = widget.maxBytes < MecpMessage.maxBytes
        ? widget.maxBytes
        : MecpMessage.maxBytes;
    final used = message?.bytes ?? 0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.mecpTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in MecpSeverity.values)
                    ChoiceChip(
                      avatar: Icon(_severityIcon(s), size: 18),
                      label: Text(_severityName(context, s)),
                      selected: _severity == s,
                      onSelected: (_) => setState(() => _severity = s),
                    ),
                ],
              ),
              for (final cat in mecpCategories.entries)
                // Beacons are sent automatically by beacon devices.
                if (cat.key != 'B')
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(_labels().category(cat.key)),
                    children: [
                      for (final code in mecpCodes.entries)
                        if (code.key.startsWith(cat.key))
                          CheckboxListTile(
                            value: _codes.contains(code.key),
                            title: Text(_labels().code(code.key) ?? code.value),
                            onChanged: (on) => setState(() {
                              on == true
                                  ? _codes.add(code.key)
                                  : _codes.remove(code.key);
                            }),
                          ),
                    ],
                  ),
              if (widget.position != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.mecpIncludePosition),
                  value: _withPosition,
                  onChanged: (v) => setState(() => _withPosition = v),
                ),
              TextField(
                key: const Key('mecp-note'),
                controller: _note,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.mecpNote,
                  helperText: l.mecpNoteHelp,
                ),
              ),
              const SizedBox(height: 8),
              if (message != null) ...[
                Text(message.encode()),
                Text(
                  l.composerBytes(used, limit),
                  style: TextStyle(
                    color: used > limit
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: message == null || used > limit
                      ? null
                      : () => Navigator.pop(context, message.encode()),
                  child: Text(l.mecpUse),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
