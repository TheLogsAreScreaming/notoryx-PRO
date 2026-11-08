import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/meshtastic_settings.dart';
import '../app/radio_connection.dart';
import '../mesh/mesh.dart';
import '../meshtastic/admin.dart';
import 'common.dart';

/// Settings of a Meshtastic node: the connected radio, or another node
/// ([node]) administered over the mesh.
class MeshtasticSettingsScreen extends StatefulWidget {
  const MeshtasticSettingsScreen({
    super.key,
    required this.connection,
    this.node,
    this.timeout = const Duration(seconds: 30),
  });

  final MeshtasticConnection connection;

  /// How long to wait for each answer (other nodes can be slow).
  final Duration timeout;

  /// Another node to administer; null for the connected radio.
  final Node? node;

  @override
  State<MeshtasticSettingsScreen> createState() =>
      _MeshtasticSettingsScreenState();
}

class _MeshtasticSettingsScreenState extends State<MeshtasticSettingsScreen> {
  final _form = GlobalKey<FormState>();
  MeshtasticSettings? _settings;
  Object? _error;
  bool _saving = false;
  final _longName = TextEditingController();
  final _shortName = TextEditingController();
  final _slot = TextEditingController();

  bool get _remote => widget.node != null;
  int? get _target => widget.node?.key.meshtasticNum;

