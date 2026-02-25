// Базовый smoke-тест приложения NgondroApp
import 'package:flutter_test/flutter_test.dart';
import 'package:ngondro_app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NgondroApp());
    expect(find.byType(NgondroApp), findsOneWidget);
  });
}
