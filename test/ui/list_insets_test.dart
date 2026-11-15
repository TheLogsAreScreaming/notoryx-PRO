import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/ui/list_insets.dart';

void main() {
  testWidgets('adds the navigation bar inset to a list\'s own padding', (
    tester,
  ) async {
    late EdgeInsets got;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
        child: Builder(
          builder: (context) {
            got = withBottomInset(context, const EdgeInsets.all(8));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got, const EdgeInsets.fromLTRB(8, 8, 8, 56));
  });

  testWidgets('no inset leaves the padding alone', (tester) async {
    late EdgeInsets got;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            got = withBottomInset(context, const EdgeInsets.all(16));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got, const EdgeInsets.all(16));
  });
}
