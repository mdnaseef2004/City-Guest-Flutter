import 'package:flutter_test/flutter_test.dart';
import 'package:city_guest_flutter/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CityGuestApp());
  });
}
