import 'dart:async';
import 'dart:typed_data';

/// The two mesh protocols NOTORYX PRO speaks.
enum RadioProtocol {
  meshcore('MeshCore'),
  meshtastic('Meshtastic');

  const RadioProtocol(this.label);

  /// Name shown to people.
  final String label;
}

/// How the phone or computer reaches the radio.
enum LinkKind {
  bluetooth('Bluetooth'),
  usb('USB'),
  tcp('Wi-Fi');

  const LinkKind(this.label);

  /// Name shown to people.
  final String label;
}

/// Where a [RadioLink] is in its life.
enum LinkState { idle, connecting, connected, disconnected }

/// A failure while opening or using a [RadioLink].
class LinkException implements Exception {
  const LinkException(this.message, [this.cause]);

  /// What went wrong, in words fit to show people.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'LinkException: $message'
      : 'LinkException: $message ($cause)';
}

/// A byte pipe to one radio, independent of protocol.
///
/// Bluetooth links deliver whole protocol frames ([deliversFrames] is true);
/// USB serial and TCP links deliver a raw byte stream that the protocol
/// layer must split into frames itself.
abstract class RadioLink {
  /// The transport this link uses.
  LinkKind get kind;

  /// The protocol spoken over this link.
  RadioProtocol get protocol;

  /// Human-readable address, such as a device name or `host:port`.
  String get label;

  /// Whether each event on [incoming] is exactly one protocol frame.
  bool get deliversFrames;

  /// The current state.
  LinkState get state;

  /// State changes, starting after the call that subscribes.
  Stream<LinkState> get states;

  /// Bytes (or frames, see [deliversFrames]) received from the radio.
  Stream<Uint8List> get incoming;

  /// Connects to the radio. Throws [LinkException] if it can't.
  Future<void> open();

  /// Sends bytes (or one frame, see [deliversFrames]) to the radio.
  Future<void> send(Uint8List data);

  /// Disconnects. Safe to call more than once.
  Future<void> close();
}

/// Shared state handling for [RadioLink] implementations.
abstract class BaseRadioLink implements RadioLink {
  final StreamController<LinkState> _states =
      StreamController<LinkState>.broadcast();
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  LinkState _state = LinkState.idle;

  @override
  LinkState get state => _state;

  @override
  Stream<LinkState> get states => _states.stream;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  /// Moves to [next] and tells listeners, if it's a change.
  void setState(LinkState next) {
    if (next == _state) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Passes received bytes to listeners.
  void deliver(Uint8List data) {
    if (!_incoming.isClosed && data.isNotEmpty) _incoming.add(data);
  }

  /// Throws unless the link is connected.
  void requireConnected() {
    if (_state != LinkState.connected) {
      throw LinkException('$label is not connected');
    }
  }
}
