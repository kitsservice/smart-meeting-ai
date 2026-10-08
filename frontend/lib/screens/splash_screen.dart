import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _introController;
  late AnimationController _waveController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Intro animation (fade and scale up)
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeIn),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutBack),
    );

    // Continuous wave animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _introController.forward();

    // Check auth and navigate after animation
    Timer(const Duration(milliseconds: 2500), () async {
      if (!mounted) return;
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        try {
          final data = await Supabase.instance.client
              .from('users')
              .select('voice_profile_url')
              .eq('id', session.user.id)
              .single();
          if (data['voice_profile_url'] == null ||
              data['voice_profile_url'].toString().isEmpty) {
            Navigator.pushReplacementNamed(context, '/voice_setup');
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        } catch (e) {
          Navigator.pushReplacementNamed(context, '/voice_setup');
        }
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Widget _buildSoundWave(double height, int index) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        // Offset each wave slightly to create a ripple effect
        final phaseOffset = index * 0.4;
        final scale = 0.5 + 0.5 * math.sin((_waveController.value * math.pi) + phaseOffset);
        
        return Container(
          width: 6,
          height: height * (0.6 + 0.4 * scale), // Smooth scale bounds
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8 * scale),
                blurRadius: 10 * scale,
                spreadRadius: 2 * scale,
              ),
            ],
          ),
        );
      },
    );
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
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.rectangle,
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4364F7).withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Premium AI Microphone Icon
                      const Icon(
                        Icons.mic_rounded,
                        size: 56,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Animated AI Soundwaves
                      SizedBox(
                        height: 50, // Fixed height bound for waves
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildSoundWave(24, 0),
                            _buildSoundWave(40, 1),
                            _buildSoundWave(50, 2),
                            _buildSoundWave(36, 3),
                            _buildSoundWave(28, 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // Modern Typography
                const Text(
                  'Smart Meeting AI',
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
