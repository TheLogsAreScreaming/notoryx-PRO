import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/meshtastic_settings.dart';
import '../app/radio_connection.dart';
import '../l10n/app_localizations.dart';
import '../mesh/mesh.dart';
import '../meshtastic/admin.dart';
import 'common.dart';

typedef _Text = String Function(AppLocalizations l);

/// One editable setting of a module. Field numbers are from
/// `module_config.proto`.
sealed class _Setting {
  const _Setting(this.field, this.label);
  final int field;
  final _Text label;
}

class _Toggle extends _Setting {
  const _Toggle(super.field, super.label);
}

class _Number extends _Setting {
  const _Number(super.field, super.label, {this.max = 0xffffffff});
  final int max;
}

class _Words extends _Setting {
  const _Words(
    super.field,
    super.label, {
    required this.maxBytes,
    this.secret = false,
  });

  final int maxBytes;
  final bool secret;
}

class _Choice extends _Setting {
  const _Choice(super.field, super.label, this.names);
  final Map<int, String> names;
}

class _Module {
  const _Module(this.kind, this.name, this.help, this.settings);
  final SectionKind kind;
  final _Text name;
  final _Text help;
  final List<_Setting> settings;
}

_Text _on = (l) => l.modEnabled;

const _pin = 255;

final _modules = <_Module>[
  _Module(SectionKind.mqtt, (l) => l.modMqtt, (l) => l.modMqttHelp, [
    _Toggle(1, _on),
    _Words(2, (l) => l.modMqttAddress, maxBytes: 63),
    _Words(3, (l) => l.modMqttUser, maxBytes: 63),
    _Words(4, (l) => l.modMqttPassword, maxBytes: 31, secret: true),
    _Toggle(5, (l) => l.modMqttEncrypted),
    _Toggle(6, (l) => l.modMqttJson),
    _Toggle(7, (l) => l.modMqttTls),
    _Words(8, (l) => l.modMqttRoot, maxBytes: 31),
    _Toggle(9, (l) => l.modMqttProxy),
    _Toggle(10, (l) => l.modMqttMap),
  ]),
  _Module(SectionKind.serial, (l) => l.modSerial, (l) => l.modSerialHelp, [
    _Toggle(1, _on),
    _Toggle(2, (l) => l.modSerialEcho),
    _Number(3, (l) => l.modSerialRx, max: _pin),
    _Number(4, (l) => l.modSerialTx, max: _pin),
    _Choice(5, (l) => l.modSerialBaud, const {
      0: 'Default',
      1: '110',
      2: '300',
      3: '600',
      4: '1200',
      5: '2400',
      6: '4800',
      7: '9600',
      8: '19200',
      9: '38400',
      10: '57600',
      11: '115200',
      12: '230400',
      13: '460800',
      14: '576000',
      15: '921600',
    }),
    _Number(6, (l) => l.modSerialTimeout),
    _Choice(7, (l) => l.modSerialMode, const {
      0: 'Default',
      1: 'Simple',
      2: 'Protobuf',
      3: 'Text message',
      4: 'NMEA',
      5: 'CalTopo',
      6: 'WS85',
      7: 'VE.Direct',
      8: 'MS config',
      9: 'Log',
      10: 'Log (text only)',
    }),
  ]),
  _Module(
    SectionKind.externalNotification,
    (l) => l.modExternal,
    (l) => l.modExternalHelp,
    [
      _Toggle(1, _on),
      _Number(2, (l) => l.modExternalMs),
      _Number(3, (l) => l.modExternalPin, max: _pin),
      _Toggle(4, (l) => l.modExternalActive),
      _Toggle(5, (l) => l.modExternalMessage),
      _Toggle(6, (l) => l.modExternalBell),
      _Toggle(7, (l) => l.modExternalPwm),
      _Number(14, (l) => l.modExternalNag),
    ],
  ),
  _Module(SectionKind.storeForward, (l) => l.modStore, (l) => l.modStoreHelp, [
    _Toggle(1, _on),
    _Toggle(2, (l) => l.modStoreHeartbeat),
    _Number(3, (l) => l.modStoreRecords),
    _Number(4, (l) => l.modStoreMax),
    _Number(5, (l) => l.modStoreWindow),
    _Toggle(6, (l) => l.modStoreServer),
  ]),
  _Module(SectionKind.rangeTest, (l) => l.modRange, (l) => l.modRangeHelp, [
    _Toggle(1, _on),
    _Number(2, (l) => l.modRangeSender),
    _Toggle(3, (l) => l.modRangeSave),
  ]),
  _Module(
    SectionKind.neighborInfo,
    (l) => l.modNeighbor,
    (l) => l.modNeighborHelp,
    [
      _Toggle(1, _on),
      _Number(2, (l) => l.modNeighborInterval),
      _Toggle(3, (l) => l.modNeighborLora),
    ],
  ),
  _Module(
    SectionKind.ambientLighting,
    (l) => l.modAmbient,
    (l) => l.modAmbientHelp,
    [
      _Toggle(1, _on),
      _Number(2, (l) => l.modAmbientCurrent, max: 31),
      _Number(3, (l) => l.modAmbientRed, max: 255),
      _Number(4, (l) => l.modAmbientGreen, max: 255),
      _Number(5, (l) => l.modAmbientBlue, max: 255),
    ],
  ),
  _Module(
    SectionKind.detectionSensor,
    (l) => l.modDetection,
    (l) => l.modDetectionHelp,
    [
      _Toggle(1, _on),
      _Number(2, (l) => l.modDetectionMin),
      _Number(3, (l) => l.modDetectionState),
      _Toggle(4, (l) => l.modDetectionBell),
      _Words(5, (l) => l.modDetectionName, maxBytes: 19),
      _Number(6, (l) => l.modDetectionPin, max: _pin),
      _Choice(7, (l) => l.modDetectionTrigger, const {
        0: 'Low',
        1: 'High',
        2: 'Falling edge',
        3: 'Rising edge',
        4: 'Either edge, active low',
        5: 'Either edge, active high',
      }),
      _Toggle(8, (l) => l.modDetectionPullup),
    ],
  ),
  _Module(SectionKind.paxcounter, (l) => l.modPax, (l) => l.modPaxHelp, [
    _Toggle(1, _on),
    _Number(2, (l) => l.modPaxInterval),
  ]),
  _Module(
    SectionKind.remoteHardware,
    (l) => l.modRemote,
    (l) => l.modRemoteHelp,
    [_Toggle(1, _on), _Toggle(2, (l) => l.modRemoteUndefined)],
  ),
];

