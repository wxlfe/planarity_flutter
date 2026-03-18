import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:planarity/main.dart';

String _todayKey() {
  final now = DateTime.now().toUtc();
  final year = now.year.toString().padLeft(4, '0');
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

void main() {
  test('score updates when a graph is solved', () {
    expect(scoreForSolvedLevel(level: 6, movesUsed: 2), 4);
    expect(scoreForSolvedLevel(level: 6, movesUsed: 6), 0);
    expect(scoreForSolvedLevel(level: 6, movesUsed: 8), 0);
  });

  testWidgets('Home page shows mobile leaderboard with global default', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PlanarityApp());
    await tester.pumpAndSettle();

    expect(find.text('planarity'), findsAtLeastNWidgets(1));
    expect(find.text('start'), findsOneWidget);
    expect(find.text('leaderboard'), findsOneWidget);
    expect(find.text('Global'), findsOneWidget);
    expect(find.text('global top score'), findsOneWidget);
    expect(find.text('daily score'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('Home page shows leaderboard alongside hero on wide screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PlanarityApp());
    await tester.pumpAndSettle();

    expect(find.text('leaderboard'), findsOneWidget);
    expect(find.text('start'), findsOneWidget);
    expect(find.text('daily score'), findsOneWidget);
  });

  testWidgets('Home page shows the saved daily score for today', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'daily_status': 'inProgress',
      'daily_level': 8,
      'daily_score': 7,
      'daily_day': _todayKey(),
    });

    await tester.pumpWidget(const PlanarityApp());
    await tester.pumpAndSettle();

    expect(find.text('daily score'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('continue'), findsOneWidget);
  });

  testWidgets('Home page resets expired daily score to zero', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'daily_status': 'locked',
      'daily_level': 10,
      'daily_score': 9,
      'daily_day': '1900-01-01',
    });

    await tester.pumpWidget(const PlanarityApp());
    await tester.pumpAndSettle();

    expect(find.text('daily score'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('start'), findsOneWidget);
  });
}
