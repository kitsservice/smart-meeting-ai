import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true; // Toggle between Login and Sign Up
  bool _rememberMe = true;
  bool _obscurePassword = true;

  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        if (!mounted) return;
        try {
          final user = data.session?.user;
          if (user != null) {
            final profile = await Supabase.instance.client
                .from('users')
                .select('voice_profile_url')
                .eq('id', user.id)
                .single();
            if (profile['voice_profile_url'] == null ||
                profile['voice_profile_url'].toString().isEmpty) {
              Navigator.pushReplacementNamed(context, '/voice_setup');
            } else {
              Navigator.pushReplacementNamed(context, '/home');
            }
          }
        } catch (e) {
          Navigator.pushReplacementNamed(context, '/voice_setup');
        }
      }
    });
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    if (savedEmail != null && savedPassword != null) {
      setState(() {
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveOrClearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailController.text.trim());
      await prefs.setString('saved_password', _passwordController.text);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );

        await _saveOrClearCredentials();

        if (mounted) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            try {
              final data = await Supabase.instance.client
                  .from('users')
                  .select('voice_profile_url')
                  .eq('id', user.id)
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
          }
        }
      } else {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created! Please check your email inbox to verify your account before logging in.'),
              duration: Duration(seconds: 5),
            ),
          );
          setState(() {
            _isLogin = true;
            _passwordController.clear();
          });
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An unexpected error occurred')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.smartmeeting://login-callback',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not sign in with Google')),
        );
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController(text: _emailController.text);
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Reset Password', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter your email address and we will send you a link to reset your password.',
                    style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Email Address',
                        hintStyle: GoogleFonts.inter(
                          color: const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: const Icon(Icons.mail_outline_rounded, color: Color(0xFF2563EB)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final email = resetEmailController.text.trim();
                          if (email.isEmpty) return;

                          setState(() => isSending = true);
                          try {
                            await Supabase.instance.client.auth.resetPasswordForEmail(email);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Password reset link sent!')),
                              );
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Error sending password reset link.')),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setState(() => isSending = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Send Link', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F5FA),
      body: Stack(
        children: [
          // Background waves
          Positioned.fill(
            child: CustomPaint(
              painter: WavesPainter(),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 10),
                  // App Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1D4ED8).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildSoundBar(14),
                          const SizedBox(width: 4),
                          _buildSoundBar(24),
                          const SizedBox(width: 4),
                          _buildSoundBar(34),
                          const SizedBox(width: 4),
                          _buildSoundBar(24),
                          const SizedBox(width: 4),
                          _buildSoundBar(14),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // App Title
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Smart ',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        TextSpan(
                          text: 'Meeting',
                          style: TextStyle(color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Subtitle
                  Text(
                    'Connect  •  Collaborate  •  Get Things Done',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Login Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLogin ? 'Welcome Back' : 'Create Account',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isLogin ? 'Sign in to your account to continue' : 'Sign up for a new account',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        if (!_isLogin) ...[
                          // Full Name Field
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: TextField(
                              controller: _nameController,
                              keyboardType: TextInputType.name,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF0F172A),
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Full Name',
                                hintStyle: GoogleFonts.inter(
                                  color: const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: const Icon(
                                  Icons.person_outline_rounded,
                                  color: Color(0xFF2563EB),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Email Field
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: GoogleFonts.inter(
                              color: const Color(0xFF0F172A),
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Email Address',
                              hintStyle: GoogleFonts.inter(
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: const Icon(
                                Icons.mail_outline_rounded,
                                color: Color(0xFF2563EB),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Password Field
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: GoogleFonts.inter(
                              color: const Color(0xFF0F172A),
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              hintStyle: GoogleFonts.inter(
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: Color(0xFF2563EB),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        if (_isLogin) ...[
                          // Remember me & Forgot Password
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _rememberMe,
                                  onChanged: (val) {
                                    setState(() => _rememberMe = val ?? true);
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  activeColor: const Color(0xFF2563EB),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Remember Me',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF0F172A),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _showForgotPasswordDialog,
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: const Color(0xFF2563EB),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ] else ...[
                          const SizedBox(height: 8),
                        ],
                        
                        // Sign In / Create Account Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _authenticate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(_isLogin ? Icons.login_rounded : Icons.person_add_rounded, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isLogin ? 'Sign In' : 'Create Account',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // OR divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: const Color(0xFFE2E8F0))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: const Color(0xFFE2E8F0))),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Continue with Google Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _signInWithGoogle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Simple Google Logo using Text/Icon as placeholder since we don't have asset
                                _buildGoogleIcon(),
                                const SizedBox(width: 12),
                                Text(
                                  'Continue with Google',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    color: const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Sign Up Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLogin ? 'New to Smart Meeting? ' : 'Already have an account? ',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _passwordController.clear();
                            _nameController.clear();
                          });
                        },
                        child: Text(
                          _isLogin ? 'Sign Up' : 'Sign In',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF2563EB),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundBar(double height) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Center(
        child: Image.asset(
          'assets/images/google_logo.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // We draw soft, light blue blobs to mimic the image background
    
    // Top Left Wave
    final Paint paint1 = Paint()
      ..color = const Color(0xFFD6E4FF).withOpacity(0.6)
      ..style = PaintingStyle.fill;
    
    final path1 = Path();
    path1.moveTo(0, 0);
    path1.lineTo(size.width * 0.4, 0);
    path1.quadraticBezierTo(
      size.width * 0.3, size.height * 0.15,
      0, size.height * 0.25,
    );
    path1.close();
    canvas.drawPath(path1, paint1);

    // Top Right Wave
    final Paint paint2 = Paint()
      ..color = const Color(0xFFD6E4FF).withOpacity(0.4)
      ..style = PaintingStyle.fill;
    
    final path2 = Path();
    path2.moveTo(size.width, 0);
    path2.lineTo(size.width * 0.6, 0);
    path2.quadraticBezierTo(
      size.width * 0.8, size.height * 0.15,
      size.width, size.height * 0.35,
    );
    path2.close();
    canvas.drawPath(path2, paint2);

    // Bottom Waves
    final Paint paint3 = Paint()
      ..color = const Color(0xFFD6E4FF).withOpacity(0.5)
      ..style = PaintingStyle.fill;
      
    final path3 = Path();
    path3.moveTo(0, size.height);
    path3.lineTo(0, size.height * 0.85);
    path3.quadraticBezierTo(
      size.width * 0.3, size.height * 0.95,
      size.width * 0.6, size.height * 0.9,
    );
    path3.quadraticBezierTo(
      size.width * 0.8, size.height * 0.85,
      size.width, size.height * 0.95,
    );
    path3.lineTo(size.width, size.height);
    path3.close();
    canvas.drawPath(path3, paint3);
    
    // Bottom Wave 2 (darker)
    final Paint paint4 = Paint()
      ..color = const Color(0xFFADC8FF).withOpacity(0.6)
      ..style = PaintingStyle.fill;
      
    final path4 = Path();
    path4.moveTo(0, size.height);
    path4.lineTo(0, size.height * 0.92);
    path4.quadraticBezierTo(
      size.width * 0.2, size.height * 0.98,
      size.width * 0.5, size.height * 0.95,
    );
    path4.quadraticBezierTo(
      size.width * 0.8, size.height * 0.92,
      size.width, size.height * 0.98,
    );
    path4.lineTo(size.width, size.height);
    path4.close();
    canvas.drawPath(path4, paint4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
