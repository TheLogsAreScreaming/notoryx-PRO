import 'package:flutter/material.dart';

import '../mesh/model.dart';
import 'common.dart';

/// Asks for coordinates to fix a node at; returns null if cancelled.
Future<GeoPoint?> showFixedPositionDialog(
  BuildContext context, {
  GeoPoint? initial,
}) => showDialog<GeoPoint>(
  context: context,
  builder: (_) => _FixedPositionDialog(initial),
);

class _FixedPositionDialog extends StatefulWidget {
  const _FixedPositionDialog(this.initial);

  final GeoPoint? initial;

  @override
  State<_FixedPositionDialog> createState() => _FixedPositionDialogState();
}

class _FixedPositionDialogState extends State<_FixedPositionDialog> {
  final _form = GlobalKey<FormState>();
  late final _latitude = TextEditingController(
    text: widget.initial?.latitude.toString() ?? '',
  );
  late final _longitude = TextEditingController(
    text: widget.initial?.longitude.toString() ?? '',
  );
  late final _altitude = TextEditingController(
    text: widget.initial?.altitude?.toString() ?? '',
  );

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    _altitude.dispose();
    super.dispose();
  }

  String? _coordinate(String? text, double limit) {
    final v = double.tryParse(text?.trim() ?? '');
    return v == null || v.abs() > limit
        ? context.l10n.settingsPositionInvalid
        : null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final altitude = _altitude.text.trim();
    Navigator.pop(
      context,
      GeoPoint(
        double.parse(_latitude.text.trim()),
        double.parse(_longitude.text.trim()),
        altitude: altitude.isEmpty ? null : int.parse(altitude),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const numbers = TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    );
    return AlertDialog(
      title: Text(l.mtFixedSet),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.mtFixedHelp),
              TextFormField(
                key: const Key('fixed-latitude'),
                controller: _latitude,
                keyboardType: numbers,
                decoration: InputDecoration(labelText: l.settingsLatitude),
                validator: (t) => _coordinate(t, 90),
              ),
              TextFormField(
                key: const Key('fixed-longitude'),
                controller: _longitude,
                keyboardType: numbers,
                decoration: InputDecoration(labelText: l.settingsLongitude),
                validator: (t) => _coordinate(t, 180),
              ),
              TextFormField(
                key: const Key('fixed-altitude'),
                controller: _altitude,
                keyboardType: numbers,
                decoration: InputDecoration(labelText: l.mtFixedAltitude),
                validator: (t) {
                  final text = t?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final v = int.tryParse(text);
                  return v == null || v < -500 || v > 9000
                      ? l.settingsPositionInvalid
                      : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.settingsSave)),
      ],
    );
  }
}
