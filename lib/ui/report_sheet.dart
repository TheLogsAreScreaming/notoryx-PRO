import 'package:flutter/material.dart';

import '../mesh/reports.dart';
import 'common.dart';

/// Asks which report to write, then returns its text for the message box.
/// Null if cancelled. Never sends anything.
Future<String?> showReportComposer(
  BuildContext context, {
  required int maxBytes,
  String? position,
}) async {
  final l = context.l10n;
  final kind = await showModalBottomSheet<ReportKind>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(l.reportSalute),
              subtitle: Text(l.reportSaluteAbout),
              onTap: () => Navigator.pop(context, ReportKind.salute),
            ),
            ListTile(
              leading: const Icon(Icons.medical_services_outlined),
              title: Text(l.reportNineLine),
              subtitle: Text(l.reportNineLineAbout),
              onTap: () => Navigator.pop(context, ReportKind.nineLine),
            ),
          ],
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        _ReportForm(kind: kind, maxBytes: maxBytes, position: position),
  );
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({
    required this.kind,
    required this.maxBytes,
    this.position,
  });

  final ReportKind kind;
  final int maxBytes;
  final String? position;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  late final _fields = [
    for (var i = 0; i < widget.kind.tags.length; i++)
      TextEditingController(
        text: i == widget.kind.locationField ? widget.position : null,
      ),
  ];

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  List<String> _labels(BuildContext context) {
    final l = context.l10n;
    return switch (widget.kind) {
      ReportKind.salute => [
        l.reportSize,
        l.reportActivity,
        l.reportLocation,
        l.reportUnit,
        l.reportTime,
        l.reportEquipment,
      ],
      ReportKind.nineLine => [
        l.report9Location,
        l.report9Radio,
        l.report9Precedence,
        l.report9Equipment,
        l.report9Patients,
        l.report9Security,
        l.report9Marking,
        l.report9Nationality,
        l.report9Terrain,
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = _labels(context);
    final values = [for (final f in _fields) f.text];
    final empty = values.every((v) => v.trim().isEmpty);
    final used = widget.kind.bytes(values);
    final tooLong = used > widget.maxBytes;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.kind == ReportKind.salute
                    ? l.reportSalute
                    : l.reportNineLine,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (var i = 0; i < _fields.length; i++)
                TextField(
                  key: Key('report-${widget.kind.tags[i]}'),
                  controller: _fields[i],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: labels[i]),
                ),
              const SizedBox(height: 8),
              Text(
                l.composerBytes(used, widget.maxBytes),
                style: TextStyle(
                  color: tooLong ? Theme.of(context).colorScheme.error : null,
                ),
              ),
              Text(l.reportHelp),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: empty || tooLong
                    ? null
                    : () => Navigator.pop(context, widget.kind.encode(values)),
                child: Text(l.reportUse),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
