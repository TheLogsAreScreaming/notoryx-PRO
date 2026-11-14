import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/meshcore_settings.dart';
import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../meshcore/frames.dart';
import 'common.dart';
import 'identity_key_screen.dart';
import 'preset_sheet.dart';

/// A MeshCore companion's own settings.
class MeshCoreSettingsScreen extends StatefulWidget {
  const MeshCoreSettingsScreen({super.key, required this.connection});

  final MeshCoreConnection connection;

  @override
  State<MeshCoreSettingsScreen> createState() => _MeshCoreSettingsScreenState();
}

class _MeshCoreSettingsScreenState extends State<MeshCoreSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late MeshCoreSettings _current = widget.connection.settings!;
  late final _name = TextEditingController(text: _current.name);
  late final _freq = TextEditingController(text: '${_current.frequencyMHz}');
  late final _lat = TextEditingController(text: '${_current.latitude}');
  late final _lon = TextEditingController(text: '${_current.longitude}');
  late int _power = _current.txPower;
  late double _bw = _nearestBandwidth(_current.bandwidthKHz);
  late int _sf = _current.spreadingFactor;
  late int _cr = _current.codingRate;
  late bool _share = _current.shareLocationInAdverts;
  late bool _autoAdd = !_current.manualAddContacts;
  late int? _pathHash = widget.connection.pathHashBytes;
  bool _saving = false;

  static double _nearestBandwidth(double v) => MeshCoreSettings.bandwidths
      .reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  @override
  void dispose() {
    for (final c in [_name, _freq, _lat, _lon]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final l = context.l10n;
    setState(() => _saving = true);
    try {
      final saved = await widget.connection.applySettings(
        _current.copyWith(
          name: _name.text.trim(),
          txPower: _power,
          frequencyMHz: double.parse(_freq.text.trim()),
          bandwidthKHz: _bw,
          spreadingFactor: _sf,
          codingRate: _cr,
          latitude: double.parse(_lat.text.trim()),
          longitude: double.parse(_lon.text.trim()),
          shareLocationInAdverts: _share,
          manualAddContacts: !_autoAdd,
        ),
        pathHashBytes: _pathHash,
      );
      if (!mounted) return;
      setState(() => _current = saved);
      _say(l.settingsSaved);
    } on Object catch (e) {
      if (mounted) _say(l.settingsSaveFailed(RadioConnection.describeError(e)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reboot() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.settingsRebootConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.settingsReboot),
          ),
        ],
      ),
    );
    if (ok == true) await widget.connection.reboot();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.connection;
    final heading = Theme.of(context).textTheme.titleMedium;
    String? number(String? v, double lo, double hi, String error) {
      final n = double.tryParse((v ?? '').trim());
      return n == null || n < lo || n > hi ? error : null;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle(_current.name))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('settings-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l.settingsName),
              validator: (v) {
                final n = utf8.encode((v ?? '').trim()).length;
                return n < 1 || n > 31 ? l.settingsNameInvalid : null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              '${l.settingsTxPower}: ${l.settingsTxPowerValue(_power)}',
              style: heading,
            ),
            Slider(
              value: _power.toDouble(),
              min: -9,
              max: _current.maxTxPower.toDouble().clamp(-8, 40),
              divisions: (_current.maxTxPower + 9).clamp(1, 49),
              label: l.settingsTxPowerValue(_power),
              onChanged: (v) => setState(() => _power = v.round()),
            ),
            const SizedBox(height: 16),
            Text(l.settingsRadio, style: heading),
            Text(
              l.settingsRadioWarning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('settings-presets'),
                icon: const Icon(Icons.public),
                label: Text(l.presetsButton),
                onPressed: () async {
                  final p = await showMeshCorePresets(
                    context,
                    latitude: double.tryParse(_lat.text.trim()),
                    longitude: double.tryParse(_lon.text.trim()),
                  );
                  if (p == null || !mounted) return;
                  setState(() {
                    _freq.text = p.frequencyMHz.toStringAsFixed(3);
                    _bw = _nearestBandwidth(p.bandwidthKHz);
                    _sf = p.spreadingFactor;
                    _cr = p.codingRate;
                    if (_pathHash != null) {
                      _pathHash = p.pathHashBytes ?? _pathHash;
                    }
                  });
                  _say(l.presetApplied(p.name));
                },
              ),
            ),
            TextFormField(
              key: const Key('settings-frequency'),
              controller: _freq,
              decoration: InputDecoration(labelText: l.settingsFrequency),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  number(v, 150, 2500, l.settingsFrequencyInvalid),
            ),
            DropdownButtonFormField<double>(
              key: ValueKey('_bw-$_bw'),
              initialValue: _bw,
              decoration: InputDecoration(labelText: l.settingsBandwidth),
              items: [
                for (final b in MeshCoreSettings.bandwidths)
                  DropdownMenuItem(value: b, child: Text('$b')),
              ],
              onChanged: (v) => setState(() => _bw = v ?? _bw),
            ),
            DropdownButtonFormField<int>(
              key: ValueKey('_sf-$_sf'),
              initialValue: _sf,
              decoration: InputDecoration(labelText: l.settingsSpreading),
              items: [
                for (var s = 5; s <= 12; s++)
                  DropdownMenuItem(value: s, child: Text('SF$s')),
              ],
              onChanged: (v) => setState(() => _sf = v ?? _sf),
            ),
            DropdownButtonFormField<int>(
              key: ValueKey('_cr-$_cr'),
              initialValue: _cr,
              decoration: InputDecoration(labelText: l.settingsCoding),
              items: [
                for (var r = 5; r <= 8; r++)
                  DropdownMenuItem(
                    value: r,
                    child: Text(l.settingsCodingValue(r)),
                  ),
              ],
              onChanged: (v) => setState(() => _cr = v ?? _cr),
            ),
            const SizedBox(height: 16),
            Text(l.settingsPosition, style: heading),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('settings-lat'),
                    controller: _lat,
                    decoration: InputDecoration(labelText: l.settingsLatitude),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (v) =>
                        number(v, -90, 90, l.settingsPositionInvalid),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('settings-lon'),
                    controller: _lon,
                    decoration: InputDecoration(labelText: l.settingsLongitude),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (v) =>
                        number(v, -180, 180, l.settingsPositionInvalid),
                  ),
                ),
              ],
            ),
            if (_pathHash != null)
              DropdownButtonFormField<int>(
                key: ValueKey('settings-path-hash-$_pathHash'),
                initialValue: _pathHash,
                decoration: InputDecoration(
                  labelText: l.settingsPathHash,
                  helperText: l.settingsPathHashHelp,
                  helperMaxLines: 4,
                ),
                items: [
                  for (final n in const [1, 2, 3])
                    DropdownMenuItem(
                      value: n,
                      child: Text(l.settingsPathHashValue(n)),
                    ),
                ],
                onChanged: (v) => setState(() => _pathHash = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.settingsShareLocation),
              value: _share,
              onChanged: (v) => setState(() => _share = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.settingsAutoAdd),
              value: _autoAdd,
              onChanged: (v) => setState(() => _autoAdd = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(l.settingsSave),
              onPressed: _saving ? null : _save,
            ),
            const Divider(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await c.sendAdvert();
                    if (mounted) _say(l.settingsAdvertSent);
                  },
                  child: Text(l.settingsAdvertNeighbours),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await c.sendAdvert(flood: true);
                    if (mounted) _say(l.settingsAdvertSent);
                  },
                  child: Text(l.settingsAdvertEveryone),
                ),
                if (c.hasCompanionCli)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.terminal),
                    label: Text(l.settingsCli),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ConsoleScreen(title: l.settingsCli, run: c.runCli),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('identity-key'),
                  icon: const Icon(Icons.key),
                  label: Text(l.identityKeyTitle),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => IdentityKeyScreen(
                        export: c.exportPrivateKey,
                        import: c.importPrivateKey,
                      ),
                    ),
                  ),
                ),
                TextButton(onPressed: _reboot, child: Text(l.settingsReboot)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple command line: type, run, see replies.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key, required this.title, required this.run});

  final String title;
  final Future<String> Function(String command) run;

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final _input = TextEditingController();
  final _lines = <(String, String, bool)>[]; // command, reply, failed
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _busy) return;
    final l = context.l10n;
    setState(() => _busy = true);
    _input.clear();
    try {
      final reply = await widget.run(cmd);
      if (mounted) setState(() => _lines.add((cmd, reply, false)));
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _lines.add((
            cmd,
            l.consoleFailed(RadioConnection.describeError(e)),
            true,
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mono = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: _lines.isEmpty
                ? EmptyState(l.consoleEmpty, icon: Icons.terminal)
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final (cmd, reply, failed) in _lines) ...[
                        Text('> $cmd', style: mono),
                        SelectableText(
                          reply,
                          style: mono?.copyWith(
                            color: failed
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      style: mono,
                      autocorrect: false,
                      decoration: InputDecoration(hintText: l.consoleHint),
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                  IconButton(
                    tooltip: l.consoleRun,
                    onPressed: _busy ? null : _run,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Log in to a MeshCore repeater or room server, see its status and run
/// commands. The password is only kept while this screen is open.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.connection, required this.node});

  final MeshCoreConnection connection;
  final Node node;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _password = TextEditingController();
  LoginResultPush? _login;
  RepeaterStatusPush? _status;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = context.l10n.serverNoAnswer(
            RadioConnection.describeError(e),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.connection;
    final n = widget.node;
    final login = _login;
    final s = _status;
    return Scaffold(
      appBar: AppBar(title: Text(l.serverTitle(n.displayName))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('server-password'),
            controller: _password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.serverPassword,
              helperText: l.serverPasswordHelp,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _do(() async {
                        final r = await c.login(n, _password.text);
                        if (mounted) setState(() => _login = r);
                      }),
                child: Text(l.serverLogin),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _do(() async {
                        final r = await c.serverStatus(n);
                        if (mounted) setState(() => _status = r);
                      }),
                child: Text(l.serverStatus),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal),
                label: Text(l.serverConsole),
                onPressed: login?.success == true && login!.isAdmin
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ConsoleScreen(
                            title: l.serverTitle(n.displayName),
                            run: (cmd) => c.serverCommand(n, cmd),
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (login != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                !login.success
                    ? l.serverLoginFailed
                    : login.isAdmin
                    ? l.serverLoggedInAdmin
                    : l.serverLoggedInGuest,
              ),
            ),
          if (login == null || !login.isAdmin)
            Text(
              l.serverConsoleNeedsLogin,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (s != null) ...[
            const Divider(height: 32),
            _row(
              l.statusBattery,
              l.statusVolts((s.batteryMv / 1000).toStringAsFixed(2)),
            ),
            _row(
              l.statusUptime,
              l.statusUptimeValue(
                s.uptimeSeconds ~/ 86400,
                (s.uptimeSeconds % 86400) ~/ 3600,
              ),
            ),
            _row(l.statusNoise, l.diagValueDbm(s.noiseFloor)),
            _row(
              l.statusLastSignal,
              pathSummary(context, PathFacts(snr: s.lastSnr, rssi: s.lastRssi)),
            ),
            _row(
              l.statusPackets,
              l.statusPacketsValue(s.packetsReceived, s.packetsSent),
            ),
            _row(l.statusAirtime, l.statusAirtimeValue(s.airTimeSeconds ~/ 60)),
            _row(l.statusQueue, '${s.queueLength}'),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
