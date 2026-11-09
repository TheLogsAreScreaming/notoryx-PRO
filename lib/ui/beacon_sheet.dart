import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/distress_beacon.dart';
import '../app/radio_connection.dart';
import '../mesh/model.dart';
import 'common.dart';

/// Sets up a distress beacon and, after a second confirmation, starts it.
Future<void> showBeaconSheet(
  BuildContext context, {
  required AppController app,
  required RadioConnection connection,
  required Conversation conversation,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _BeaconSheet(
    app: app,
    connection: connection,
    conversation: conversation,
  ),
);

class _BeaconSheet extends StatefulWidget {
  const _BeaconSheet({
    required this.app,
    required this.connection,
    required this.conversation,
  });

  final AppController app;
  final RadioConnection connection;
  final Conversation conversation;

  @override
  State<_BeaconSheet> createState() => _BeaconSheetState();
}

class _BeaconSheetState extends State<_BeaconSheet> {
  final _note = TextEditingController();
  int _every = 5;
  int _lasts = 60;
  bool _drill = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_drill ? l.beaconConfirmDrill : l.beaconConfirmReal),
        content: Text(l.beaconConfirmBody(_every, _lasts)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            key: const Key('beacon-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.beaconStart),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.app.startBeacon(
      widget.connection,
      widget.conversation,
      every: Duration(minutes: _every),
      lasts: Duration(minutes: _lasts),
      note: _note.text,
      drill: _drill,
      noticeTitle: _drill ? l.beaconNoticeDrill : l.beaconNoticeReal,
      noticeBody: l.beaconNoticeBody(_every),
      noticeStop: l.beaconStop,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    Widget choice(
      String title,
      List<int> options,
      int value,
      void Function(int) set,
    ) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(l.beaconMinutes(o)),
                  selected: value == o,
                  onSelected: (_) => setState(() => set(o)),
                ),
            ],
          ),
        ],
      ),
    );
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
              Text(l.beaconTitle, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(l.beaconHelp),
              choice(
                l.beaconEvery,
                const [5, 10, 15],
                _every,
                (v) => _every = v,
              ),
              choice(
                l.beaconLasts,
                const [30, 60, 120, 240],
                _lasts,
                (v) => _lasts = v,
              ),
              TextField(
                controller: _note,
                maxLength: 60,
                decoration: InputDecoration(labelText: l.beaconNote),
              ),
              SwitchListTile(
                key: const Key('beacon-drill'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.beaconDrill),
                subtitle: Text(l.beaconDrillHelp),
                value: _drill,
                onChanged: (v) => setState(() => _drill = v),
              ),
              FilledButton.icon(
                key: const Key('beacon-start'),
                icon: const Icon(Icons.sos),
                label: Text(l.beaconStart),
                onPressed: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a running beacon and stops it with one tap.
class BeaconBanner extends StatelessWidget {
  const BeaconBanner({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DistressBeacon?>(
    valueListenable: app.beacon,
    builder: (context, beacon, _) {
      if (beacon == null) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: beacon,
        builder: (context, _) {
          final l = context.l10n;
          final s = Theme.of(context).colorScheme;
          return Material(
            color: s.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (beacon.drill)
                          l.beaconNoticeDrill
                        else
                          l.beaconNoticeReal,
                        l.beaconCount(beacon.sent, beacon.failed),
                        if (beacon.acknowledged) l.beaconAcknowledged,
                      ].join(' · '),
                      style: TextStyle(color: s.onErrorContainer),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          key: const Key('beacon-ok'),
                          style: TextButton.styleFrom(
                            foregroundColor: s.onErrorContainer,
                          ),
                          onPressed: () => beacon.stop(imOk: true),
                          child: Text(l.beaconStopOk),
                        ),
                        FilledButton(
                          key: const Key('beacon-stop'),
                          onPressed: beacon.stop,
                          child: Text(l.beaconStop),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
