import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

enum AresPermissionType {
  microphone,
  calendar,
  notification,
}

class PermissionSheet extends StatelessWidget {
  final AresPermissionType type;
  final VoidCallback onContinue;
  final VoidCallback? onDismiss;

  const PermissionSheet({
    super.key,
    required this.type,
    required this.onContinue,
    this.onDismiss,
  });

  /// Static helper to display the sheet modally
  static Future<bool> show(
    BuildContext context, {
    required AresPermissionType type,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PermissionSheet(
        type: type,
        onContinue: () {
          HapticFeedback.lightImpact();
          Navigator.pop(ctx, true);
        },
        onDismiss: () {
          HapticFeedback.lightImpact();
          Navigator.pop(ctx, false);
        },
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    IconData icon;
    String title;
    String subtitle;
    List<Map<String, String>> points;

    switch (type) {
      case AresPermissionType.microphone:
        icon = Icons.mic_rounded;
        title = 'Microphone Access Required';
        subtitle =
            'Ares requires microphone access to record conversations and generate real-time AI transcripts.';
        points = [
          {
            'title': 'Real-Time Transcription',
            'desc': 'Capture speech-to-text with continuous precision.',
          },
          {
            'title': 'AI Speaker Diarization',
            'desc': 'Distinguish between you and other participants.',
          },
          {
            'title': 'Encrypted & Private',
            'desc': 'Audio is encrypted and never shared without permission.',
          },
        ];
        break;

      case AresPermissionType.calendar:
        icon = Icons.calendar_month_rounded;
        title = 'Calendar Access';
        subtitle =
            'Sync meetings and export action items directly to your personal calendar.';
        points = [
          {
            'title': 'Meeting Scheduling',
            'desc': 'View and coordinate upcoming calendar commitments.',
          },
          {
            'title': 'Action Item Reminders',
            'desc': 'Add task deadlines with reminders to Google Calendar.',
          },
          {
            'title': 'Strict Privacy',
            'desc': 'Ares only reads events needed to detect meeting schedules.',
          },
        ];
        break;

      case AresPermissionType.notification:
        icon = Icons.notifications_active_rounded;
        title = 'Notification Permission';
        subtitle =
            'Stay in control of your meeting recordings even when your screen is locked.';
        points = [
          {
            'title': 'Lock Screen Controls',
            'desc': 'Pause, resume, and end meetings from notifications.',
          },
          {
            'title': 'Background Protection',
            'desc': 'Ensures the OS does not terminate recordings while locked.',
          },
          {
            'title': 'Timely Reminders',
            'desc': 'Get gentle alerts 5 minutes before scheduled meetings.',
          },
        ];
        break;
    }

    return ResponsiveSheetContainer(
      maxWidth: Responsive.maxSheetWidth,
      backgroundColor: AppTheme.cardBg(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      padding: EdgeInsets.fromLTRB(
        Responsive.value(context, mobile: 24.0, narrow: 14.0),
        20,
        Responsive.value(context, mobile: 24.0, narrow: 14.0),
        32,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Icon badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: AppTheme.primaryColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),

            // Benefits checklist
            ...points.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['title']!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p['desc']!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Primary action button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Allow & Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Subtle dismiss button
            TextButton(
              onPressed: onDismiss ?? () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
              ),
              child: const Text(
                'Not Now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
