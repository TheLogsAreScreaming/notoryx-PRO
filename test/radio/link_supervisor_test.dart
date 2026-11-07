import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/radio/connection_log.dart';
import 'package:notoryx_pro/radio/link_supervisor.dart';
import 'package:notoryx_pro/radio/radio_link.dart';

/// A link whose opens fail while [available] is false, like a radio that
/// is unplugged, out of range or switched off.
class FlakyLink extends BaseRadioLink {
  FlakyLink(this.kind);

  @override
  final LinkKind kind;
  bool available = true;
  int opens = 0;

  @override
  RadioProtocol get protocol => RadioProtocol.meshcore;

  @override
  String get label => 'flaky ${kind.label}';

  @override
  bool get deliversFrames => kind == LinkKind.bluetooth;

  @override
  Future<void> open() async {
    opens++;
    setState(LinkState.connecting);
    if (!available) {
      setState(LinkState.disconnected);
      throw const LinkException('radio not reachable');
    }
    setState(LinkState.connected);
  }

  /// The radio goes away.
  void drop() {
    available = false;
    setState(LinkState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async => requireConnected();

  @override
  Future<void> close() async {
    if (state == LinkState.connected) setState(LinkState.disconnected);
  }
}

const fast = [Duration(milliseconds: 10), Duration(milliseconds: 30)];

Future<void> waitFor(bool Function() done, {int ms = 2000}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsedMilliseconds > ms) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  for (final kind in LinkKind.values) {
    test('${kind.label}: recovers after the radio comes back', () async {
      final link = FlakyLink(kind);
      final log = ConnectionLog();
      final s = LinkSupervisor(link, delays: fast, log: log);
      await s.start();
      expect(s.status.phase, SupervisorPhase.connected);

      link.drop();
      await waitFor(() => link.opens >= 3);
      expect(s.status.phase, SupervisorPhase.reconnecting);
      expect(s.status.attempt, greaterThanOrEqualTo(2));

      link.available = true;
      await waitFor(() => s.status.phase == SupervisorPhase.connected);
      expect(log.export(), contains('link dropped'));
      expect(log.export(), contains('reconnected'));
      await s.dispose();
    });
  }

  test('keeps retrying at the last delay', () async {
    final link = FlakyLink(LinkKind.tcp)..available = false;
    final s = LinkSupervisor(link, delays: fast);
    await s.start();
    expect(s.status.phase, SupervisorPhase.reconnecting);
    await waitFor(() => link.opens >= 5);
    await s.dispose();
  });

  test('tryNow skips the wait', () async {
    final link = FlakyLink(LinkKind.usb)..available = false;
    final s = LinkSupervisor(link, delays: const [Duration(minutes: 5)]);
    await s.start();
    expect(link.opens, 1);
    link.available = true;
    await s.tryNow();
    expect(link.opens, 2);
    expect(s.status.phase, SupervisorPhase.connected);
    await s.dispose();
  });

  test('stop disconnects and never reconnects', () async {
    final link = FlakyLink(LinkKind.bluetooth);
    final s = LinkSupervisor(link, delays: fast);
    await s.start();
    await s.stop();
    expect(link.state, LinkState.disconnected);
    expect(s.status.phase, SupervisorPhase.stopped);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(link.opens, 1);
    await s.dispose();
  });

  test('set-up failures retry; fatal ones stop', () async {
    final link = FlakyLink(LinkKind.bluetooth);
    var setups = 0;
    final s = LinkSupervisor(
      link,
      delays: fast,
      onConnected: (_) async {
        setups++;
        if (setups == 1) throw StateError('handshake timed out');
        if (setups == 2) throw const FormatException('firmware too old');
      },
      isFatal: (e) => e is FormatException,
    );
    await s.start();
    expect(s.status.phase, SupervisorPhase.reconnecting);
    await waitFor(() => s.status.phase == SupervisorPhase.failed);
    expect(s.status.lastError, isA<FormatException>());
    expect(link.state, LinkState.disconnected);
    final opens = link.opens;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(link.opens, opens, reason: 'no retries after a fatal error');
    await s.dispose();
  });

  test('reports each phase on the status stream', () async {
    final link = FlakyLink(LinkKind.tcp);
    final s = LinkSupervisor(link, delays: fast);
    final phases = <SupervisorPhase>[];
    s.statuses.listen((st) => phases.add(st.phase));
    await s.start();
    link.drop();
    await waitFor(() => link.opens >= 2);
    link.available = true;
    await waitFor(() => s.status.phase == SupervisorPhase.connected);
    await s.stop();
    await Future<void>.delayed(Duration.zero);
    expect(phases.first, SupervisorPhase.connecting);
    expect(phases, contains(SupervisorPhase.reconnecting));
    expect(phases.last, SupervisorPhase.stopped);
    await s.dispose();
  });
}
