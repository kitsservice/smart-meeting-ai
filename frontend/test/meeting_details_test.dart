import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_meeting_ai/screens/meeting_details_screen.dart';

void main() {
  testWidgets('MeetingDetailsScreen renders properly without error',
      (WidgetTester tester) async {
    final mockMeeting = {
      'id': 'test-123',
      'title': 'Test Meeting',
      'created_at': '2026-10-15T10:00:00Z',
      'transcript': '[00:05] Speaker 1: Hello everyone\n[00:10] Speaker 2: Hi there',
      'summary': 'Test summary points',
      'action_items': [
        {'task': 'Follow up with team', 'assignee': 'John', 'is_completed': false}
      ]
    };

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              settings: RouteSettings(arguments: mockMeeting),
              builder: (context) => const MeetingDetailsScreen(),
            );
          },
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.pushNamed(
                context,
                '/details',
                arguments: mockMeeting,
              ),
              child: const Text('Go'),
            ),
          ),
          routes: {
            '/details': (context) => const MeetingDetailsScreen(),
          },
        ),
      ),
    );

    // Tap to navigate
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('Test Meeting'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('AI Summary'), findsOneWidget);
  });

  testWidgets('MeetingDetailsScreen handles null arguments gracefully without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MeetingDetailsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Meeting'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('AI Summary'), findsOneWidget);
  });

  testWidgets('MeetingDetailsScreen opens note dialog with keyboard insets and saves without error',
      (WidgetTester tester) async {
    final mockMeeting = {
      'id': 'test-note-123',
      'title': 'Test Meeting With Notes',
      'created_at': '2026-10-15T10:00:00Z',
      'notes': ['Existing note point 1'],
    };

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              settings: RouteSettings(arguments: mockMeeting),
              builder: (context) => const MeetingDetailsScreen(
                initialTabIndex: 1, // Start on Notes tab
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Notes tab is active
    expect(find.text('Add Meeting Note'), findsOneWidget);

    // Simulate keyboard open by setting viewInsets
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);

    // Tap Add Meeting Note button to open modal bottom sheet
    await tester.tap(find.text('Add Meeting Note'));
    await tester.pumpAndSettle();

    // Expect the bottom sheet to be open
    expect(find.text('New Meeting Note'), findsOneWidget);
    expect(find.text('Save Note'), findsOneWidget);

    // Enter text in TextField
    await tester.enterText(find.byType(TextField), 'New test note');
    await tester.pumpAndSettle();

    // Dismiss keyboard by setting viewInsets to 0
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    // Tap Save Note
    await tester.tap(find.text('Save Note'));
    await tester.pumpAndSettle();

    // Verify dialog dismissed cleanly without any uncaught exceptions
    expect(find.text('New Meeting Note'), findsNothing);
  });
}
