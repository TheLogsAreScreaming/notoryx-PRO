import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import '../radio/connection_log.dart';
import '../radio/radio_link.dart';
import 'codes.dart';
import 'commands.dart';
import 'firmware.dart';
import 'frames.dart';
import 'stream_framing.dart';

/// The radio answered a command with ERR.
class MeshCoreException implements Exception {
  const MeshCoreException(this.code, this.command);

  /// Why it failed.
  final MeshCoreErrorCode code;

  /// The command byte that failed.
  final int command;

  @override
  String toString() => 'MeshCoreException: ${code.message} (command $command)';
}

/// The radio didn't answer in time.
class MeshCoreTimeout implements Exception {
  const MeshCoreTimeout(this.command);

  /// The command byte that timed out.
  final int command;

  @override
  String toString() => 'MeshCoreTimeout: no reply to command $command';
}

/// Result of [MeshCoreSession.getContacts].
class ContactSync {
  const ContactSync({
    required this.contacts,
    required this.total,
    required this.lastModified,
  });

  /// Contacts returned (all, or only those changed since the `since` value).
  final List<ContactFrame> contacts;

  /// How many contacts the radio holds in all.
  final int total;

  /// Pass as `since` next time to fetch only changes.
  final int lastModified;
}

/// What the radio said when the session started.
class MeshCoreHandshake {
  const MeshCoreHandshake({
    required this.self,
    required this.device,
    required this.clockSet,
  });

  final SelfInfoFrame self;
  final DeviceInfoFrame device;

  /// Whether the radio accepted the phone's time (it won't go backwards).
  final bool clockSet;
}

/// Decides what to do with each frame while a command waits for its reply.
///
/// Returns true if the frame belongs to this command. Completes [done] when
/// the reply is complete.
typedef _Collector =
    bool Function(MeshCoreFrame frame, Completer<Object?> done);

class _Pending {
  _Pending(this.command, this.collect, this.timeout);

  final Uint8List command;
  final _Collector collect;
  final Duration timeout;
  final Completer<Object?> done = Completer<Object?>();
  Timer? timer;

  int get code => command.first;
}

/// Talks the MeshCore companion protocol over any [RadioLink].
///
/// Commands go out one at a time: each waits for its reply (or [timeout])
/// before the next is sent, as the firmware expects. Frames that aren't a
/// reply, such as adverts and delivery confirmations, appear on [pushes].
/// When the radio says messages are waiting, the session fetches them and
/// emits each on [messages] (turn off with `autoFetchMessages`).
class MeshCoreSession {
  MeshCoreSession(
    this.link, {
    this.timeout = const Duration(seconds: 5),
    this.appName = 'NOTORYX PRO',
    this.autoFetchMessages = true,
    ConnectionLog? log,
    DateTime Function()? clock,
  }) : _log = log,
       _clock = clock ?? DateTime.now;

  /// The link to the radio.
  final RadioLink link;

  /// How long to wait for each reply.
  final Duration timeout;

  /// Name sent in APP_START.
  final String appName;

  /// Whether to fetch queued messages when the radio says some are waiting.
  final bool autoFetchMessages;

  final ConnectionLog? _log;
  final DateTime Function() _clock;
  final Queue<_Pending> _queue = Queue<_Pending>();
  _Pending? _current;
  final List<StreamSubscription<Object?>> _subs = [];
  final _pushes = StreamController<MeshCoreFrame>.broadcast();
  final _messages = StreamController<MeshCoreFrame>.broadcast();
  bool _fetching = false;
  bool _fetchAgain = false;
  bool _attached = false;

  /// Unrequested frames from the radio.
  Stream<MeshCoreFrame> get pushes => _pushes.stream;

  /// Received direct messages, channel messages and channel datagrams.
  Stream<MeshCoreFrame> get messages => _messages.stream;

  String get _source => 'MeshCore ${link.label}';

  /// Starts listening to [link]. The link must already be open.
  void attach() {
    if (_attached) return;
    _attached = true;
    final frames = link.deliversFrames
        ? link.incoming
        : decodeStreamFrames(link.incoming);
    _subs.add(frames.listen(_onFrame));
    _subs.add(
      link.states.listen((state) {
        if (state == LinkState.disconnected) {
          _failAll(LinkException('${link.label} disconnected'));
        }
      }),
    );
  }

