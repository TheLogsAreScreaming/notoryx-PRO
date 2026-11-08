import 'dart:async';
import 'dart:typed_data';

import 'ble_backend.dart';
import 'ble_profiles.dart';
import 'connection_log.dart';
import 'radio_link.dart';

/// A radio reached over Bluetooth Low Energy.
///
/// Each event on [incoming] is one whole frame: a MeshCore companion frame
/// or one Meshtastic `FromRadio` packet. For Meshtastic, a FromNum
/// notification only says new data is waiting, so the link reads FromRadio
/// until it comes back empty ([drain]); it also drains once after
/// connecting and after every write, since the reply may already be queued.
class BleRadioLink extends BaseRadioLink {
  BleRadioLink({
    required this.deviceId,
    required this.name,
    required this.profile,
    required BleBackend backend,
    ConnectionLog? log,
    this.mtu = 512,
    this.maxDrainReads = 200,
    this.pollEvery = const Duration(seconds: 2),
  }) : _backend = backend,
       _log = log;

  /// Platform device ID.
  final String deviceId;

  /// Name to show, usually the advertised name.
  final String name;

  /// Which protocol's service to use.
  final BleProfile profile;

  /// Packet size to ask for after connecting.
  final int mtu;

  /// Safety limit on reads in one [drain], so a radio stuck returning data
  /// can't lock the app in a loop.
  final int maxDrainReads;

  /// For Meshtastic: how often to look for queued packets anyway, in case
  /// the radio's FromNum notification doesn't arrive.
  final Duration pollEvery;
  Timer? _poll;

  final BleBackend _backend;
  final ConnectionLog? _log;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _draining = Future.value();
  bool _drainQueued = false;

  @override
  RadioProtocol get protocol => profile.protocol;

  @override
  LinkKind get kind => LinkKind.bluetooth;

  @override
  String get label => name;

  @override
  bool get deliversFrames => true;

  String get _source => 'BLE $name';

  @override
  Future<void> open() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    setState(LinkState.connecting);
    _log?.add(_source, 'connecting (${profile.protocol.label})');
    try {
      await _backend.connect(deviceId);
      _subscriptions.add(
        _backend.connection(deviceId).listen((connected) {
          if (!connected) _dropped();
        }),
      );
      final services = await _backend.discoverServices(deviceId);
      if (!services.map(normalizeUuid).contains(profile.service)) {
        throw LinkException(
          '$name has no ${profile.protocol.label} Bluetooth service',
        );
      }
      try {
        final granted = await _backend.requestMtu(deviceId, mtu);
        _log?.add(_source, 'packet size $granted');
      } on Object catch (error) {
        // Some platforms pick the size themselves; carry on.
        _log?.add(_source, 'packet size request skipped: $error');
      }
      if (profile.protocol == RadioProtocol.meshtastic) await _ensurePaired();
      _subscriptions.add(
        _backend.values(deviceId, profile.notify).listen(_onNotify),
      );
      await _backend.subscribe(deviceId, profile.service, profile.notify);
      setState(LinkState.connected);
      _log?.add(_source, 'connected');
      if (profile.pollsForData) {
        unawaited(drain());
        _poll = Timer.periodic(pollEvery, (_) => unawaited(drain()));
      }
    } on Object catch (error) {
      _log?.add(_source, 'connect failed: $error');
      await _cancelSubscriptions();
      setState(LinkState.disconnected);
      try {
        await _backend.disconnect(deviceId);
      } on Object catch (_) {
        // Not connected anyway.
      }
      if (error is LinkException) rethrow;
      throw LinkException('Could not connect to $name', error);
    }
  }

  /// Meshtastic radios keep their data behind a PIN: without a bond the
  /// reads and notifications fail, so pair first if the system can tell
  /// there is no bond yet.
  Future<void> _ensurePaired() async {
    try {
      final paired = await _backend.isPaired(deviceId);
      if (paired == false) {
        _log?.add(_source, 'pairing (enter the radio\'s PIN if asked)');
        await _backend.pair(deviceId);
        _log?.add(_source, 'paired');
      }
    } on Object catch (error) {
      // Some platforms pair on first use instead; carry on and see.
      _log?.add(_source, 'pairing skipped: $error');
    }
  }

  void _onNotify(Uint8List value) {
    if (state != LinkState.connected) return;
    if (profile.pollsForData) {
      unawaited(drain());
    } else {
      deliver(value);
    }
  }

  /// Reads queued Meshtastic packets until the radio has none left.
  ///
  /// Calls made while a drain runs are folded into one follow-up drain.
  Future<void> drain() {
    if (!profile.pollsForData) return Future.value();
    if (_drainQueued) return _draining;
    _drainQueued = true;
    _draining = _draining.then((_) async {
      _drainQueued = false;
      await _readUntilEmpty();
    });
    return _draining;
  }

  Future<void> _readUntilEmpty() async {
    for (var i = 0; i < maxDrainReads; i++) {
      if (state != LinkState.connected) return;
      final Uint8List packet;
      try {
        packet = await _backend.read(deviceId, profile.service, profile.read!);
      } on Object catch (error) {
        _log?.add(_source, 'read failed: $error');
        return;
      }
      if (packet.isEmpty) return;
      deliver(packet);
    }
    _log?.add(_source, 'stopped reading after $maxDrainReads packets');
  }

  @override
  Future<void> send(Uint8List data) async {
    requireConnected();
    try {
      await _backend.write(deviceId, profile.service, profile.write, data);
    } on Object catch (error) {
      _log?.add(_source, 'write failed: $error');
      throw LinkException('Could not send to $name', error);
    }
    if (profile.pollsForData) unawaited(drain());
  }

  void _dropped() {
    if (state == LinkState.disconnected || state == LinkState.idle) return;
    _log?.add(_source, 'connection lost');
    unawaited(_cancelSubscriptions());
    setState(LinkState.disconnected);
  }

  @override
  Future<void> close() async {
    if (state == LinkState.idle || state == LinkState.disconnected) return;
    _log?.add(_source, 'disconnecting');
    await _cancelSubscriptions();
    setState(LinkState.disconnected);
    try {
      await _backend.disconnect(deviceId);
    } on Object catch (error) {
      _log?.add(_source, 'disconnect error: $error');
    }
  }

  Future<void> _cancelSubscriptions() async {
    _poll?.cancel();
    _poll = null;
    final subs = List.of(_subscriptions);
    _subscriptions.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }
}