/// Lists a Meshtastic node's optional modules.
class MeshtasticModulesScreen extends StatelessWidget {
  const MeshtasticModulesScreen({
    super.key,
    required this.connection,
    this.node,
    this.timeout = const Duration(seconds: 30),
  });

  final MeshtasticConnection connection;

  /// Another node to administer; null for the connected radio.
  final Node? node;
  final Duration timeout;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final name = node?.displayName ?? connection.radio?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l.modTitle(name))),
      body: ListView(
        children: [
          for (final m in _modules)
            ListTile(
              title: Text(m.name(l)),
              subtitle: Text(m.help(l)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ModuleScreen(
                    module: m,
                    connection: connection,
                    node: node,
                    timeout: timeout,
                  ),
                ),
              ),
            ),
          ListTile(subtitle: Text(l.modNotCovered)),
        ],
      ),
    );
  }
}

class _ModuleScreen extends StatefulWidget {
  const _ModuleScreen({
    required this.module,
    required this.connection,
    required this.node,
    required this.timeout,
  });

  final _Module module;
  final MeshtasticConnection connection;
  final Node? node;
  final Duration timeout;

  @override
  State<_ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<_ModuleScreen> {
  final _form = GlobalKey<FormState>();
  final Map<int, TextEditingController> _controllers = {};
  MeshtasticSettings? _settings;
  Object? _error;
  bool _saving = false;

  SectionKind get _kind => widget.module.kind;
  int? get _target => widget.node?.key.meshtasticNum;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
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
        kinds: [_kind],
      );
      if (!mounted) return;
      final section = s[_kind];
      for (final setting in widget.module.settings) {
        final text = switch (setting) {
          _Words() => section.text(setting.field),
          _Number() => '${section.number(setting.field)}',
          _ => null,
        };
        if (text != null) {
          (_controllers[setting.field] ??= TextEditingController()).text = text;
        }
      }
      setState(() => _settings = s);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _set(int field, Object value) =>
      setState(() => _settings = _settings!.withValue(_kind, field, value));

  Future<void> _save() async {
    final l = context.l10n;
    final s = _settings;
    if (s == null || !_form.currentState!.validate()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.mtConfirmTitle),
        content: Text(l.mtConfirmRestart),
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
    final name = widget.node?.displayName;
    try {
      await widget.connection.saveSettings(
        s,
        node: _target,
        timeout: widget.timeout,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(name == null ? l.mtSavedLocal : l.mtSavedRemote(name)),
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l.settingsSaveFailed(RadioConnection.describeError(e)),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(BuildContext context, _Setting setting, SettingsSection s) {
    final l = context.l10n;
    final key = Key('mod-${setting.field}');
    switch (setting) {
      case _Toggle():
        return SwitchListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(setting.label(l)),
          value: s.flag(setting.field),
          onChanged: (v) => _set(setting.field, v),
        );
      case _Number():
        return TextFormField(
          key: key,
          controller: _controllers[setting.field],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: setting.label(l)),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (t) {
            final v = int.tryParse(t ?? '');
            return v == null || v < 0 || v > setting.max
                ? l.modInvalidNumber(setting.max)
                : null;
          },
          onChanged: (t) {
            final v = int.tryParse(t);
            if (v != null && v >= 0 && v <= setting.max) {
              _set(setting.field, v);
            }
          },
        );
      case _Words():
        return TextFormField(
          key: key,
          controller: _controllers[setting.field],
          obscureText: setting.secret,
          autocorrect: false,
          decoration: InputDecoration(labelText: setting.label(l)),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (t) => utf8.encode(t ?? '').length > setting.maxBytes
              ? l.modTooLong(setting.maxBytes)
              : null,
          onChanged: (t) => _set(setting.field, t),
        );
      case _Choice():
        final value = s.number(setting.field);
        return DropdownButtonFormField<int>(
          key: key,
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(labelText: setting.label(l)),
          items: [
            if (!setting.names.containsKey(value))
              DropdownMenuItem(
                value: value,
                child: Text(l.modOtherChoice('$value')),
              ),
            for (final e in setting.names.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) _set(setting.field, v);
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: Text(widget.module.name(l))),
      body: s != null
          ? Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(widget.module.help(l)),
                  const SizedBox(height: 8),
                  for (final setting in widget.module.settings)
                    _field(context, setting, s[_kind]),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('mod-save'),
                    onPressed: _saving || !s.hasChanges ? null : _save,
                    child: Text(l.settingsSave),
                  ),
                ],
              ),
            )
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l.settingsSaveFailed(RadioConnection.describeError(_error!)),
                ),
                TextButton(onPressed: _load, child: Text(l.mtTryAgain)),
              ],
            )
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
}
