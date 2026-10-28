import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meeting_ai/widgets/shimmer_loading.dart';
import 'package:smart_meeting_ai/widgets/audio_waveform_visualizer.dart';
import 'package:smart_meeting_ai/widgets/permission_sheet.dart';

void main() {
  group('Polish Features QA Test Suite', () {
    testWidgets('Shimmer Loading Skeletons render correctly without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MeetingListSkeleton(count: 2),
                  TranscriptSkeleton(count: 2),
                  SizedBox(
                    height: 400,
                    child: ActionItemsSkeleton(count: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MeetingListSkeleton), findsOneWidget);
      expect(find.byType(TranscriptSkeleton), findsOneWidget);
      expect(find.byType(ActionItemsSkeleton), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('AudioWaveformVisualizer renders in active and interrupted states',
        (WidgetTester tester) async {
      final samples = List.generate(28, (i) => 0.06 + (i * 0.03));

      // Test active recording state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioWaveformVisualizer(
              samples: samples,
              isRecording: true,
              isInterrupted: false,
              currentAmplitude: 0.45,
            ),
          ),
        ),
      );

      expect(find.text('SPEECH DETECTED'), findsOneWidget);

      // Test interrupted state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioWaveformVisualizer(
              samples: samples,
              isRecording: false,
              isInterrupted: true,
              currentAmplitude: 0.0,
            ),
          ),
        ),
      );

      expect(find.text('AUDIO INTERRUPTED • TAP RESUME'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('PermissionSheet displays microphone, calendar, and notification info',
        (WidgetTester tester) async {
      // Test Microphone sheet
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionSheet(
              type: AresPermissionType.microphone,
              onContinue: () {},
            ),
          ),
        ),
      );

      expect(find.text('Microphone Access Required'), findsOneWidget);
      expect(find.text('Allow & Continue'), findsOneWidget);

      // Test Calendar sheet
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionSheet(
              type: AresPermissionType.calendar,
              onContinue: () {},
            ),
          ),
        ),
      );

      expect(find.text('Calendar Access'), findsOneWidget);

      // Test Notification sheet
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionSheet(
              type: AresPermissionType.notification,
              onContinue: () {},
            ),
          ),
        ),
      );

      expect(find.text('Notification Permission'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
