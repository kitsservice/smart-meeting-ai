import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Help & Support',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Best Practices',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  _buildTip(
                    Icons.phone_android,
                    'Keep your phone flat on the table, face up.',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  _buildTip(
                    Icons.mic_none,
                    'Do not block the bottom microphone of your device.',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  _buildTip(
                    Icons.record_voice_over,
                    'Speak clearly and avoid talking over each other for best results.',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    _buildFaqTile(
                      'How accurate is the AI transcription?',
                      'Our AI models achieve over 95% accuracy in quiet environments. Heavy background noise or overlapping speakers may reduce accuracy.',
                    ),
                    const Divider(height: 1),
                    _buildFaqTile(
                      'Is my meeting data private?',
                      'Yes. All transcripts are securely stored on our servers and are never used to train public AI models.',
                    ),
                    const Divider(height: 1),
                    _buildFaqTile(
                      'Can I export my notes?',
                      'Yes! You can export your meeting summaries to PDF, Word, or share them directly to Notion and Slack (Pro feature).',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Text(
              'Troubleshooting',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            _buildActionCard(
              context,
              icon: Icons.bug_report_outlined,
              title: 'Report AI Hallucination',
              subtitle:
                  'Did the AI completely mess up a transcript? Send it to developers.',
              color: AppTheme.dangerColor,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Diagnostic log queued for submission.'),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context,
              icon: Icons.play_lesson_outlined,
              title: 'Run a Demo Meeting',
              subtitle:
                  'Learn how to use Live Notes with a fake 30-second meeting.',
              color: AppTheme.primaryColor,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo meeting feature coming soon!'),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context,
              icon: Icons.chat_bubble_outline,
              title: 'Contact Support',
              subtitle: 'Chat with our engineering team for help.',
              color: AppTheme.accentColor,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening support chat...')),
                );
              },
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqTile(String question, String answer) {
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        iconColor: AppTheme.primaryColor,
        collapsedIconColor: AppTheme.textSecondary,
        title: Text(
          question,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: AppTheme.textPrimary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text(
              answer,
              style: const TextStyle(
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppTheme.textPrimary, height: 1.4),
          ),
        ),
      ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
