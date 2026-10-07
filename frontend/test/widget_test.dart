import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meeting_ai/main.dart';

void main() {
  testWidgets('App loads and shows the title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartMeetingApp());

    // Verify that the title is present.
    expect(find.text('Smart Meeting AI'), findsOneWidget);
    expect(find.text('Recent Meetings'), findsOneWidget);
  });
}
