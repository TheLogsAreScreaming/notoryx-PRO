import 'package:flutter/material.dart';

import '../mesh/model.dart';
import 'common.dart';

/// Everything known about how one message travelled: route, hops, signal,
/// internet relay, times, delivery and tries.
class MessagePathCard extends StatelessWidget {
  const MessagePathCard({super.key, required this.message});

  final Message message;

  /// Shows the card as a bottom sheet.
  static Future<void> show(BuildContext context, Message message) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => MessagePathCard(message: message),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = message;
    final p = m.path;
    final (_, deliveryText) = deliveryLook(context, m.delivery);
    final signal = [
      if (p.snr != null) l.pathSnr(p.snr!.toStringAsFixed(1)),
      if (p.rssi != null) l.pathRssi(p.rssi!),
    ].join(' · ');
    final rows = <(String, String)>[
      (l.pathCardMesh, protocolName(context, m.protocol)),
      if (!m.outgoing)
        (l.pathCardSender, m.senderName ?? m.from?.short ?? l.notReported),
      if (!m.outgoing) ...[
        (
          l.pathCardRoute,
          switch (p.route) {
            RouteKind.direct => l.pathRouteDirect,
            RouteKind.flood => l.pathRouteFlood,
            RouteKind.unknown => l.pathRouteUnknown,
          },
        ),
        (l.pathCardHops, p.hops == null ? l.notReported : l.pathHops(p.hops!)),
        (l.pathCardSignal, signal.isEmpty ? l.notReported : signal),
        (l.pathCardInternet, p.viaMqtt ? l.yes : l.no),
      ],
      (l.pathCardSent, _time(m.sentAt)),
      if (!m.outgoing) (l.pathCardReceived, _time(m.receivedAt)),
      if (m.outgoing) ...[
        (l.pathCardDelivery, deliveryText),
        (l.pathCardAttempts, '${m.attempts}'),
        if (m.delivery case Delivered(:final roundTrip?))
          (
            l.pathCardRoundTrip,
            l.pathCardRoundTripValue(
              (roundTrip.inMilliseconds / 1000).toStringAsFixed(1),
            ),
          ),
      ],
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.pathCardTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
