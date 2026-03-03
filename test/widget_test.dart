import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:planarity_flutter/main.dart';

void main() {
  testWidgets('Home page shows planarity and start button', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PlanarityApp());
    await tester.pumpAndSettle();

    expect(find.text('planarity'), findsAtLeastNWidgets(1));
    expect(find.text('start'), findsOneWidget);
  });
}