  String get _name =>
      widget.node?.displayName ?? widget.connection.radio?.name ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_longName, _shortName, _slot]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _settings = null;
      _error = null;
    });
    try {
      final s = await widget.connection.loadSettings(
        node: _target,
        timeout: widget.timeout,
      );
      if (!mounted) return;
      final owner = s[SectionKind.owner];
      _longName.text = owner.text(OwnerField.longName);
      _shortName.text = owner.text(OwnerField.shortName);
      _slot.text = '${s[SectionKind.lora].number(LoraField.channelNum)}';
      setState(() => _settings = s);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _set(SectionKind kind, int field, Object value) =>
      setState(() => _settings = _settings!.withValue(kind, field, value));

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final l = context.l10n;
    final s = _settings;
    if (s == null || !_form.currentState!.validate()) return;
    if (!s.hasChanges) return _say(l.mtNoChanges);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.mtConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.radioChanged) ...[
              Text(
                l.mtConfirmRadio,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            if (s.becomesInfrastructure) ...[
              Text(
                l.mtConfirmRouter,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Text(l.mtConfirmRestart),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.settingsSave),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.connection.saveSettings(s, node: _target);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_remote ? l.mtSavedRemote(_name) : l.mtSavedLocal),
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      if (mounted) _say(l.settingsSaveFailed(RadioConnection.describeError(e)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restart() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          _remote ? l.mtRestartConfirm(_name) : l.settingsRebootConfirm,
        ),
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
    if (ok != true || !mounted) return;
    try {
      await widget.connection.rebootNode(node: _target);
      if (mounted && _remote) _say(l.mtRemoteRestarted(_name));
    } on Object catch (e) {
      if (mounted) _say(l.settingsSaveFailed(RadioConnection.describeError(e)));
    }
  }

  Future<void> _copyKey() async {
    final key = widget.connection.ownCard?.publicKey;
    if (key == null || key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: base64.encode(key)));
    if (mounted) _say(context.l10n.mtKeyCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = _settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(_remote ? l.mtRemoteTitle(_name) : l.settingsTitle(_name)),
      ),
      body: s != null
          ? _editor(context, s)
          : _error != null
          ? _failed(context)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l.mtLoading),
                ],
              ),
            ),
    );
  }

  Widget _failed(BuildContext context) {
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _remote
              ? l.mtRemoteFailed(_name)
              : l.mtLocalFailed(RadioConnection.describeError(_error!)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: _load, child: Text(l.mtTryAgain)),
            if (_remote &&
                (widget.connection.ownCard?.publicKey.isNotEmpty ?? false))
              OutlinedButton.icon(
                icon: const Icon(Icons.key),
                label: Text(l.mtCopyMyKey),
                onPressed: _copyKey,
              ),
          ],
        ),
      ],
    );
  }

  Widget _editor(BuildContext context, MeshtasticSettings s) {
    final l = context.l10n;
    final heading = Theme.of(context).textTheme.titleMedium;
    final device = s[SectionKind.device];
    final lora = s[SectionKind.lora];
    final position = s[SectionKind.position];
    final telemetry = s[SectionKind.telemetry];
    final role = device.number(DeviceField.role);
    final region = lora.number(LoraField.region);
    final preset = lora.number(LoraField.modemPreset);
    final usePreset = lora.flag(LoraField.usePreset);
    final hops = lora.number(LoraField.hopLimit);
    final power = lora.signed(LoraField.txPower);
    final gpsMode = position.number(PositionField.gpsMode);

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.mtNames, style: heading),
          TextFormField(
            key: const Key('mt-long-name'),
            controller: _longName,
            decoration: InputDecoration(labelText: l.mtLongName),
            onChanged: (v) =>
                _set(SectionKind.owner, OwnerField.longName, v.trim()),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || utf8.encode(t).length > 39
                  ? l.mtLongNameInvalid
                  : null;
            },
          ),
          TextFormField(
            key: const Key('mt-short-name'),
            controller: _shortName,
            decoration: InputDecoration(labelText: l.mtShortName),
            onChanged: (v) =>
                _set(SectionKind.owner, OwnerField.shortName, v.trim()),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty ||
                      t.runes.length > 4 ||
                      utf8.encode(t).length > 7
                  ? l.mtShortNameInvalid
                  : null;
            },
          ),
          const SizedBox(height: 16),
          Text(l.mtRole, style: heading),
          DropdownButtonFormField<int>(
            key: const Key('mt-role'),
            initialValue: role,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.mtRole),
            items: [
              for (final r in {
                ...MeshtasticRole.choices,
                if (!MeshtasticRole.choices.contains(role)) role,
              })
                DropdownMenuItem(value: r, child: Text(roleName(context, r))),
            ],
            onChanged: (v) {
              if (v != null) _set(SectionKind.device, DeviceField.role, v);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              roleHelp(context, role),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          Text(l.mtRadio, style: heading),
          Text(
            l.settingsRadioWarning,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          DropdownButtonFormField<int>(
            key: const Key('mt-region'),
            initialValue: region,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.mtRegion),
            items: [
              if (region == MeshtasticRegion.unset)
                DropdownMenuItem(
                  value: MeshtasticRegion.unset,
                  child: Text(l.mtRegionUnset),
                ),
              if (region != MeshtasticRegion.unset &&
                  !MeshtasticRegion.names.containsKey(region))
                DropdownMenuItem(
                  value: region,
                  child: Text(l.mtRegionOther(region)),
                ),
              for (final MapEntry(key: code, value: name)
                  in MeshtasticRegion.names.entries)
                DropdownMenuItem(value: code, child: Text(name)),
            ],
            onChanged: (v) {
              if (v != null) _set(SectionKind.lora, LoraField.region, v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.mtUsePreset),
            value: usePreset,
            onChanged: (v) => _set(SectionKind.lora, LoraField.usePreset, v),
          ),
          if (usePreset)
            DropdownButtonFormField<int>(
              key: const Key('mt-preset'),
              initialValue: preset,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.mtPreset),
              items: [
                for (final MapEntry(key: code, value: name)
                    in MeshtasticPreset.names.entries)
                  if (!MeshtasticPreset.retired.contains(code) ||
                      code == preset)
                    DropdownMenuItem(value: code, child: Text(name)),
                if (!MeshtasticPreset.names.containsKey(preset))
                  DropdownMenuItem(
                    value: preset,
                    child: Text(l.mtPresetOther(preset)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  _set(SectionKind.lora, LoraField.modemPreset, v);
                }
              },
            )
          else
            Text(l.mtCustomRadio),
          TextFormField(
            key: const Key('mt-slot'),
            controller: _slot,
            decoration: InputDecoration(labelText: l.mtSlot),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 0 ? l.mtSlotInvalid : null;
            },
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null && n >= 0) {
                _set(SectionKind.lora, LoraField.channelNum, n);
              }
            },
          ),
          const SizedBox(height: 12),
          Text(l.mtHopLimit(hops)),
          Slider(
            key: const Key('mt-hops'),
            value: hops.clamp(1, 7).toDouble(),
            min: 1,
            max: 7,
            divisions: 6,
            label: '$hops',
            onChanged: (v) =>
                _set(SectionKind.lora, LoraField.hopLimit, v.round()),
          ),
          Text(l.mtHopHelp, style: Theme.of(context).textTheme.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.mtTxEnabled),
            value: lora.flag(LoraField.txEnabled),
            onChanged: (v) => _set(SectionKind.lora, LoraField.txEnabled, v),
          ),
          Text(
            l.mtTxPower(
              power <= 0 ? l.mtTxPowerMax : l.settingsTxPowerValue(power),
            ),
          ),
          Slider(
            value: power.clamp(0, 30).toDouble(),
            min: 0,
            max: 30,
            divisions: 30,
            label: power <= 0 ? l.mtTxPowerMax : l.settingsTxPowerValue(power),
            onChanged: (v) =>
                _set(SectionKind.lora, LoraField.txPower, v.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.mtOkToMqtt),
            value: lora.flag(LoraField.okToMqtt),
            onChanged: (v) => _set(SectionKind.lora, LoraField.okToMqtt, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.mtIgnoreMqtt),
            value: lora.flag(LoraField.ignoreMqtt),
            onChanged: (v) => _set(SectionKind.lora, LoraField.ignoreMqtt, v),
          ),
          const SizedBox(height: 16),
          Text(l.mtPosition, style: heading),
          _interval(
            context,
            label: l.mtPositionInterval,
            value: position.number(PositionField.broadcastSecs),
            onChanged: (v) =>
                _set(SectionKind.position, PositionField.broadcastSecs, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.mtSmartPosition),
            value: position.flag(PositionField.smartBroadcast),
            onChanged: (v) =>
                _set(SectionKind.position, PositionField.smartBroadcast, v),
          ),
          DropdownButtonFormField<int>(
            initialValue: gpsMode.clamp(0, 2),
            decoration: InputDecoration(labelText: l.mtGpsMode),
            items: [
              DropdownMenuItem(
                value: MeshtasticGpsMode.enabled,
                child: Text(l.mtGpsEnabled),
              ),
              DropdownMenuItem(
                value: MeshtasticGpsMode.disabled,
                child: Text(l.mtGpsDisabled),
              ),
              DropdownMenuItem(
                value: MeshtasticGpsMode.notPresent,
                child: Text(l.mtGpsNotPresent),
              ),
            ],
            onChanged: (v) {
              if (v != null) {
                _set(SectionKind.position, PositionField.gpsMode, v);
              }
            },
          ),
          if (position.flag(PositionField.fixedPosition))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.mtFixedPosition),
            ),
          const SizedBox(height: 16),
          Text(l.mtTelemetry, style: heading),
          _interval(
            context,
            label: l.mtDeviceInterval,
            value: telemetry.number(TelemetryField.deviceInterval),
            onChanged: (v) =>
                _set(SectionKind.telemetry, TelemetryField.deviceInterval, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.mtEnvironmentEnabled),
            value: telemetry.flag(TelemetryField.environmentEnabled),
            onChanged: (v) => _set(
              SectionKind.telemetry,
              TelemetryField.environmentEnabled,
              v,
            ),
          ),
          if (telemetry.flag(TelemetryField.environmentEnabled))
            _interval(
              context,
              label: l.mtEnvironmentInterval,
              value: telemetry.number(TelemetryField.environmentInterval),
              onChanged: (v) => _set(
                SectionKind.telemetry,
                TelemetryField.environmentInterval,
                v,
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('mt-save'),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(l.settingsSave),
            onPressed: _saving || !s.hasChanges ? null : _save,
          ),
          const Divider(height: 32),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _restart,
              child: Text(l.settingsReboot),
            ),
          ),
        ],
      ),
    );
  }

  /// Interval choices, in seconds; 0 is the firmware's default.
  static const _intervals = [0, 900, 1800, 3600, 10800, 21600, 43200, 86400];

  Widget _interval(
    BuildContext context, {
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) => DropdownButtonFormField<int>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final v in {..._intervals, value})
        DropdownMenuItem(value: v, child: Text(intervalName(context, v))),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

