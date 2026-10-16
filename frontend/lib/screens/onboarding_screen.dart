import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _onboardingData = [
    {
      'title': 'AI Meeting Assistant',
      'description':
          'Say goodbye to taking notes. Let our advanced AI capture every detail of your conversations with perfect accuracy.',
      'icon': Icons.graphic_eq_rounded,
    },
    {
      'title': 'Identify Speakers',
      'description':
          'Train the AI to recognize your voice. The app will automatically attribute quotes and action items to the right people.',
      'icon': Icons.record_voice_over_rounded,
    },
    {
      'title': 'Instant Summaries',
      'description':
          'Get immediate, professional meeting minutes and task lists delivered directly to your dashboard right after you finish.',
      'icon': Icons.auto_awesome_rounded,
    },
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Skip button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentPage < _onboardingData.length - 1)
                    TextButton(
                      onPressed: _completeOnboarding,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ).animate().fade(duration: 400.ms),
                ],
              ),
            ),

            // Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon / Illustration
                        Container(
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.08,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _onboardingData[index]['icon'],
                                size: 120,
                                color: AppTheme.primaryColor,
                              ),
                            )
                            .animate(key: ValueKey(index))
                            .scale(duration: 500.ms, curve: Curves.easeOutBack)
                            .fade(duration: 400.ms),

                        const SizedBox(height: 56),

                        // Title
                        Text(
                              _onboardingData[index]['title'],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            )
                            .animate(key: ValueKey('title_$index'))
                            .slideY(
                              begin: 0.2,
                              curve: Curves.easeOutQuad,
                              duration: 400.ms,
                            )
                            .fade(duration: 400.ms),

                        const SizedBox(height: 16),

                        // Description
                        Text(
                              _onboardingData[index]['description'],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.8,
                                ),
                                height: 1.6,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                            .animate(key: ValueKey('desc_$index'))
                            .slideY(
                              begin: 0.2,
                              curve: Curves.easeOutQuad,
                              duration: 400.ms,
                              delay: 100.ms,
                            )
                            .fade(duration: 400.ms, delay: 100.ms),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Controls
            Container(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Page Indicators
                  Row(
                    children: List.generate(
                      _onboardingData.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.only(right: 8),
                        height: 10,
                        width: _currentPage == index ? 32 : 10,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? AppTheme.primaryColor
                              : AppTheme.dividerColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  // Next / Get Started Button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: ElevatedButton(
                      key: ValueKey(_currentPage == _onboardingData.length - 1),
                      onPressed: () {
                        if (_currentPage == _onboardingData.length - 1) {
                          _completeOnboarding();
                        } else {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: _currentPage == _onboardingData.length - 1
                              ? 32
                              : 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentPage == _onboardingData.length - 1
                                ? 'Get Started'
                                : 'Next',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (_currentPage < _onboardingData.length - 1) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
