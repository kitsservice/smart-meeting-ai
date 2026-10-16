import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meeting_ai/main.dart';

void main() {
  testWidgets('App loads and shows the title', (WidgetTester tester) async {
    // Build our app and trigger an initial frame.
    await tester.pumpWidget(const SmartMeetingApp());

    // Verify that the title is present on the Splash Screen.
    expect(find.text('Smart Meeting'), findsOneWidget);
    expect(find.text('AI-Powered Intelligent Summaries'), findsOneWidget);

    // Unmount widget to trigger dispose and cancel pending timers
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
