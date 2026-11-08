import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/mqtt_feed.dart';
import '../radio/radio_link.dart';
import 'common.dart';
import 'diagnostics_screen.dart';

/// MQTT feeds: read-only views of a mesh through an internet broker.
class FeedsScreen extends StatefulWidget {
  const FeedsScreen({super.key, required this.app});

  final AppController app;

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  late final Future<void> _loaded = widget.app.feeds.load();

  MqttFeeds get _feeds => widget.app.feeds;

  String _status(BuildContext context, MqttFeed f) {
    final l = context.l10n;
    return switch (f.state) {
      MqttFeedState.off => l.feedOff,
      MqttFeedState.connecting => l.feedConnecting,
      MqttFeedState.connected => l.feedConnected(f.log.entries.length),
      MqttFeedState.failed => l.feedFailed(f.error ?? ''),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.feedsTitle)),
      floatingActionButton: FloatingActionButton(
        tooltip: l.feedAdd,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _FeedForm(feeds: _feeds)),
        ),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) => ListenableBuilder(
          listenable: _feeds,
          builder: (context, _) {
            final feeds = _feeds.feeds;
            return ListView(
              children: [
                ListTile(subtitle: Text(l.feedsHelp)),
                if (feeds.isEmpty) EmptyState(l.feedsEmpty),
                for (final f in feeds)
                  ListTile(
                    leading: ProtocolBadge(f.config.protocol),
                    title: Text(f.config.name),
                    subtitle: Text(_status(context, f)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(f.config.name)),
                          body: PacketLogView(log: f.log),
                        ),
                      ),
                    ),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Switch(
                          value:
                              f.state != MqttFeedState.off &&
                              f.state != MqttFeedState.failed,
                          onChanged: (on) => on ? f.start() : f.stop(),
                        ),
                        IconButton(
                          tooltip: l.deleteAction,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _feeds.remove(f),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeedForm extends StatefulWidget {
  const _FeedForm({required this.feeds});

  final MqttFeeds feeds;

  @override
  State<_FeedForm> createState() => _FeedFormState();
}

class _FeedFormState extends State<_FeedForm> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1883');
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _topic = TextEditingController(
    text: MqttFeedConfig.defaultTopic(RadioProtocol.meshtastic),
  );
  RadioProtocol _protocol = RadioProtocol.meshtastic;
  bool _tls = false;

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _password, _topic]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _portNumber {
    final p = int.tryParse(_port.text.trim());
    return p != null && p > 0 && p < 65536 ? p : null;
  }

  bool get _valid =>
      _host.text.trim().isNotEmpty &&
      _topic.text.trim().isNotEmpty &&
      _portNumber != null;

  Future<void> _save() async {
    final host = _host.text.trim();
    final name = _name.text.trim();
    final nav = Navigator.of(context);
    await widget.feeds.add(
      MqttFeedConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.isEmpty ? host : name,
        protocol: _protocol,
        host: host,
        port: _portNumber!,
        tls: _tls,
        username: _user.text.trim(),
        password: _password.text,
        topic: _topic.text.trim(),
      ),
    );
    if (mounted) nav.pop();
  }

  Widget _field(
    TextEditingController c,
    String label, {
    Key? key,
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: key,
      controller: c,
      obscureText: secret,
      keyboardType: keyboard,
      autocorrect: false,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.feedAdd)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<RadioProtocol>(
            segments: const [
              ButtonSegment(
                value: RadioProtocol.meshtastic,
                label: Text('Meshtastic'),
              ),
              ButtonSegment(
                value: RadioProtocol.meshcore,
                label: Text('MeshCore'),
              ),
            ],
            selected: {_protocol},
            onSelectionChanged: (s) => setState(() {
              _protocol = s.single;
              _topic.text = MqttFeedConfig.defaultTopic(_protocol);
            }),
          ),
          const SizedBox(height: 8),
          _field(_name, l.feedName),
          _field(_host, l.feedHost, key: const Key('feed-host')),
          _field(_port, l.feedPort, keyboard: TextInputType.number),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.feedTls),
            value: _tls,
            onChanged: (v) => setState(() {
              _tls = v;
              if (_port.text == '1883' && v) _port.text = '8883';
              if (_port.text == '8883' && !v) _port.text = '1883';
            }),
          ),
          _field(_user, l.feedUser),
          _field(_password, l.feedPassword, secret: true),
          _field(_topic, l.feedTopic),
          if (!_tls && _password.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.feedPlainWarning),
            ),
          FilledButton(
            onPressed: _valid ? _save : null,
            child: Text(l.feedSave),
          ),
        ],
      ),
    );
  }
}
