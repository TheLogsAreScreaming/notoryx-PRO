import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/radio_connection.dart';
import '../app/radio_target.dart';
import '../meshcore/firmware.dart';
import '../meshtastic/firmware.dart';
import '../radio/radio.dart';
import 'admin_screens.dart';
import 'common.dart';
import 'connection_log_sheet.dart';
import 'diagnostics_screen.dart';
import 'verify_screen.dart';
import 'channels_screen.dart';
import 'meshtastic_admin_screen.dart';
import 'telemetry_screen.dart';

/// Connected radios, and ways to connect more: Bluetooth, Wi-Fi and USB.
class RadiosScreen extends StatelessWidget {
  const RadiosScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.radiosConnected,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (app.connections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.radiosNone),
            ),
          for (final c in app.connections)
            _ConnectionCard(app: app, connection: c),
          if (app.connections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                app.canAddRadio
                    ? l.radiosAddAnother
                    : l.radiosFull(AppController.maxRadios),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(l.radiosFindBluetooth),
            onPressed: !app.canAddRadio
                ? null
                : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BluetoothScanSheet(app: app),
                  ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.wifi),
            label: Text(l.radiosAddWifi),
            onPressed: !app.canAddRadio
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => WifiRadioDialog(app: app),
                  ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(l.logButton),
            onPressed: () => showConnectionLog(context, app.log),
          ),
          if (app.links.usb.supported) ...[
            const SizedBox(height: 24),
            _UsbSection(app: app),
          ],
        ],
      ),
    );
  }
}

/// Text for a connection's status.
String statusText(BuildContext context, RadioConnection c) {
  final l = context.l10n;
  final s = c.status;
  return switch (s.phase) {
    SupervisorPhase.stopped => l.statusStopped,
    SupervisorPhase.connecting => l.statusConnecting,
    SupervisorPhase.connected => l.statusConnected,
    SupervisorPhase.reconnecting => l.statusReconnecting(s.attempt),
    SupervisorPhase.failed => l.statusFailed(switch (s.lastError) {
      UnsupportedFirmware(:final message) => message,
      UnsupportedMeshtasticFirmware(:final message) => message,
      final e? => RadioConnection.describeError(e),
      null => '',
    }),
  };
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.app, required this.connection});

  final AppController app;
  final RadioConnection connection;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = connection;
    final radio = c.radio;
    final phase = c.status.phase;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (c.target.kind) {
                  LinkKind.bluetooth => Icons.bluetooth,
                  LinkKind.usb => Icons.usb,
                  LinkKind.tcp => Icons.wifi,
                }),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    radio?.name ?? c.target.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ProtocolBadge(c.protocol),
              ],
            ),
            const SizedBox(height: 4),
            Text(statusText(context, c)),
            if (radio != null && radio.firmware.isNotEmpty)
              Text(l.radioFirmware(radio.firmware)),
            if (c is MeshtasticConnection &&
                c.regionUnset &&
                phase == SupervisorPhase.connected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.regionUnsetWarning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (c is MeshCoreConnection &&
                    c.settings != null &&
                    phase == SupervisorPhase.connected)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tune),
                    label: Text(l.settings),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MeshCoreSettingsScreen(connection: c),
                      ),
                    ),
                  ),
                if (c is MeshtasticConnection &&
                    phase == SupervisorPhase.connected)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tune),
                    label: Text(l.settings),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MeshtasticSettingsScreen(connection: c),
                      ),
                    ),
                  ),
                if (c is MeshtasticConnection && radio != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.battery_charging_full),
                    label: Text(l.telemetryButton),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TelemetryScreen(
                          store: c.store,
                          radioId: radio.id,
                          node: radio.self,
                          name: radio.name,
                        ),
                      ),
                    ),
                  ),
                if (phase == SupervisorPhase.connected && radio != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tag),
                    label: Text(l.channelsButton),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChannelsScreen(connection: c),
                      ),
                    ),
                  ),
                if (c.ownCard case final card?)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: Text(l.myCode),
                    onPressed: () => showMyCode(context, card),
                  ),
                if (radio != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: Text(l.diagnostics),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiagnosticsScreen(connection: c),
                      ),
                    ),
                  ),
                if (phase == SupervisorPhase.reconnecting)
                  OutlinedButton(
                    onPressed: c.tryNow,
                    child: Text(l.radiosTryNow),
                  ),
                TextButton(
                  onPressed: () => app.disconnect(c),
                  child: Text(l.radiosDisconnect),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks which mesh a radio speaks, when it couldn't be told from Bluetooth.
Future<RadioProtocol?> pickProtocol(BuildContext context) =>
    showDialog<RadioProtocol>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.radiosPickProtocol),
        children: [
          for (final p in RadioProtocol.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Text(protocolName(context, p)),
            ),
        ],
      ),
    );

