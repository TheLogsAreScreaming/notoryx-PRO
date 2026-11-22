// SARNEG screens block screenshots while they show, and only then.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';
import 'package:notoryx_pro/ui/sarneg/no_screenshots.dart';
import 'package:notoryx_pro/ui/sarneg/sarneg.dart';
import 'package:notoryx_pro/ui/sarneg/sarneg_ui.dart';

final DateTime t0 = DateTime(2026, 11, 21, 9);

/// Records every call the guard makes.
class _FakeBlocker implements ScreenCaptureBlocker {
  final calls = <bool>[];

  bool get blocked => calls.isNotEmpty && calls.last;

  @override
  Future<void> setBlocked(bool blocked) async => calls.add(blocked);
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

/// A plain screen that can open the SARNEG screen or the composer sheet.
class _Home extends StatelessWidget {
  const _Home({this.received});

  final String? received;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const SarnegScreen()),
          ),
          child: const Text('open setup'),
        ),
        TextButton(
          onPressed: () => showSarnegComposeSheet(context),
          child: const Text('open sheet'),
        ),
        if (received != null) SarnegDecodeLine(text: received!, at: t0),
      ],
    ),
  );
}

void main() {
  late _FakeBlocker blocker;

  setUp(() {
    blocker = _FakeBlocker();
    screenCaptureGuard.blocker = blocker;
    SarnegKeys.instance = SarnegKeys(
      storage: MemorySarnegStorage(
        jsonEncode(SarnegKeySet(word: 'BLACKHORSE').toJson()),
      ),
      clock: () => t0,
    );
  });

  test('the block stays on until the last holder lets go', () {
    final guard = ScreenCaptureGuard(blocker);
    guard
      ..acquire()
      ..acquire();
    expect(blocker.calls, [true]);
    guard.release();
    expect(guard.blocked, isTrue);
    expect(blocker.calls, [true]);
    guard.release();
    expect(blocker.calls, [true, false]);
    guard.release(); // extra release is ignored
    expect(blocker.calls, [true, false]);
  });

  testWidgets('the code word screen blocks screenshots while open', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Home()));
    expect(blocker.calls, isEmpty);
    await tester.tap(find.text('open setup'));
    await tester.pumpAndSettle();
    expect(blocker.blocked, isTrue);
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(blocker.blocked, isTrue, reason: 'share QR is over the screen');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(blocker.calls, [true, false]);
  });

  testWidgets('the composer sheet blocks screenshots while open', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Home()));
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(blocker.blocked, isTrue);
    await tester.tapAt(const Offset(10, 10)); // tap outside closes it
    await tester.pumpAndSettle();
    expect(blocker.calls, [true, false]);
  });

  testWidgets('a decode line blocks only while the numbers show', (
    tester,
  ) async {
    final received = SarnegCodec('BLACKHORSE').encodeMessage('906.875');
    await tester.pumpWidget(_app(_Home(received: received)));
    await tester.pumpAndSettle();
    expect(blocker.calls, isEmpty);
    await tester.tap(find.text('SARNEG · tap to decode'));
    await tester.pump();
    expect(find.text('Decoded: 906.875'), findsOneWidget);
    expect(blocker.blocked, isTrue);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Decoded: 906.875'), findsNothing);
    expect(blocker.calls, [true, false]);
  });
}