  /// Stops listening and fails any waiting commands. Doesn't close [link].
  Future<void> detach() async {
    _failAll(const LinkException('Session closed'));
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _attached = false;
  }

  /// Runs the start-up sequence: APP_START, DEVICE_QUERY and setting the
  /// radio's clock from this device.
  Future<MeshCoreHandshake> handshake() async {
    attach();
    final self = await appStart();
    final device = await deviceQuery();
    _firmwareCode = device.firmwareCode;
    if (device.firmwareCode < MeshCoreFirmware.minimumCode) {
      _log?.add(_source, 'firmware too old: ${device.firmwareCode}');
      // Stop before changing anything on the radio.
      throw UnsupportedFirmware(
        found: device.firmwareCode,
        needed: MeshCoreFirmware.minimumCode,
        version: device.version,
      );
    }
    var clockSet = true;
    try {
      await setTime(_clock());
    } on MeshCoreException {
      clockSet = false; // The radio's clock is already ahead; that's fine.
    }
    _log?.add(
      _source,
      'ready: protocol ${device.firmwareCode}, ${device.version ?? 'unknown'}',
    );
    return MeshCoreHandshake(self: self, device: device, clockSet: clockSet);
  }

  /// Protocol code from DEVICE_INFO, once [handshake] or [deviceQuery] ran.
  int? get firmwareCode => _firmwareCode;
  int? _firmwareCode;

  /// Throws [UnsupportedFirmware] unless the radio has [feature].
  ///
  /// Call before using a command that older firmware lacks.
  void requireFeature(MeshCoreFeature feature) {
    final code = _firmwareCode;
    if (code == null || !MeshCoreFirmware.supports(code, feature)) {
      throw UnsupportedFirmware(
        found: code ?? 0,
        needed: feature.minimumCode,
        feature: feature,
      );
    }
  }

  /// APP_START → SELF_INFO.
  Future<SelfInfoFrame> appStart() =>
      _expect<SelfInfoFrame>(MeshCoreCommands.appStart(appName));

  /// DEVICE_QUERY → DEVICE_INFO.
  Future<DeviceInfoFrame> deviceQuery() =>
      _expect<DeviceInfoFrame>(MeshCoreCommands.deviceQuery());

  /// Sets the radio's clock. Throws [MeshCoreException] if it refuses.
  Future<void> setTime(DateTime time) => _expect<OkFrame>(
    MeshCoreCommands.setDeviceTime(time.millisecondsSinceEpoch ~/ 1000),
  );

  /// Reads the radio's clock.
  Future<DateTime> getTime() async {
    final f = await _expect<CurrentTimeFrame>(MeshCoreCommands.getDeviceTime());
    return DateTime.fromMillisecondsSinceEpoch(f.unixSeconds * 1000);
  }

  /// Battery and storage.
  Future<BatteryFrame> battery() =>
      _expect<BatteryFrame>(MeshCoreCommands.getBattAndStorage());

  /// All contacts, or only those changed after [since].
  Future<ContactSync> getContacts({int? since}) async {
    final contacts = <ContactFrame>[];
    var total = 0;
    final result = await _send(
      MeshCoreCommands.getContacts(since: since),
      (frame, done) {
        switch (frame) {
          case ContactsStartFrame(total: final count):
            total = count;
            return true;
          case ContactFrame(fromNewAdvert: false):
            contacts.add(frame);
            return true;
          case EndOfContactsFrame(lastModified: final mark):
            done.complete(mark);
            return true;
          case ErrorFrame(code: final code):
            done.completeError(MeshCoreException(code, Cmd.getContacts));
            return true;
          default:
            return false;
        }
      },
      // Large contact lists take a while over Bluetooth.
      timeout: timeout * 6,
    );
    return ContactSync(
      contacts: contacts,
      total: total,
      lastModified: result! as int,
    );
  }

  /// One channel slot, or null if [index] is past the radio's last slot.
  Future<ChannelInfoFrame?> getChannel(int index) async {
    try {
      return await _expect<ChannelInfoFrame>(
        MeshCoreCommands.getChannel(index),
      );
    } on MeshCoreException catch (e) {
      if (e.code == MeshCoreErrorCode.notFound) return null;
      rethrow;
    }
  }

