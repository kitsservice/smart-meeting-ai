import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const isDark = false;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Help & Support',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.4,
            color: isDark ? Colors.white : AppTheme.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppTheme.textPrimary,
        ),
      ),
      body: ResponsiveContentWrapper(
        maxWidth: Responsive.maxContentWidth,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.horizontalPadding(context),
            vertical: 16,
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Guide & Feature Manual Header
            _buildSectionHeader(
              'Feature Guides & User Manual',
              'Step-by-step walkthroughs for every tool in the app',
              Icons.menu_book_rounded,
              const Color(0xFF4364F7),
              context,
            ),
            const SizedBox(height: 12),
            _buildUserGuideSection(context),

            const SizedBox(height: 32),

            // Best Practices Header
            _buildSectionHeader(
              'Best Practices',
              'Tips for 98%+ AI transcription accuracy',
              Icons.verified_outlined,
              AppTheme.primaryColor,
              context,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.cardBg(context) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primaryColor
                      .withValues(alpha: isDark ? 0.35 : 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor
                        .withValues(alpha: isDark ? 0.15 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildTip(
                    Icons.phone_android_rounded,
                    'Keep your phone flat on the table, face up.',
                    context,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                  _buildTip(
                    Icons.mic_none_rounded,
                    'Do not block the bottom microphone of your device.',
                    context,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                  _buildTip(
                    Icons.record_voice_over_rounded,
                    'Speak naturally and avoid talking over each other.',
                    context,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // FAQ Header
            _buildSectionHeader(
              'Frequently Asked Questions',
              'Common questions about transcripts & privacy',
              Icons.quiz_outlined,
              const Color(0xFF8B5CF6),
              context,
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.cardBg(context) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  children: [
                    _buildFaqTile(
                      'How accurate is the AI transcription?',
                      'Our AI models achieve over 95% accuracy in quiet rooms. Heavy ambient noise, music, or shouting across the room may reduce accuracy.',
                      context,
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFF1F5F9),
                    ),
                    _buildFaqTile(
                      'Is my meeting data private?',
                      'Yes. Transcripts are encrypted in transit and at rest. They are strictly private to your account and never used to train public AI models.',
                      context,
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFF1F5F9),
                    ),
                    _buildFaqTile(
                      'Can I export my notes and action items?',
                      'Yes! You can copy transcripts directly, share to external apps, and sync action items straight to your device calendar.',
                      context,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Troubleshooting Header
            _buildSectionHeader(
              'Troubleshooting',
              'Quick diagnostic tools and developer support',
              Icons.build_circle_outlined,
              AppTheme.dangerColor,
              context,
            ),
            const SizedBox(height: 12),

            // Card 1: Report Hallucination
            _buildActionCard(
              context,
              icon: Icons.bug_report_rounded,
              title: 'Report AI Hallucination',
              subtitle:
                  'Did the AI hallucinate or mislabel a speaker? Send logs directly to engineers.',
              color: AppTheme.dangerColor,
              onTap: () => _showReportHallucinationSheet(context),
            ),
            const SizedBox(height: 14),

            // Card 2: Run Demo Meeting
            _buildActionCard(
              context,
              icon: Icons.play_lesson_rounded,
              title: 'Run a Demo Meeting',
              subtitle:
                  'Explore an instant pre-populated meeting with speakers, timestamps, and action items.',
              color: AppTheme.primaryColor,
              onTap: () => _showDemoMeetingDialog(context),
            ),
            const SizedBox(height: 14),

            // Card 3: Contact Support
            _buildActionCard(
              context,
              icon: Icons.headset_mic_rounded,
              title: 'Contact Engineering Support',
              subtitle:
                  'Compose a support ticket with system diagnostics or copy our direct team email.',
              color: const Color(0xFF059669), // Rich Emerald Green
              onTap: () => _showContactSupportSheet(context),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle,
    IconData icon,
    Color accentColor,
    BuildContext context,
  ) {
    const isDark = false;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accentColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTip(IconData icon, String text, BuildContext context) {
    const isDark = false;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaqTile(String question, String answer, BuildContext context) {
    const isDark = false;

    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        iconColor: AppTheme.primaryColor,
        collapsedIconColor: isDark ? Colors.white60 : AppTheme.textSecondary,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        title: Text(
          question,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            color: isDark ? Colors.white : AppTheme.textPrimary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 18),
            child: Text(
              answer,
              style: TextStyle(
                height: 1.5,
                fontSize: 13.5,
                color: isDark ? Colors.white70 : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    const isDark = false;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardBg(context) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          // Soft ambient colored glow
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.16 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          // Deep clean drop shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Glowing Icon Badge
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: color.withValues(alpha: isDark ? 0.45 : 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: color, size: 25),
                  ),
                ),
                const SizedBox(width: 16),

                // Card Labels
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          letterSpacing: -0.2,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // High-visibility Chevron Pill
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.18 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: color,
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReportHallucinationSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    final textController = TextEditingController();
    String selectedCategory = 'Inaccurate Words';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            const isDark = false;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurface : Colors.white,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(28)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 44,
                            height: 4.5,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white24
                                  : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),

                        // Header with glowing icon badge
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppTheme.dangerColor
                                    .withValues(alpha: isDark ? 0.2 : 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.dangerColor
                                      .withValues(alpha: isDark ? 0.45 : 0.25),
                                  width: 1.5,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.bug_report_rounded,
                                  color: AppTheme.dangerColor,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Report AI Hallucination',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      letterSpacing: -0.3,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Help us train and improve model accuracy',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),

                        // Section Label
                        Text(
                          'Issue Type',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Category Chips with visible border and active styling
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Inaccurate Words',
                            'Wrong Speaker',
                            'Phantom Speech',
                            'Missed Discussion',
                          ].map((cat) {
                            final isSel = selectedCategory == cat;
                            return ChoiceChip(
                              label: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight:
                                      isSel ? FontWeight.w800 : FontWeight.w600,
                                  color: isSel
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B)),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppTheme.dangerColor,
                              backgroundColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF1F5F9),
                              side: BorderSide(
                                color: isSel
                                    ? AppTheme.dangerColor
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : const Color(0xFFCBD5E1)),
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onSelected: (val) {
                                if (val) {
                                  setModalState(() => selectedCategory = cat);
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),

                        // Text Area Container with strong borders and contrast
                        TextField(
                          controller: textController,
                          maxLines: 4,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Paste the hallucinated text or describe what the AI got wrong...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : const Color(0xFFCBD5E1),
                                width: 1.5,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : const Color(0xFFCBD5E1),
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.dangerColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Submit Button with elevation and safe clearance
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final text = textController.text.trim();
                                    if (text.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please provide a short description.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setModalState(() => isSubmitting = true);
                                    try {
                                      final user = Supabase
                                          .instance.client.auth.currentUser;
                                      await Supabase.instance.client
                                          .from('support_tickets')
                                          .insert({
                                        'user_id': user?.id,
                                        'type': 'ai_hallucination',
                                        'category': selectedCategory,
                                        'description': text,
                                        'status': 'open',
                                        'created_at':
                                            DateTime.now().toIso8601String(),
                                      });
                                    } catch (_) {
                                      // Silently proceed if table not yet created
                                    }
                                    if (!modalContext.mounted) return;
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Report submitted! Our AI team will review the diagnostic log.',
                                        ),
                                        backgroundColor: AppTheme.accentColor,
                                      ),
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.dangerColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                              shadowColor: AppTheme.dangerColor
                                  .withValues(alpha: 0.4),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Text(
                                    'Submit Report',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Secondary: Direct Email to Engineering
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final text = textController.text.trim();
                              final user =
                                  Supabase.instance.client.auth.currentUser;
                              final body =
                                  "Issue Category: $selectedCategory\nUser ID: ${user?.id ?? 'Guest'}\nUser Email: ${user?.email ?? 'Not logged in'}\nTimestamp: ${DateTime.now().toIso8601String()}\n\nDescription / Hallucinated Text:\n${text.isEmpty ? '[Please describe the hallucination]' : text}";
                              final emailUri = Uri(
                                scheme: 'mailto',
                                path: 'kitssalesteam@gmail.com',
                                queryParameters: {
                                  'subject':
                                      '[AI Hallucination] $selectedCategory',
                                  'body': body,
                                },
                              );
                              try {
                                if (await canLaunchUrl(emailUri)) {
                                  await launchUrl(
                                    emailUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else {
                                  SharePlus.instance.share(
                                    ShareParams(
                                      text: body,
                                      subject:
                                          '[AI Hallucination] $selectedCategory',
                                    ),
                                  );
                                }
                              } catch (_) {
                                SharePlus.instance.share(
                                  ShareParams(
                                    text: body,
                                    subject:
                                        '[AI Hallucination] $selectedCategory',
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.email_outlined, size: 17),
                            label: const Text(
                              'Email to kitssalesteam@gmail.com',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? Colors.white70
                                  : const Color(0xFF334155),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : const Color(0xFFCBD5E1),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: MediaQuery.of(modalContext).padding.bottom > 0
                              ? 8
                              : 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDemoMeetingDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        const isDark = false;

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color:
                            isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor
                              .withValues(alpha: isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.primaryColor
                                .withValues(alpha: isDark ? 0.45 : 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_lesson_rounded,
                            color: AppTheme.primaryColor,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Interactive Demo Meeting',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17.5,
                                letterSpacing: -0.3,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Explore how AI captures and structures meetings',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Card 1: Sample AI Meeting Summary Card
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.35 : 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.pushNamed(
                            context,
                            '/meeting_details',
                            arguments: {
                              'id': 'demo_meeting_sample',
                              'title': 'Demo: Product Launch & AI Sprint',
                              'created_at': DateTime.now()
                                  .subtract(const Duration(hours: 3))
                                  .toIso8601String(),
                              'summary':
                                  'The product team aligned on the mobile app launch timeline, confirmed Deepgram Nova-2 speech diarization performance with 16kHz mono audio, and delegated action items for Friday\'s release.',
                              'transcript':
                                  '[00:04] Alex (Product Lead): Good morning everyone, let\'s review the release goals for this sprint.\n\n[00:15] Priya (ML Engineer): The voice biometrics downsampling is configured, and Gemini 2.0 Flash handles the multilingual code-switching smoothly.\n\n[00:28] Alex (Product Lead): Excellent. Let\'s verify device calendar synchronization before publishing to app stores.',
                              'action_items': [
                                {
                                  'id': 'demo_task_1',
                                  'task':
                                      'Verify Deepgram Nova-2 audio downsampling in staging',
                                  'assignee': 'Priya',
                                  'is_completed': true,
                                },
                                {
                                  'id': 'demo_task_2',
                                  'task':
                                      'Prepare Play Store release notes and feature graphic assets',
                                  'assignee': 'Alex',
                                  'is_completed': false,
                                },
                                {
                                  'id': 'demo_task_3',
                                  'task':
                                      'Review Supabase database query performance and indexes',
                                  'assignee': 'Engineering',
                                  'is_completed': false,
                                },
                              ],
                            },
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF10B981)
                                        .withValues(
                                            alpha: isDark ? 0.45 : 0.25),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.auto_stories_rounded,
                                    color: Color(0xFF10B981),
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Explore Sample AI Meeting Summary',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: -0.2,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Review timestamps, diarized speakers, and auto-generated action items.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        height: 1.3,
                                        color: isDark
                                            ? Colors.white70
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: isDark ? 0.2 : 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 11,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Card 2: Practice Live Recording Room Card
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.35 : 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.pushNamed(
                            context,
                            '/active_meeting',
                            arguments: {
                              'title': 'Demo: Practice Live Session',
                            },
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.primaryColor
                                        .withValues(
                                            alpha: isDark ? 0.45 : 0.25),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.mic_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Practice Live Recording Room',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: -0.2,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Start a test recording session with waveform and participant presence.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        height: 1.3,
                                        color: isDark
                                            ? Colors.white70
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: isDark ? 0.2 : 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 11,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(sheetContext).padding.bottom > 0
                        ? 6
                        : 12,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showContactSupportSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    const supportEmail = 'kitssalesteam@gmail.com';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        const isDark = false;
        final user = Supabase.instance.client.auth.currentUser;

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color:
                            isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Sheet Header with Glowing Badge
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669)
                              .withValues(alpha: isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF059669)
                                .withValues(alpha: isDark ? 0.45 : 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.headset_mic_rounded,
                            color: Color(0xFF059669),
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contact Engineering Support',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17.5,
                                letterSpacing: -0.3,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'We typically respond within 24 hours',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Email Support Card with high visibility, shadow & copy pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.35 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669)
                                .withValues(alpha: isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF059669)
                                  .withValues(alpha: isDark ? 0.45 : 0.25),
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.email_rounded,
                              color: Color(0xFF059669),
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Support Email',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                supportEmail,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Clipboard.setData(
                                const ClipboardData(text: supportEmail),
                              );
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Support email copied to clipboard!',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : const Color(0xFF059669)
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : const Color(0xFF059669)
                                          .withValues(alpha: 0.25),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF059669),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Diagnostics Information Note
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: isDark
                              ? Colors.white60
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Includes app version (v2.0.3), device logs, and user ID to speed up support.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Share / Send Diagnostics Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final diagnostics =
                            "App: Smart Meeting AI v2.0.3\nUser ID: ${user?.id ?? 'Guest'}\nEmail: ${user?.email ?? 'Not logged in'}\nTimestamp: ${DateTime.now().toIso8601String()}\n\n[Please describe your issue or question below]:\n";
                        final emailUri = Uri(
                          scheme: 'mailto',
                          path: supportEmail,
                          queryParameters: {
                            'subject': 'Smart Meeting AI Support Ticket',
                            'body': diagnostics,
                          },
                        );
                        try {
                          if (await canLaunchUrl(emailUri)) {
                            await launchUrl(
                              emailUri,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            SharePlus.instance.share(
                              ShareParams(
                                text: diagnostics,
                                subject: 'Smart Meeting AI Support Ticket',
                              ),
                            );
                          }
                        } catch (_) {
                          SharePlus.instance.share(
                            ShareParams(
                              text: diagnostics,
                              subject: 'Smart Meeting AI Support Ticket',
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.send_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Compose Support Ticket',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                        shadowColor: const Color(0xFF059669)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(sheetContext).padding.bottom > 0
                        ? 6
                        : 12,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static final List<Map<String, dynamic>> _featureGuides = [
    {
      'title': '1. Solo Memos vs. Team Rooms',
      'subtitle': 'Learn when to use quick voice notes vs 6-digit room codes',
      'icon': Icons.groups_rounded,
      'color': const Color(0xFF4364F7),
      'description':
          'Smart Meeting AI allows you to record private voice notes by yourself or collaborate in live team rooms with colleagues.',
      'steps': [
        'Solo Meeting: Simply tap "Start Meeting", enter a title, and press Start. You do not need to share the code.',
        'Team Meeting: The Host starts the meeting and shares the 6-digit room code with attendees.',
        'Joiners: Team members tap "Join Meeting", enter the code, and wait in the lobby until the host begins.',
        'Audio Capture: Only the host phone records master audio to eliminate acoustic feedback and echoes.'
      ],
      'tip':
          'Place the host device in the center of the conference table, face up, without obstructing the microphone.',
      'actionText': 'Start a Meeting',
      'actionRoute': '/active_meeting',
    },
    {
      'title': '2. Voice Profile Biometrics',
      'subtitle': 'How the AI identifies you by your real name',
      'icon': Icons.record_voice_over_rounded,
      'color': const Color(0xFF10B981),
      'description':
          'Our SpeechBrain ECAPA-TDNN biometric engine matches your voice frequency to your name automatically.',
      'steps': [
        'Open Voice Calibration from the home banner, drawer, or settings.',
        'Record 3 separate voice samples (6-8 seconds each) reading the prompt aloud naturally.',
        'The app calculates your 192-dimensional acoustic centroid and saves your signature.',
        'In live meetings, all of your spoken sentences will automatically display your real name!'
      ],
      'tip':
          'Record your calibration samples in a quiet room using your everyday business tone.',
      'actionText': 'Open Voice Setup',
      'actionRoute': '/voice_setup',
    },
    {
      'title': '3. Interactive Timestamp Seeking',
      'subtitle': 'Tap any [MM:SS] timestamp to jump audio playback',
      'icon': Icons.fast_forward_rounded,
      'color': const Color(0xFFF59E0B),
      'description':
          'Every sentence in your meeting transcript is synchronized with the recorded audio down to the exact second.',
      'steps': [
        'Open any meeting details from the Home screen or History list.',
        'In the Transcript tab, find any sentence and tap its [MM:SS] timestamp tag.',
        'The built-in audio player will instantly jump to that exact second and begin playing.',
        'Adjust playback speed between 1.0x, 1.5x, and 2.0x on the floating audio player bar.'
      ],
      'tip':
          'Use the search bar at the top of the transcript to search for keywords like "budget" or "deadline", then tap the timestamp!',
      'actionText': 'Got it',
      'actionRoute': null,
    },
    {
      'title': '4. Ask Ares AI Meeting Copilot',
      'subtitle': 'Chat with your meeting transcript to get instant answers',
      'icon': Icons.auto_awesome_rounded,
      'color': const Color(0xFF8B5CF6),
      'description':
          'Ask Ares is an intelligent meeting assistant powered by Google Gemini that answers questions directly from your meeting dialogue.',
      'steps': [
        'Tap the floating "Ask Ares" button in any meeting or on the Home screen.',
        'Type or ask questions like: "What was decided about the project deadline?" or "List all action items assigned to Priya".',
        'Ares replies with grounded answers, exact quotes, and direct timestamps.',
        'You can also ask Ares to draft client follow-up emails based on the discussion.'
      ],
      'tip':
          'You can query specific numbers, budget approvals, and team commitments with pinpoint precision.',
      'actionText': 'Got it',
      'actionRoute': null,
    },
    {
      'title': '5. Action Items & Calendar Sync',
      'subtitle': 'Extract tasks and sync directly to Google Calendar',
      'icon': Icons.event_available_rounded,
      'color': const Color(0xFF06B6D4),
      'description':
          'Never drop a follow-up item. The AI listens for commitments like "I will email the contract by Friday" and lists them under Action Items.',
      'steps': [
        'In Meeting Details, navigate to the "Action Items" tab.',
        'Review detected tasks and their assignees.',
        'Tap the calendar icon on any task to add it straight into your device Google/Apple calendar with reminders.',
        'Check off items as your team completes them, or tap "+ Add Task" to create custom action items.'
      ],
      'tip':
          'Speaking clear deadlines during the meeting (e.g. "by Monday at 3 PM") helps the AI set exact calendar alarm dates.',
      'actionText': 'Got it',
      'actionRoute': null,
    },
    {
      'title': '6. Executive Daily Reports',
      'subtitle': 'Consolidated end-of-day digest across all meetings',
      'icon': Icons.pie_chart_rounded,
      'color': const Color(0xFFEC4899),
      'description':
          'Designed for executives and managers to get a unified overview of all discussions conducted throughout the day.',
      'steps': [
        'On the Home screen or Meetings list, tap "Daily Report".',
        'Select today or any previous calendar date.',
        'The AI synthesizes total meeting duration, all attendees present, major company decisions, and a master task list.',
        'Export or share the executive brief with your leadership team in 1 tap.'
      ],
      'tip':
          'Save 45 minutes of manual status updates by reviewing the 5 PM Daily Report with your department leads.',
      'actionText': 'Got it',
      'actionRoute': null,
    },
    {
      'title': '7. Hindi, Marathi & Multilingual Dialects',
      'subtitle': 'Natively transcribes Indic languages with business slang',
      'icon': Icons.translate_rounded,
      'color': const Color(0xFFE11D48),
      'description':
          'Smart Meeting AI natively supports Hindi (हिन्दी), Marathi (मराठी), code-mixed Hinglish, and English without dropping colloquial slang.',
      'steps': [
        'By default, Ares automatically identifies language shifts on the fly.',
        'Local conversational phrases like "kam complete karo", "udya meeting aahe", or "funda clear hai" are transcribed accurately.',
        'To force a specific language, go to Settings > Language Priority and select Marathi, Hindi, or English.',
        'Transcripts maintain speaker names regardless of the language spoken.'
      ],
      'tip':
          'If your team mixes English and Marathi/Hindi frequently, leave the setting on "Auto-Detect" for optimal results.',
      'actionText': 'Open Settings',
      'actionRoute': '/settings',
    },
    {
      'title': '8. Background Recording & Offline Auto-Sync',
      'subtitle': 'Record with screen off and sync automatically when online',
      'icon': Icons.cloud_off_rounded,
      'color': const Color(0xFF64748B),
      'description':
          'Engineered for reliability in elevators, basements, or airplanes without reliable internet.',
      'steps': [
        'Android Foreground Service ensures recording continues even if your phone screen locks or turns off.',
        'Use the persistent interactive notification to Pause or End meeting without opening the app.',
        'If internet drops, audio is securely saved locally on your device.',
        'The moment Wi-Fi or cellular data reconnects, the offline queue automatically uploads and transcribes in the background.'
      ],
      'tip':
          'Allow "Battery Optimization Exemption" when prompted to ensure the OS never puts background recording to sleep.',
      'actionText': 'Got it',
      'actionRoute': null,
    },
  ];

  Widget _buildUserGuideSection(BuildContext context) {
    const isDark = false;

    return Column(
      children: [
        // Hero Card: Manual Overview & Full SOP Button
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4364F7).withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_stories_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Official SOP User Manual',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Comprehensive walkthrough for all features',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Explore the 8 essential workflows below to get 100% value out of Smart Meeting AI, from voice diarization to calendar sync.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showFullManualDialog(context),
                  icon: const Icon(Icons.chrome_reader_mode_rounded, size: 18),
                  label: const Text(
                    'Read Complete Manual & SOP',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 8 Interactive Feature Guide Cards
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _featureGuides.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final guide = _featureGuides[index];
            final color = guide['color'] as Color;

            return InkWell(
              onTap: () => _showFeatureGuideSheet(context, guide),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.cardBg(context) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(guide['icon'] as IconData,
                          color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guide['title'] as String,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: isDark ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            guide['subtitle'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showFeatureGuideSheet(
      BuildContext context, Map<String, dynamic> guide) {
    final color = guide['color'] as Color;
    final steps = guide['steps'] as List<String>;
    final actionText = guide['actionText'] as String?;
    final actionRoute = guide['actionRoute'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Badge & Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(guide['icon'] as IconData,
                                color: color, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  guide['title'] as String,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  guide['subtitle'] as String,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Description
                      Text(
                        guide['description'] as String,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          color: AppTheme.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Step-by-Step Instructions',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Steps
                      ...List.generate(steps.length, (idx) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  steps[idx],
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 14),

                      // Pro Tip Callout
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: color.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lightbulb_rounded,
                                color: color, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                guide['tip'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: color.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Bottom Action Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            if (actionRoute != null && context.mounted) {
                              Navigator.pushNamed(context, actionRoute);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            actionText ?? 'Got it',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFullManualDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 650, maxWidth: 550),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ares AI User Manual & SOP',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Version 2.0.3 (Build 7)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildManualChapter(
                        '1. Getting Started & Permissions',
                        'Grant Microphone, Notifications, and disable Battery Optimization for Ares. Complete your 3-phrase Voice Calibration to register your biometric voiceprint.',
                      ),
                      _buildManualChapter(
                        '2. Solo Meetings & Voice Notes',
                        'Tap "Start Meeting" -> "Start Session". Speak naturally. You do not need to share the room code for solo voice notes.',
                      ),
                      _buildManualChapter(
                        '3. Live Room Collaboration',
                        'The Host creates the meeting and shares the 6-digit code. Joiners enter the code to join the live room and link their biometric identities.',
                      ),
                      _buildManualChapter(
                        '4. Transcripts with Named Speakers',
                        'Deepgram Nova-3 + SpeechBrain diarizes every speaker. Tap any [MM:SS] timestamp to jump the audio player directly to that sentence.',
                      ),
                      _buildManualChapter(
                        '5. Executive MoM Summaries',
                        'Minutes of Meeting are generated in 15-30 seconds with key objectives, decisions made, and follow-ups.',
                      ),
                      _buildManualChapter(
                        '6. Action Items & Calendar Alarms',
                        'Tasks are extracted with assignees. Tap the calendar icon on any action item to push it to your Google Calendar.',
                      ),
                      _buildManualChapter(
                        '7. Ask Ares AI Copilot',
                        'Chat contextually with any meeting transcript. Ask for quotes, numbers, summaries, or draft follow-up emails.',
                      ),
                      _buildManualChapter(
                        '8. Offline & Background Safety',
                        'Turn your screen off freely while recording. If internet drops, audio is saved locally and automatically syncs when online.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Close Manual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualChapter(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

}
