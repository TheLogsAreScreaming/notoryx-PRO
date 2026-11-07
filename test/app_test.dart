import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/main.dart';

void main() {
  testWidgets('shows the app name', (tester) async {
    await tester.pumpWidget(const NotoryxProApp());
    expect(find.textContaining('NOTORYX PRO'), findsOneWidget);
  });
}
