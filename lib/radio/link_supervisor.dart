import 'dart:async';

import 'connection_log.dart';
import 'radio_link.dart';

/// What a [LinkSupervisor] is doing.
enum SupervisorPhase {
  /// Not started, or stopped by the user.
  stopped,

  /// Opening the link for the first time.
  connecting,

  /// Connected and set up.
  connected,

  /// Lost the link (or couldn't open it); waiting to try again.
  reconnecting,

  /// Gave up because of an error retrying can't fix, such as old firmware.
  failed,
}

/// A snapshot of a [LinkSupervisor].
class SupervisorStatus {
  const SupervisorStatus(
    this.phase, {
    this.attempt = 0,
    this.nextAttempt,
    this.lastError,
  });

  final SupervisorPhase phase;

  /// Reconnect attempts since the last successful connection.
  final int attempt;

  /// When the next attempt is due, while [phase] is reconnecting.
  final DateTime? nextAttempt;

  /// The most recent failure, if any.
  final Object? lastError;

  @override
  String toString() => 'SupervisorStatus($phase, attempt $attempt)';
}

/// Keeps a [RadioLink] connected, on any transport.
///
/// After a drop (Bluetooth out of range or turned off, USB unplugged, Wi-Fi
/// lost) it reopens the link after each delay in [delays], repeating the
/// last one until it succeeds or [stop] is called. [onConnected] runs after
/// every successful open, for protocol set-up; if it throws, that counts as
/// a failed attempt, unless [isFatal] says retrying can't help.
class LinkSupervisor {
  LinkSupervisor(
    this.link, {
    this.delays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
    this.onConnected,
    bool Function(Object error)? isFatal,
    ConnectionLog? log,
    DateTime Function()? clock,
  }) : assert(delays.isNotEmpty),
       _isFatal = isFatal ?? ((_) => false),
       _log = log,
       _clock = clock ?? DateTime.now;

  /// The link kept open.
  final RadioLink link;

  /// Waits between attempts; the last one repeats.
  final List<Duration> delays;

  /// Protocol set-up after each open, such as a handshake.
  final Future<void> Function(RadioLink link)? onConnected;

  final bool Function(Object error) _isFatal;
  final ConnectionLog? _log;
  final DateTime Function() _clock;
  final _status = StreamController<SupervisorStatus>.broadcast();
  SupervisorStatus _current = const SupervisorStatus(SupervisorPhase.stopped);
  StreamSubscription<LinkState>? _linkStates;
  Timer? _timer;
  bool _wanted = false;
  bool _attempting = false;
  int _attempt = 0;

  /// Current status.
  SupervisorStatus get status => _current;

  /// Status changes.
  Stream<SupervisorStatus> get statuses => _status.stream;

  String get _source => 'Reconnect ${link.label}';

  void _set(SupervisorStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Connects and keeps the link up. Completes after the first attempt,
  /// whether or not it succeeded; later attempts happen in the background.
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    _attempt = 0;
    _linkStates ??= link.states.listen(_onLinkState);
    _set(const SupervisorStatus(SupervisorPhase.connecting));
    await _tryOnce();
  }

  /// Tries again now instead of waiting.
  Future<void> tryNow() async {
    if (!_wanted || _attempting) return;
    if (_current.phase == SupervisorPhase.connected) return;
    _timer?.cancel();
    _log?.add(_source, 'trying now');
    await _tryOnce();
  }

  /// Disconnects and stops reconnecting (the user chose to disconnect).
  Future<void> stop() async {
    _wanted = false;
    _timer?.cancel();
    _timer = null;
    await _linkStates?.cancel();
    _linkStates = null;
    await link.close();
    _set(const SupervisorStatus(SupervisorPhase.stopped));
  }

  /// Stops and releases the status stream.
  Future<void> dispose() async {
    await stop();
    await _status.close();
  }

  void _onLinkState(LinkState state) {
    if (state != LinkState.disconnected || !_wanted || _attempting) return;
    if (_current.phase != SupervisorPhase.connected) return;
    _log?.add(_source, 'link dropped');
    _attempt = 0;
    _schedule(null);
  }

  Future<void> _tryOnce() async {
    if (!_wanted || _attempting) return;
    _attempting = true;
    try {
      if (_attempt > 0) _log?.add(_source, 'attempt $_attempt');
      await link.open();
      if (onConnected != null) await onConnected!(link);
      if (!_wanted) return;
      if (_attempt > 0) _log?.add(_source, 'reconnected');
      _attempt = 0;
      _set(const SupervisorStatus(SupervisorPhase.connected));
    } on Object catch (error) {
      if (!_wanted) return;
      try {
        await link.close();
      } on Object catch (_) {
        // Already closed.
      }
      if (_isFatal(error)) {
        _log?.add(_source, 'stopped: $error');
        _wanted = false;
        _set(SupervisorStatus(SupervisorPhase.failed, lastError: error));
        return;
      }
      _schedule(error);
    } finally {
      _attempting = false;
    }
  }

  void _schedule(Object? error) {
    final delay = delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    final due = _clock().add(delay);
    _log?.add(_source, 'next try in ${delay.inMilliseconds} ms');
    _set(
      SupervisorStatus(
        SupervisorPhase.reconnecting,
        attempt: _attempt,
        nextAttempt: due,
        lastError: error,
      ),
    );
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_tryOnce()));
  }
}