/// Scans for MeshCore and Meshtastic radios.
class BluetoothScanSheet extends StatefulWidget {
  const BluetoothScanSheet({super.key, required this.app});

  final AppController app;

  @override
  State<BluetoothScanSheet> createState() => _BluetoothScanSheetState();
}

class _BluetoothScanSheetState extends State<BluetoothScanSheet> {
  bool _showAll = false;
  late Stream<List<FoundRadio>> _scan = _start();

  Stream<List<FoundRadio>> _start() =>
      BleRadioScanner(widget.app.links.ble).scan(showAll: _showAll);

  Future<void> _connect(FoundRadio r) async {
    final protocol = r.protocol ?? await pickProtocol(context);
    if (protocol == null || !mounted) return;
    Navigator.pop(context);
    await widget.app.connect(
      BleTarget(deviceId: r.deviceId, name: r.name, protocol: protocol),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            ListTile(
              title: Text(
                l.radiosScanTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SwitchListTile(
              title: Text(l.radiosShowAll),
              value: _showAll,
              onChanged: (v) => setState(() {
                _showAll = v;
                _scan = _start();
              }),
            ),
            Expanded(
              child: StreamBuilder<List<FoundRadio>>(
                stream: _scan,
                builder: (context, snap) {
                  if (snap.error case final ScanUnavailable e) {
                    return EmptyState(
                      e.message,
                      icon: Icons.bluetooth_disabled,
                    );
                  }
                  final radios = snap.data ?? const <FoundRadio>[];
                  final scanning = snap.connectionState != ConnectionState.done;
                  if (radios.isEmpty) {
                    return EmptyState(
                      scanning ? l.radiosScanning : l.radiosScanNothing,
                      icon: Icons.bluetooth_searching,
                    );
                  }
                  return ListView(
                    children: [
                      for (final r in radios)
                        ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(r.name),
                          subtitle: r.rssi == null
                              ? null
                              : Text(l.pathRssi(r.rssi!)),
                          trailing: r.protocol == null
                              ? Text(l.radiosUnknownProtocol)
                              : ProtocolBadge(r.protocol!),
                          onTap: () => _connect(r),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Address, optional port and mesh for a radio on the network.
class WifiRadioDialog extends StatefulWidget {
  const WifiRadioDialog({super.key, required this.app});

  final AppController app;

  @override
  State<WifiRadioDialog> createState() => _WifiRadioDialogState();
}

class _WifiRadioDialogState extends State<WifiRadioDialog> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController();
  RadioProtocol _protocol = RadioProtocol.meshcore;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final port = int.tryParse(_port.text.trim());
    Navigator.pop(context);
    widget.app.connect(
      TcpTarget(host: _host.text.trim(), port: port, protocol: _protocol),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.radiosAddWifi),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<RadioProtocol>(
              segments: [
                for (final p in RadioProtocol.values)
                  ButtonSegment(
                    value: p,
                    label: Text(protocolName(context, p)),
                  ),
              ],
              selected: {_protocol},
              onSelectionChanged: (s) => setState(() => _protocol = s.single),
            ),
            TextFormField(
              key: const Key('wifi-host'),
              controller: _host,
              decoration: InputDecoration(
                labelText: l.radiosHost,
                hintText: l.radiosHostHint,
              ),
              keyboardType: TextInputType.url,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l.radiosHostRequired : null,
            ),
            TextFormField(
              key: const Key('wifi-port'),
              controller: _port,
              decoration: InputDecoration(
                labelText: l.radiosPort,
                hintText: '${TcpRadioLink.defaultPort(_protocol)}',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                return n == null || n < 1 || n > 65535
                    ? l.radiosPortInvalid
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.radiosCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.radiosConnect)),
      ],
    );
  }
}

class _UsbSection extends StatefulWidget {
  const _UsbSection({required this.app});

  final AppController app;

  @override
  State<_UsbSection> createState() => _UsbSectionState();
}

class _UsbSectionState extends State<_UsbSection> {
  late Future<List<SerialPortInfo>> _ports = widget.app.links.usb.list();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.radiosUsb,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: l.radiosRefresh,
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  setState(() => _ports = widget.app.links.usb.list()),
            ),
          ],
        ),
        FutureBuilder<List<SerialPortInfo>>(
          future: _ports,
          builder: (context, snap) {
            final ports = snap.data ?? const <SerialPortInfo>[];
            if (ports.isEmpty) return Text(l.radiosUsbNone);
            return Column(
              children: [
                for (final p in ports)
                  ListTile(
                    leading: const Icon(Icons.usb),
                    title: Text(p.name),
                    enabled: widget.app.canAddRadio,
                    onTap: () async {
                      final protocol = await pickProtocol(context);
                      if (protocol == null) return;
                      await widget.app.connect(
                        UsbTarget(port: p, protocol: protocol),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
