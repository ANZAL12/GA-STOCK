import 'package:flutter_test/flutter_test.dart';
import 'package:godown_scanner/main.dart';

void main() {
  testWidgets('GodownScannerApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GodownScannerApp());
    expect(find.byType(GodownScannerApp), findsOneWidget);
  });
}
