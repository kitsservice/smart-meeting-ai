import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _introController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _navigated = false;
  Timer? _displayTimer;

  @override
  void initState() {
    super.initState();

    // Intro animation (fade and scale up)
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _introController, curve: Curves.easeIn));

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutBack),
    );

    _introController.forward();

    // Start auth resolution in parallel with the minimum branding presentation
    _resolveNavigation();
  }

  Future<String> _determineNextRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // One-time fresh start wipe: clear local cache & active session
      final hasCompletedFreshStart = prefs.getBool('fresh_start_v3') ?? false;
      if (!hasCompletedFreshStart) {
        await prefs.clear();
        await prefs.setBool('fresh_start_v3', true);
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        return '/onboarding';
      }

      final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

      if (!hasSeenOnboarding) {
        return '/onboarding';
      }

      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        try {
          final data = await Supabase.instance.client
              .from('users')
              .select('voice_profile_url, voice_embedding')
              .eq('id', session.user.id)
              .maybeSingle();

          final hasVoiceProfile = data != null &&
              ((data['voice_profile_url'] != null &&
                      data['voice_profile_url'].toString().isNotEmpty) ||
                  (data['voice_embedding'] != null));

          return hasVoiceProfile ? '/home' : '/voice_setup';
        } catch (_) {
          return '/voice_setup';
        }
      } else {
        return '/login';
      }
    } catch (_) {
      return '/login';
    }
  }

  Future<void> _resolveNavigation() async {
    // Run animation window & auth query concurrently for maximum launch speed
    final completer = Completer<void>();
    _displayTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!completer.isCompleted) completer.complete();
    });

    final routeFuture = _determineNextRoute();
    final results = await Future.wait([completer.future, routeFuture]);
    if (!mounted || _navigated) return;
    _navigated = true;

    final targetRoute = results[1] as String;
    Navigator.pushReplacementNamed(context, targetRoute);
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A clean, professional, proper vibrant blue gradient
    const gradient = LinearGradient(
      colors: [
        Color(0xFF0052D4), // Deep Blue
        Color(0xFF4364F7), // Vibrant Blue
        Color(0xFF6FB1FC), // Light Blue/Cyan
      ],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: gradient),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Premium Logo
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4364F7).withValues(alpha: 0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icon/app_icon.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                // Modern Typography
                const Text(
                  'Smart Meeting',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'AI-Powered Intelligent Summaries',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 60),
                // Loading Indicator matching the theme
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.8),
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
}
