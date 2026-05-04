import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('App loads rabbit list screen', (WidgetTester tester) async {
    await tester.pumpWidget(const CuniSmartApp());
    expect(find.text('CuniSmart — Rabbits'), findsOneWidget);
  });
}
