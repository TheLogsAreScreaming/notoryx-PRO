import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mesh/mecp.dart';
import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// Repeats an MECP distress beacon on one conversation until stopped.
///
/// Only ever started by a person. It lives in memory, so it can't come back
/// by itself after the app restarts, and it ends on its own after [lasts].
class DistressBeacon extends ChangeNotifier {
  DistressBeacon({
    required this.conversation,
    required Future<void> Function(String text) send,
    required Future<(double, double)?> Function() position,
    required Stream<StoredMessage> incoming,
    required this.maxBytes,
    Duration every = minEvery,
    Duration lasts = const Duration(hours: 1),
    this.note = '',
    this.drill = false,
  }) : _send = send,
       _position = position,
       _incoming = incoming,
       every = every < minEvery ? minEvery : every,
       lasts = lasts > maxLasts ? maxLasts : lasts;

  /// The shortest allowed gap between beacons, so one can't hog a channel.
  static const minEvery = Duration(minutes: 5);

  /// The longest a beacon may run before it needs starting again.
  static const maxLasts = Duration(hours: 4);

  final Conversation conversation;
  final Future<void> Function(String text) _send;
  final Future<(double, double)?> Function() _position;
  final Stream<StoredMessage> _incoming;

  /// The largest message the radio can send.
  final int maxBytes;

  /// Gap between beacons. Doubles once if someone acknowledges (MECP B02).
  Duration every;

  /// How long it runs.
  final Duration lasts;

  /// Added to each beacon.
  final String note;

  /// Marked as a practice (D01), so nobody treats it as real.
  final bool drill;

  /// Beacons the radio accepted.
  int sent = 0;

  /// Beacons that couldn't be sent.
  int failed = 0;

  /// Whether someone acknowledged it.
  bool acknowledged = false;

  /// Whether it is still running.
  bool get active => _active;
  bool _active = false;

  Timer? _repeat;
  Timer? _end;
  StreamSubscription<StoredMessage>? _sub;

  /// The beacon's text for a position.
  String textFor((double, double)? at) {
    final codes = ['B01', if (drill) 'D01', if (at != null) 'P05'];
    var free = [
      if (at != null) '${at.$1.toStringAsFixed(4)},${at.$2.toStringAsFixed(4)}',
      if (note.trim().isNotEmpty) note.trim(),
    ].join(' ');
    var m = MecpMessage(
      severity: MecpSeverity.mayday,
      codes: codes,
      freetext: free,
    );
    final limit = maxBytes < MecpMessage.maxBytes
        ? maxBytes
        : MecpMessage.maxBytes;
    // Position matters more than the note if both can't fit.
    while (m.bytes > limit && free.isNotEmpty) {
      free = free.substring(0, free.length - 1).trimRight();
      m = MecpMessage(
        severity: MecpSeverity.mayday,
        codes: codes,
        freetext: free,
      );
    }
    return m.encode();
  }

  /// Sends the first beacon now and schedules the rest.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _sub = _incoming.listen(_onMessage);
    _end = Timer(lasts, stop);
    _schedule();
    notifyListeners();
    await _beacon();
  }

  void _schedule() {
    _repeat?.cancel();
    _repeat = Timer.periodic(every, (_) => unawaited(_beacon()));
  }

  void _onMessage(StoredMessage s) {
    final m = s.message;
    if (acknowledged || m.outgoing || m.conversation != conversation) return;
    if (!(MecpMessage.tryParse(m.text)?.codes.contains('B02') ?? false)) {
      return;
    }
    acknowledged = true;
    every *= 2;
    _schedule();
    notifyListeners();
  }

  Future<void> _beacon() async {
    if (!_active) return;
    try {
      await _send(textFor(await _position()));
      sent++;
    } on Object catch (e) {
      failed++;
      debugPrint('beacon: $e');
    }
    if (_active) notifyListeners();
  }

  /// Stops the beacon. With [imOk], also tells the mesh to stand down
  /// (MECP B03).
  Future<void> stop({bool imOk = false}) async {
    if (!_active) return;
    _active = false;
    _repeat?.cancel();
    _end?.cancel();
    unawaited(_sub?.cancel());
    notifyListeners();
    if (!imOk) return;
    try {
      await _send(
        MecpMessage(
          severity: MecpSeverity.routine,
          codes: const ['B03'],
        ).encode(),
      );
    } on Object catch (e) {
      debugPrint('beacon cancel: $e');
    }
  }
}
