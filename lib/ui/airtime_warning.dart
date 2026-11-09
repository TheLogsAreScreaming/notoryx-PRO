import 'package:flutter/material.dart';

import '../app/radio_connection.dart';
import 'common.dart';

/// Before a settings change goes over the mesh: if this radio has been
/// transmitting a lot lately, says so and asks. True to go ahead.
Future<bool> okToWriteOverMesh(
  BuildContext context,
  MeshtasticConnection connection,
) async {
  final used = connection.recentAirUtilTx;
  if (used == null || used < MeshtasticConnection.busyAirUtilTx) return true;
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.airtimeBusyTitle),
      content: Text(l.airtimeBusyBody(used.toStringAsFixed(1))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.radiosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.airtimeBusySend),
        ),
      ],
    ),
  );
  return ok ?? false;
}