/// How often something is sent, in words.
String intervalName(BuildContext context, int seconds) {
  final l = context.l10n;
  if (seconds <= 0) return l.mtIntervalDefault;
  if (seconds % 3600 == 0) return l.mtIntervalHours(seconds ~/ 3600);
  if (seconds % 60 == 0) return l.mtIntervalMinutes(seconds ~/ 60);
  return l.mtIntervalSeconds(seconds);
}

/// A Meshtastic role's name.
String roleName(BuildContext context, int role) {
  final l = context.l10n;
  return switch (role) {
    MeshtasticRole.client => l.mtRoleClient,
    MeshtasticRole.clientMute => l.mtRoleClientMute,
    MeshtasticRole.clientBase => l.mtRoleClientBase,
    MeshtasticRole.clientHidden => l.mtRoleClientHidden,
    MeshtasticRole.tracker => l.mtRoleTracker,
    MeshtasticRole.sensor => l.mtRoleSensor,
    MeshtasticRole.router => l.mtRoleRouter,
    MeshtasticRole.routerLate => l.mtRoleRouterLate,
    MeshtasticRole.tak => l.mtRoleTak,
    MeshtasticRole.takTracker => l.mtRoleTakTracker,
    MeshtasticRole.lostAndFound => l.mtRoleLostAndFound,
    _ => l.mtRoleOld(role),
  };
}

/// What a Meshtastic role does.
String roleHelp(BuildContext context, int role) {
  final l = context.l10n;
  return switch (role) {
    MeshtasticRole.client => l.mtRoleHelpClient,
    MeshtasticRole.clientMute => l.mtRoleHelpClientMute,
    MeshtasticRole.clientBase => l.mtRoleHelpClientBase,
    MeshtasticRole.clientHidden => l.mtRoleHelpClientHidden,
    MeshtasticRole.tracker => l.mtRoleHelpTracker,
    MeshtasticRole.sensor => l.mtRoleHelpSensor,
    MeshtasticRole.router => l.mtRoleHelpRouter,
    MeshtasticRole.routerLate => l.mtRoleHelpRouterLate,
    MeshtasticRole.tak => l.mtRoleHelpTak,
    MeshtasticRole.takTracker => l.mtRoleHelpTakTracker,
    MeshtasticRole.lostAndFound => l.mtRoleHelpLostAndFound,
    _ => l.mtRoleHelpOld,
  };
}
