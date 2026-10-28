import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class RatingPromptService {
  static const String _countKey = 'ares_completed_meetings_count';
  static const String _ratedKey = 'ares_has_rated_app';
  static const String _lastPromptKey = 'ares_last_rating_prompt_time';

  /// Call this when a user successfully records and saves a meeting.
  static Future<void> checkAndPrompt(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRated = prefs.getBool(_ratedKey) ?? false;
      if (hasRated) return;

      int count = (prefs.getInt(_countKey) ?? 0) + 1;
      await prefs.setInt(_countKey, count);

      final lastPromptMs = prefs.getInt(_lastPromptKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceLastPrompt = (now - lastPromptMs) / (1000 * 60 * 60 * 24);

      // Trigger after 3rd meeting, or after 7th if previously postponed
      if ((count == 3 || count == 7) && daysSinceLastPrompt >= 3) {
        await prefs.setInt(_lastPromptKey, now);
        if (context.mounted) {
          _showRatingSheet(context);
        }
      }
    } catch (e) {
      debugPrint('Error in RatingPromptService: $e');
    }
  }

  static void _showRatingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _RatingBottomSheet(),
    );
  }

  static Future<void> openPlayStore() async {
    final Uri url = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.kits.ares',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Could not open Play Store: $e');
    }
  }
}

class _RatingBottomSheet extends StatefulWidget {
  const _RatingBottomSheet();

  @override
  State<_RatingBottomSheet> createState() => _RatingBottomSheetState();
}

class _RatingBottomSheetState extends State<_RatingBottomSheet> {
  int _selectedStars = 0;
  bool _submittedFeedback = false;
  final TextEditingController _feedbackController = TextEditingController();

  Future<void> _markRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ares_has_rated_app', true);
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: AppTheme.cardBorder(context),
          width: 1,
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 20),

            // Heart / Star Header Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFFF59E0B),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Enjoying Ares Smart Meeting?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),

            const Text(
              'Tap a star to rate your overall meeting experience:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),

            // 5 Star Selector Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNum = index + 1;
                final isSelected = starNum <= _selectedStars;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedStars = starNum;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      isSelected
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 38,
                      color: isSelected
                          ? const Color(0xFFF59E0B)
                          : (isDark ? Colors.white24 : Colors.grey[350]),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Branching based on selected stars
            if (_selectedStars >= 4) ...[
              // Positive Rating -> Direct to Play Store
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.sentiment_very_satisfied_rounded,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Thank you! A quick review on Google Play helps other teams discover Ares.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await _markRated();
                    if (context.mounted) Navigator.pop(context);
                    await RatingPromptService.openPlayStore();
                  },
                  icon: const Icon(Icons.rate_review_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'Rate on Google Play',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ] else if (_selectedStars > 0 && _selectedStars < 4) ...[
              // Critical Rating -> Route feedback internally to support
              if (!_submittedFeedback) ...[
                TextField(
                  controller: _feedbackController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'What can we improve in transcription or summaries?',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await _markRated();
                      setState(() => _submittedFeedback = true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Send Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Thank you for your feedback! Our engineering team will review it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13.5,
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