  /// Every channel slot up to [maxChannels] (from DEVICE_INFO).
  Future<List<ChannelInfoFrame>> getChannels(int maxChannels) async {
    final out = <ChannelInfoFrame>[];
    for (var i = 0; i < maxChannels; i++) {
      final c = await getChannel(i);
      if (c == null) break;
      out.add(c);
    }
    return out;
  }

  /// Stores a channel in slot [index].
  Future<void> setChannel(int index, String name, List<int> secret) =>
      _expect<OkFrame>(
        MeshCoreCommands.setChannel(index, name, secret),
        timeout: timeout * 2,
      );

  /// Sends a direct message. The returned [SentFrame.ackCode] matches the
  /// [SendConfirmedPush] that arrives when the recipient gets it.
  Future<SentFrame> sendText({
    required List<int> publicKey,
    required String text,
    DateTime? at,
    int attempt = 0,
    TextType type = TextType.plain,
  }) => _expect<SentFrame>(
    MeshCoreCommands.sendText(
      publicKey: publicKey,
      text: text,
      timestamp: _seconds(at),
      attempt: attempt,
      type: type,
    ),
  );

  /// Sends a message to channel slot [channel].
  Future<void> sendChannelText({
    required int channel,
    required String text,
    DateTime? at,
  }) async {
    // Firmware v1.18 replies OK; the docs describe SENT. Accept either.
    await _send(
      MeshCoreCommands.sendChannelText(
        channel: channel,
        text: text,
        timestamp: _seconds(at),
      ),
      (frame, done) {
        switch (frame) {
          case OkFrame() || SentFrame():
            done.complete(null);
            return true;
          case ErrorFrame(code: final code):
            done.completeError(MeshCoreException(code, Cmd.sendChannelText));
            return true;
          default:
            return false;
        }
      },
    );
  }

  /// Radio statistics: noise floor, last signal, airtime (protocol 8+).
  Future<RadioStatsFrame> radioStats() {
    requireFeature(MeshCoreFeature.stats);
    return _expect<RadioStatsFrame>(MeshCoreCommands.getStats(1));
  }

  /// Packet counters (protocol 8+).
  Future<PacketStatsFrame> packetStats() {
    requireFeature(MeshCoreFeature.stats);
    return _expect<PacketStatsFrame>(MeshCoreCommands.getStats(2));
  }

  /// Sends a trace along [path] and waits for it to come back.
  ///
  /// Throws [MeshCoreTimeout] if it doesn't return within the radio's
  /// estimate plus [extra].
  Future<TraceDataPush> trace(
    List<int> path, {
    int hashSize = 1,
    Duration extra = const Duration(seconds: 5),
    Random? random,
  }) async {
    final tag = (random ?? Random()).nextInt(0x7fffffff) + 1;
    final back = pushes
        .where((f) => f is TraceDataPush && f.tag == tag)
        .cast<TraceDataPush>()
        .first;
    final sent = await _expect<SentFrame>(
      MeshCoreCommands.sendTracePath(tag: tag, path: path, hashSize: hashSize),
    );
    final wait = Duration(milliseconds: sent.timeoutMs) + extra;
    return back.timeout(
      wait,
      onTimeout: () => throw const MeshCoreTimeout(Cmd.sendTracePath),
    );
  }

  /// Renames the radio (what others see in its adverts).
  Future<void> setName(String name) =>
      _expect<OkFrame>(MeshCoreCommands.setAdvertName(name));

  /// Changes frequency, bandwidth, spreading factor and coding rate.
  Future<void> setRadioParams({
    required double frequencyMHz,
    required double bandwidthKHz,
    required int spreadingFactor,
    required int codingRate,
  }) => _expect<OkFrame>(
    MeshCoreCommands.setRadioParams(
      frequencyMHz: frequencyMHz,
      bandwidthKHz: bandwidthKHz,
      spreadingFactor: spreadingFactor,
      codingRate: codingRate,
    ),
  );

  /// Sets transmit power in dBm.
  Future<void> setTxPower(int dbm) =>
      _expect<OkFrame>(MeshCoreCommands.setTxPower(dbm));

  /// Sets the position the radio advertises.
  Future<void> setPosition(double latitude, double longitude) =>
      _expect<OkFrame>(MeshCoreCommands.setAdvertPosition(latitude, longitude));

