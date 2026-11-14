import 'package:flutter/material.dart';

import '../app/hop_naming_service.dart';
import '../mesh/hop_naming.dart';
import 'common.dart';

/// How repeater IDs in MeshCore routes get names.
class HopNamingScreen extends StatefulWidget {
  const HopNamingScreen({super.key, required this.service});

  final HopNamingService service;

  @override
  State<HopNamingScreen> createState() => _HopNamingScreenState();
}

class _HopNamingScreenState extends State<HopNamingScreen> {
  late final _server = TextEditingController(text: widget.service.value.server);

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = widget.service;
    return Scaffold(
      appBar: AppBar(title: Text(l.hopNamesTitle)),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final v = s.value;
          final picks = v.pickCount(DateTime.now());
          final small = Theme.of(context).textTheme.bodySmall;
          Widget stepper(
            Key key,
            IconData icon,
            String title,
            String value,
            VoidCallback? less,
            VoidCallback? more,
          ) => ListTile(
            key: key,
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(value),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l.hopNamesLess,
                  onPressed: less,
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: l.hopNamesMore,
                  onPressed: more,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          );
          return ListView(
            children: [
              SwitchListTile(
                key: const ValueKey('hop-online'),
                title: Text(l.hopNamesOnline),
                subtitle: Text(l.hopNamesOnlineHelp),
                value: v.online,
                onChanged: s.setOnline,
              ),
              if (v.online)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const ValueKey('hop-server'),
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: l.hopNamesServer),
                    onSubmitted: s.setServer,
                  ),
                ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l.hopNamesMemoryHelp, style: small),
              ),
              stepper(
                const ValueKey('hop-days'),
                Icons.history,
                l.hopNamesKeep,
                l.hopNamesDays(v.tieDays),
                v.tieDays > 1 ? () => s.setTieDays(v.tieDays - 1) : null,
                v.tieDays < HopNaming.maxTieDays
                    ? () => s.setTieDays(v.tieDays + 1)
                    : null,
              ),
              stepper(
                const ValueKey('hop-margin'),
                Icons.balance,
                l.hopNamesMargin,
                '${v.tieMargin} %',
                v.tieMargin > 0 ? () => s.setTieMargin(v.tieMargin - 1) : null,
                v.tieMargin < HopNaming.maxTieMargin
                    ? () => s.setTieMargin(v.tieMargin + 1)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l.hopNamesMarginHelp, style: small),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  key: const ValueKey('hop-forget'),
                  onPressed: picks == 0 ? null : s.forgetPicks,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(l.hopNamesForget(picks)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
