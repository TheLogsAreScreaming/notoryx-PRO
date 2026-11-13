import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/mesh/mesh.dart';
import 'package:notoryx_pro/mesh/trace_card.dart';
import 'package:notoryx_pro/radio/radio.dart';
import 'package:notoryx_pro/ui/trace_card.dart';

final card = TraceCardData(
  protocol: RadioProtocol.meshcore,
  senderName: 'Base',
  targetName: 'Ann',
  time: DateTime(2026, 11, 13, 9, 30),
  roundTrip: const Duration(milliseconds: 3400),
  out: const [
    TraceStop('Base', position: GeoPoint(45.5, -122.6)),
    TraceStop('Peak', position: GeoPoint(45.55, -122.5), snr: 5),
    TraceStop('b2', snr: -3),
  ],
  back: const [
    TraceStop('b2'),
    TraceStop('Peak', position: GeoPoint(45.55, -122.5), snr: -6),
    TraceStop('Base', position: GeoPoint(45.5, -122.6), snr: 4),
  ],
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('the card shows the trace, its map and every hop', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(TraceCardScreen(card: card)));
    await tester.pump();
    expect(find.text('Base → Ann'), findsOneWidget);
    expect(find.textContaining('round trip 3.4 s'), findsOneWidget);
    expect(find.textContaining('2 hops'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Map of the trace: 2 of 3 radios have a known position',
      ),
      findsOneWidget,
    );
    expect(
      find.text("1 radio has no known position and isn't drawn."),
      findsOneWidget,
    );
    expect(find.text('SNR 5.0 dB'), findsOneWidget);
    expect(find.text('SNR -6.0 dB'), findsOneWidget);
    expect(find.byTooltip('Share as image'), findsOneWidget);
    expect(find.byTooltip('Share as text'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('the text version lists both ways', (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    final text = traceCardText(l, const DefaultMaterialLocalizations(), card);
    expect(text.split('\n'), [
      'NOTORYX PRO trace · MeshCore',
      'Base → Ann',
      contains('2 hops · round trip 3.4 s'),
      'Out: Base → Peak (SNR 5.0 dB) → b2 (SNR -3.0 dB)',
      'Back: b2 → Peak (SNR -6.0 dB) → Base (SNR 4.0 dB)',
    ]);
  });

  testWidgets('no positions: a note instead of an empty map', (tester) async {
    await tester.pumpWidget(
      _app(
        TraceCardScreen(
          card: TraceCardData(
            protocol: RadioProtocol.meshtastic,
            senderName: 'Base',
            targetName: 'Sam',
            time: DateTime(2026),
            out: const [TraceStop('Base'), TraceStop('Sam', snr: 1)],
            back: const [],
          ),
        ),
      ),
    );
    expect(find.textContaining("nothing to draw"), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });
}
