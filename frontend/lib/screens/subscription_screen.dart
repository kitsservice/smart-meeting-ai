import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isAnnual = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.close_rounded,
            color: AppTheme.textPrimary,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header
              const Text(
                'Choose Your Plan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ).animate().fade().slideY(begin: -0.2),

              const SizedBox(height: 12),

              const Text(
                'Unlock unlimited transcriptions and advanced AI superpowers.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ).animate().fade(delay: 100.ms).slideY(begin: -0.2),

              const SizedBox(height: 32),

              // Billing Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleBtn('Monthly', !_isAnnual),
                    _buildToggleBtn('Annually (Save 20%)', _isAnnual),
                  ],
                ),
              ).animate().fade(delay: 200.ms).scale(),

              const SizedBox(height: 32),

              // PRO PLAN (Highlighted - shown first for Decoy Effect)
              _buildPricingCard(
                title: 'Pro Plan',
                icon: Icons.auto_awesome_rounded,
                price: _isAnnual ? '₹5,990' : '₹599',
                subtitle: _isAnnual ? 'per year' : 'per month',
                isPopular: true,
                isCurrent: false,
                features: [
                  '15 hours (900 mins) / month',
                  'Max 4 hours per meeting',
                  'Voice Recognition Training',
                  'Custom Vocabulary Settings',
                  'Advanced Action Items Export',
                ],
                buttonText: 'Upgrade to Pro',
                onTap: () {},
              ).animate().fade(delay: 300.ms).slideY(begin: 0.1),

              const SizedBox(height: 24),

              // BASIC PLAN
              _buildPricingCard(
                title: 'Basic Plan',
                icon: Icons.bolt_rounded,
                price: _isAnnual ? '₹2,990' : '₹299',
                subtitle: _isAnnual ? 'per year' : 'per month',
                isPopular: false,
                isCurrent: false,
                features: [
                  '5 hours (300 mins) / month',
                  'Max 1 hour per meeting',
                  'Basic AI Summaries',
                  'Standard Transcription',
                ],
                buttonText: 'Choose Basic',
                onTap: () {},
              ).animate().fade(delay: 400.ms).slideY(begin: 0.1),

              const SizedBox(height: 24),

              // GROUP PLAN
              _buildPricingCard(
                title: 'Team Plan',
                icon: Icons.groups_rounded,
                price: _isAnnual ? '₹19,990' : '₹1,999',
                subtitle: _isAnnual ? 'per year' : 'per month',
                isPopular: false,
                isCurrent: false,
                features: [
                  'Up to 5 Team Members',
                  '50 hours shared / month',
                  'Shared Custom Vocabulary',
                  'Collaborative Meeting Notes',
                ],
                buttonText: 'Start Team Trial',
                onTap: () {},
              ).animate().fade(delay: 500.ms).slideY(begin: 0.1),

              const SizedBox(height: 32),

              // FREE PLAN (Muted at bottom)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Plan: Free',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '2 hours/month • Max 40 mins/meeting',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: AppTheme.primaryColor,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Limits reset in 12 days',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fade(delay: 600.ms),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleBtn(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isAnnual = text.contains('Annually');
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required IconData icon,
    required String price,
    required String subtitle,
    required bool isPopular,
    bool isCurrent = false,
    required List<String> features,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: isPopular
            ? const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isPopular ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular
              ? Colors.transparent
              : Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPopular
                ? const Color(0xFF0F172A).withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isPopular)
            Positioned(
              top: -12,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryColor, Color(0xFF3B82F6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'MOST POPULAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      color: isPopular
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isPopular ? Colors.white : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: isPopular ? Colors.white : AppTheme.primaryColor,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isPopular
                              ? Colors.white70
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: isPopular
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                ...features.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: isPopular
                                ? AppTheme.primaryColor
                                : const Color(0xFF10B981),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: TextStyle(
                              fontSize: 14,
                              color: isPopular
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : AppTheme.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isCurrent ? null : onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular
                          ? AppTheme.primaryColor
                          : const Color(0xFFF1F5F9),
                      foregroundColor: isPopular
                          ? Colors.white
                          : AppTheme.primaryColor,
                      elevation: isPopular ? 8 : 0,
                      shadowColor: isPopular
                          ? AppTheme.primaryColor.withValues(alpha: 0.5)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
