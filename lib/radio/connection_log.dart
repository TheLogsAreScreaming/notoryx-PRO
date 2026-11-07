import 'dart:collection';
import 'dart:typed_data';

/// One line of the [ConnectionLog].
class LogEntry {
  const LogEntry(this.time, this.source, this.message);

  /// When it happened.
  final DateTime time;

  /// Which link or part of the app wrote it, such as `BLE MeshCore-Alpha`.
  final String source;

  /// What happened. Never contains message text, keys or passwords.
  final String message;

  @override
  String toString() {
    final t = time.toIso8601String().substring(11, 23);
    return '$t  $source  $message';
  }
}

/// A short, privacy-safe history of connection events.
///
/// People paste this log into bug reports, so it records only events and
/// byte counts: payload bytes are summarised by [describeBytes], never
/// written out, and IP addresses are shortened by [redactHost].
class ConnectionLog {
  ConnectionLog({this.capacity = 300, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The most lines kept; older lines are dropped first.
  final int capacity;
  final DateTime Function() _clock;
  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();

  /// Lines from oldest to newest.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Adds a line.
  void add(String source, String message) {
    _entries.addLast(LogEntry(_clock(), source, message));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  /// Removes every line.
  void clear() => _entries.clear();

  /// The whole log as text, ready to copy.
  String export() => _entries.map((e) => e.toString()).join('\n');

  /// A payload summary that never includes the bytes themselves.
  static String describeBytes(Uint8List data) {
    if (data.isEmpty) return '0 bytes';
    final first = data.first.toRadixString(16).padLeft(2, '0');
    return '${data.length} bytes (type 0x$first)';
  }

  /// Hides the last part of an IPv4 address: `192.168.1.40` → `192.168.1.x`.
  ///
  /// Host names are left alone.
  static String redactHost(String host) {
    final parts = host.split('.');
    final isIpv4 =
        parts.length == 4 && parts.every((p) => int.tryParse(p) != null);
    if (!isIpv4) return host;
    return '${parts.take(3).join('.')}.x';
  }
}
