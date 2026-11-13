import '../radio/radio_link.dart';
import 'diagnostics.dart';
import 'model.dart';

/// One stop on a trace drawn on a card: a radio, with where it is when
/// known and the SNR at which it heard the packet.
class TraceStop {
  const TraceStop(this.label, {this.position, this.snr});

  final String label;
  final GeoPoint? position;

  /// SNR in dB as this stop heard the packet; null for the sender and for
  /// hops that didn't report it.
  final double? snr;
}

/// Everything a shareable trace card shows.
class TraceCardData {
  const TraceCardData({
    required this.protocol,
    required this.senderName,
    required this.targetName,
    required this.time,
    required this.out,
    required this.back,
    this.roundTrip,
  });

  /// Which mesh ran the trace.
  final RadioProtocol protocol;
  final String senderName;
  final String targetName;
  final DateTime time;
  final Duration? roundTrip;

  /// From the sender out, the sender first.
  final List<TraceStop> out;

  /// From the turning point back, the turning point first; empty when the
  /// mesh didn't report the way back.
  final List<TraceStop> back;

  /// Hops between the sender and the turning point.
  int get hopsOut => out.length - 1;

  /// The stops with a position, in travel order: out, then back.
  List<GeoPoint> get outLine => [
    for (final s in out)
      if (s.position != null) s.position!,
  ];
  List<GeoPoint> get backLine => [
    for (final s in back)
      if (s.position != null) s.position!,
  ];

  /// Distinct stops and how many of them have a position.
  (int placed, int total) get placedCount {
    final all = <String>{};
    final placed = <String>{};
    for (final s in [...out, ...back]) {
      all.add(s.label);
      if (s.position != null) placed.add(s.label);
    }
    return (placed.length, all.length);
  }

  /// Builds a card from a trace.
  ///
  /// [sender] is our radio, with its position if known. [known] are the
  /// radio's nodes: a hop without its [TraceHop.node] (saved traces keep
  /// only names) is placed when exactly one known node has its name, and a
  /// hop named like the sender is the sender.
  factory TraceCardData.from({
    required TraceResult result,
    required RadioProtocol protocol,
    required String senderName,
    GeoPoint? senderPosition,
    required String targetName,
    Iterable<Node> known = const [],
  }) {
    final byName = <String, List<Node>>{};
    for (final n in known) {
      byName.putIfAbsent(n.displayName, () => []).add(n);
    }
    GeoPoint? where(TraceHop h) {
      if (h.node?.position case final p?) return p;
      if (h.label == senderName) return senderPosition;
      final same = byName[h.label];
      return same != null && same.length == 1 ? same.single.position : null;
    }

    TraceStop stop(TraceHop h) =>
        TraceStop(h.label, position: where(h), snr: h.snr);
    final out = [
      TraceStop(senderName, position: senderPosition),
      for (final h in result.towards) stop(h),
    ];
    return TraceCardData(
      protocol: protocol,
      senderName: senderName,
      targetName: targetName,
      time: result.time,
      roundTrip: result.roundTrip,
      out: out,
      back: result.back.isEmpty
          ? const []
          : [
              TraceStop(out.last.label, position: out.last.position),
              for (final h in result.back) stop(h),
            ],
    );
  }
}