  /// Contact auto-add, telemetry sharing, advert position, extra acks.
  Future<void> setOtherParams({
    required bool manualAddContacts,
    required int telemetryMode,
    required int advertLocationPolicy,
    required int multiAcks,
  }) => _expect<OkFrame>(
    MeshCoreCommands.setOtherParams(
      manualAddContacts: manualAddContacts,
      telemetryMode: telemetryMode,
      advertLocationPolicy: advertLocationPolicy,
      multiAcks: multiAcks,
    ),
  );

  /// Sets the hop ID size (`0` is one byte, up to `2`, three bytes).
  Future<void> setPathHashMode(int mode) {
    requireFeature(MeshCoreFeature.pathHashMode);
    return _expect<OkFrame>(MeshCoreCommands.setPathHashMode(mode));
  }

  /// Restarts the radio. It doesn't reply; the link drops and reconnects.
  Future<void> reboot() async {
    attach();
    final cmd = MeshCoreCommands.reboot();
    await link.send(link.deliversFrames ? cmd : wrapStreamFrame(cmd));
  }

  /// Runs a command on the companion radio itself (protocol 14+).
  Future<String> runCli(String command) async {
    requireFeature(MeshCoreFeature.companionCli);
    final r = await _expect<CliReplyFrame>(MeshCoreCommands.runCli(command));
    return r.text;
  }

  /// Logs in to a repeater or room server. Waits for its answer.
  Future<LoginResultPush> login(
    List<int> publicKey,
    String password, {
    Duration extra = const Duration(seconds: 10),
  }) => _askServer<LoginResultPush>(
    publicKey,
    MeshCoreCommands.sendLogin(publicKey, password),
    extra,
  );

  /// Asks a repeater or room server for its status.
  Future<RepeaterStatusPush> serverStatus(
    List<int> publicKey, {
    Duration extra = const Duration(seconds: 10),
  }) => _askServer<RepeaterStatusPush>(
    publicKey,
    MeshCoreCommands.sendStatusRequest(publicKey),
    extra,
  );

  /// Runs [command] on a repeater or room server you're logged in to and
  /// returns its reply.
  Future<String> serverCommand(
    List<int> publicKey,
    String command, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final prefix = publicKey.sublist(0, MeshCoreLimits.keyPrefix);
    final reply = messages
        .where(
          (f) =>
              f is ContactMessageFrame &&
              f.textType == TextType.cliData &&
              _samePrefix(f.keyPrefix, prefix),
        )
        .cast<ContactMessageFrame>()
        .first;
    await sendText(publicKey: publicKey, text: command, type: TextType.cliData);
    final m = await reply.timeout(
      timeout,
      onTimeout: () => throw const MeshCoreTimeout(Cmd.sendText),
    );
    return m.text;
  }

  Future<T> _askServer<T extends MeshCoreFrame>(
    List<int> publicKey,
    Uint8List command,
    Duration extra,
  ) async {
    final prefix = publicKey.sublist(0, MeshCoreLimits.keyPrefix);
    final answer = pushes
        .where((f) => f is T && _samePrefix(_prefixOf(f), prefix))
        .cast<T>()
        .first;
    final sent = await _expect<SentFrame>(command);
    return answer.timeout(
      Duration(milliseconds: sent.timeoutMs) + extra,
      onTimeout: () => throw MeshCoreTimeout(command.first),
    );
  }

  static List<int> _prefixOf(MeshCoreFrame f) => switch (f) {
    LoginResultPush(:final keyPrefix) => keyPrefix,
    RepeaterStatusPush(:final keyPrefix) => keyPrefix,
    _ => const [],
  };

