// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'main.dart';

void main() {
  testWidgets('ECGenius Dashboard smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ECGeniusApp());

    // Welcome screen is shown first — verify welcome content
    expect(find.text('Welcome to ECG Monitoring'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap "Get Started" to go to the dashboard
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // Verify that the dashboard loads with patient information
    expect(find.text('alina azam'), findsOneWidget);
    expect(find.text('ACC-2024-001234'), findsOneWidget);

    // Verify that tabs are present (updated to match current tab names)
    expect(find.text('BPM Chart'), findsWidgets);
    expect(find.text('ECG Chart'), findsWidgets);
    expect(find.text('Patient History'), findsOneWidget);

    // Verify that control buttons are present
    expect(find.text('Start Monitoring'), findsOneWidget);
    expect(find.text('Stop Monitoring'), findsOneWidget);
  });

  testWidgets('Dashboard tab navigation test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ECGeniusApp());
    await tester.pumpAndSettle();

    // Tap "Get Started" to go to the dashboard
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // Verify we're on the BPM Chart tab initially
    expect(find.text('BPM Chart'), findsWidgets);

    // Tap on Patient History tab
    await tester.tap(find.text('Patient History'));
    await tester.pumpAndSettle();

    // Verify history content is displayed (empty state or sessions)
    expect(find.text('Patient History'), findsOneWidget);
  });
}