  static bool _samePrefix(List<int> a, List<int> b) {
    if (a.length < b.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Forgets the route to a contact so the next message floods.
  /// Adds or updates a contact on the radio; see
  /// [MeshCoreCommands.addUpdateContact].
  Future<void> addContact({
    required List<int> publicKey,
    required int type,
    required String name,
    int flags = 0,
    int lastAdvert = 0,
    double? latitude,
    double? longitude,
  }) => _expect<OkFrame>(
    MeshCoreCommands.addUpdateContact(
      publicKey: publicKey,
      type: type,
      name: name,
      flags: flags,
      lastAdvert: lastAdvert,
      latitude: latitude,
      longitude: longitude,
    ),
  );

  /// Removes a contact from the radio.
  Future<void> removeContact(List<int> publicKey) =>
      _expect<OkFrame>(MeshCoreCommands.removeContact(publicKey));

  /// Sends `RESET_PATH` for a contact.
  Future<void> resetPath(List<int> publicKey) =>
      _expect<OkFrame>(MeshCoreCommands.resetPath(publicKey));

  /// Sends this radio's advert, flooded or to neighbours only.
  Future<void> sendAdvert({bool flood = false}) =>
      _expect<OkFrame>(MeshCoreCommands.sendSelfAdvert(flood: flood));

  /// Fetches one queued message; null when none are left.
  Future<MeshCoreFrame?> syncNext() async {
    final result = await _send(MeshCoreCommands.syncNextMessage(), (
      frame,
      done,
    ) {
      switch (frame) {
        case ContactMessageFrame() ||
            ChannelMessageFrame() ||
            ChannelDataFrame():
          done.complete(frame);
          return true;
        case NoMoreMessagesFrame():
          done.complete(null);
          return true;
        case ErrorFrame(code: final code):
          done.completeError(MeshCoreException(code, Cmd.syncNextMessage));
          return true;
        default:
          return false;
      }
    });
    return result as MeshCoreFrame?;
  }

  /// Fetches every queued message and emits each on [messages].
  ///
  /// Overlapping calls are merged; returns how many were fetched.
  Future<int> fetchMessages({int limit = 500}) async {
    if (_fetching) {
      _fetchAgain = true;
      return 0;
    }
    _fetching = true;
    var count = 0;
    try {
      do {
        _fetchAgain = false;
        while (count < limit) {
          final m = await syncNext();
          if (m == null) break;
          count++;
          if (!_messages.isClosed) _messages.add(m);
        }
      } while (_fetchAgain && count < limit);
    } finally {
      _fetching = false;
    }
    return count;
  }

  int _seconds(DateTime? at) => (at ?? _clock()).millisecondsSinceEpoch ~/ 1000;

  /// Sends [command] and waits for a reply of type [T] (or ERR).
  Future<T> _expect<T extends MeshCoreFrame>(
    Uint8List command, {
    Duration? timeout,
  }) async {
    final result = await _send(command, (frame, done) {
      if (frame is T) {
        done.complete(frame);
        return true;
      }
      if (frame is ErrorFrame) {
        done.completeError(MeshCoreException(frame.code, command.first));
        return true;
      }
      return false;
    }, timeout: timeout);
    return result! as T;
  }

  Future<Object?> _send(
    Uint8List command,
    _Collector collect, {
    Duration? timeout,
  }) {
    attach();
    final pending = _Pending(command, collect, timeout ?? this.timeout);
    _queue.add(pending);
    _pump();
    return pending.done.future;
  }

  void _pump() {
    if (_current != null || _queue.isEmpty) return;
    final next = _queue.removeFirst();
    _current = next;
    next.timer = Timer(next.timeout, () {
      if (_current != next) return;
      _log?.add(_source, 'no reply to command ${next.code}');
      _finish(next, error: MeshCoreTimeout(next.code));
    });
    final bytes = link.deliversFrames
        ? next.command
        : wrapStreamFrame(next.command);
    link.send(bytes).catchError((Object error) {
      _finish(next, error: error);
    });
  }

  void _finish(_Pending p, {Object? error}) {
    p.timer?.cancel();
    if (error != null && !p.done.isCompleted) p.done.completeError(error);
    if (_current == p) _current = null;
    _pump();
  }

  void _onFrame(Uint8List data) {
    final frame = decodeFrame(data);
    if (frame is MalformedFrame) {
      _log?.add(_source, 'bad frame ${frame.code}: ${frame.reason}');
    }
    final current = _current;
    if (!frame.isPush && current != null) {
      if (current.collect(frame, current.done)) {
        if (current.done.isCompleted) _finish(current);
        return;
      }
    }
    if (frame is MessagesWaitingPush && autoFetchMessages) {
      unawaited(
        fetchMessages().catchError((Object e) {
          _log?.add(_source, 'fetching messages failed: $e');
          return 0;
        }),
      );
    }
    if (!_pushes.isClosed) _pushes.add(frame);
  }

  void _failAll(Object error) {
    final all = [?_current, ..._queue];
    _queue.clear();
    _current = null;
    for (final p in all) {
      p.timer?.cancel();
      if (!p.done.isCompleted) p.done.completeError(error);
    }
  }

  /// Closes the streams. The session can't be used afterwards.
  Future<void> dispose() async {
    await detach();
    await _pushes.close();
    await _messages.close();
  }
}
