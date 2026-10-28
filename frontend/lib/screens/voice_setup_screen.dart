import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../services/api_service.dart';

class VoiceSetupScreen extends StatefulWidget {
  const VoiceSetupScreen({super.key});

  @override
  State<VoiceSetupScreen> createState() => _VoiceSetupScreenState();
}

class _VoiceSetupScreenState extends State<VoiceSetupScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _hasRecorded = false;
  bool _isUploading = false;
  String? _recordedFilePath;
  int _recordSeconds = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _currentAmplitude = -40.0;

  // Real-time Karaoke word highlighter tracking
  int _highlightedWordIndex = 0;
  int _speechTicks = 0;

  late AnimationController _animationController;
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Curated diverse phrases so every user automatically gets a different phrase
  static const List<String> _calibrationPhrases = [
    "Hi, I am setting up my Smart Meeting voice profile. I speak clearly and naturally, and this is my regular speaking voice.",
    "Welcome to our team discussion today. We will review our project milestones, prioritize key action items, and align on upcoming goals.",
    "During this meeting, I will share the latest technical updates, discuss architectural improvements, and outline our product roadmap.",
    "Effective communication and teamwork drive our success. Let us collaborate smoothly, solve challenges together, and deliver outstanding results.",
    "Good morning everyone. Let us review the action items from our previous session and plan our next steps for this quarter.",
    "I am calibrating my microphone for real-time meeting transcription, speaker identification, and automated AI summary generation.",
    "Innovation, creativity, and consistency are essential for building great products. I look forward to working closely with everyone on this project.",
    "The quick brown fox jumps over the lazy dog while we discuss our quarterly business review, strategic priorities, and team accomplishments.",
    "Our main goal for this sprint is optimizing system responsiveness, reducing latency, and delivering a polished experience to our users.",
    "Let us carefully analyze the user feedback from our latest release and incorporate these insights into our development priorities.",
    "Clear decision making and open dialogue help our engineering team solve complex problems with high confidence and agility.",
    "Today we will walk through the customer journey, examine key conversion metrics, and plan our marketing campaign for next month.",
    "Every team member brings valuable perspective to the table, ensuring our architectural designs remain robust and future-proof.",
    "We will finalize the project timeline, confirm resource allocations, and ensure all deliverables meet our quality standards.",
    "Consistent collaboration and continuous improvement enable us to build scalable software and achieve long-term technical excellence.",
    "I speak with clarity and confidence so the system can accurately recognize my voice and attribute my contributions during meetings.",
  ];

  late String _targetPhrase;
  late List<String> _words;

  @override
  void initState() {
    super.initState();
    // Assign a unique random phrase per user/session so users never get the same text
    final user = Supabase.instance.client.auth.currentUser;
    final random = math.Random();
    int chosenIndex;
    if (user != null && user.id.isNotEmpty) {
      // Deterministically seed with user ID combined with a randomized factor
      final userHash = user.id.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7FFFFFFF);
      chosenIndex = (userHash + random.nextInt(_calibrationPhrases.length)) % _calibrationPhrases.length;
    } else {
      chosenIndex = random.nextInt(_calibrationPhrases.length);
    }

    _targetPhrase = _calibrationPhrases[chosenIndex];
    _words = _targetPhrase.split(' ');

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _animationController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      _timer?.cancel();
      _amplitudeSub?.cancel();
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
        _hasRecorded = path != null && _recordSeconds >= 3;
      });

      if (_recordSeconds < 3 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sample too short. Please speak for at least 4 seconds while reading the phrase.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Start recording
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_enrollment.wav';

        // 16kHz mono WAV is native for SpeechBrain ECAPA-TDNN biometrics
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _hasRecorded = false;
          _recordedFilePath = null;
          _recordSeconds = 0;
          _currentAmplitude = -40.0;
          _highlightedWordIndex = 0;
          _speechTicks = 0;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() {
              _recordSeconds++;
              final targetWords = (_recordSeconds * 2.2).toInt();
              if (_highlightedWordIndex < targetWords && _highlightedWordIndex < _words.length) {
                _highlightedWordIndex = targetWords.clamp(0, _words.length);
              }
            });

            if (_recordSeconds >= 6 && _highlightedWordIndex >= _words.length) {
              _toggleRecording();
            }
          }
        });

        // Real-time amplitude listener: advances Karaoke words as user speaks
        _amplitudeSub = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen((amp) {
              if (!mounted || !_isRecording) return;
              final current = amp.current;

              setState(() {
                _currentAmplitude = current;
              });

              // Sensitive down to -52 dB on mobile microphones
              if (current > -52.0) {
                _speechTicks++;
                if (_speechTicks % 2 == 0) {
                  if (_highlightedWordIndex < _words.length) {
                    setState(() {
                      _highlightedWordIndex++;
                    });
                  }
                }
              }
            });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')),
          );
        }
      }
    }
  }

  Future<void> _finishSetup() async {
    if (_recordedFilePath == null || _recordSeconds < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please record for at least 4 seconds before saving.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        // 1. Upload voice sample to backend to extract 192-dim neural biometrics embedding
        final enrolled = await ApiService().enrollVoice(_recordedFilePath!);

        if (!enrolled) {
          if (mounted) {
            setState(() => _isUploading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not reach AI voice biometrics server. Please ensure the server is running and try again.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // 2. Play confirmation sound & haptic feedback
        try {
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.mediumImpact();
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Voice profile calibrated and saved!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          if (Navigator.canPop(context)) {
            Navigator.pop(context, true);
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving voice profile: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }

    if (mounted) {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _skipCalibration() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('users')
            .update({'voice_profile_url': 'skipped'})
            .eq('id', user.id);
      } catch (e) {
        debugPrint('Error updating skip voice status: $e');
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice setup skipped. You can calibrate anytime in Settings.'),
          duration: Duration(seconds: 2),
        ),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context, false);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  List<TextSpan> _buildHighlightedText() {
    List<TextSpan> spans = [];
    for (int i = 0; i < _words.length; i++) {
      final bool isHighlighted = _isRecording
          ? (i < _highlightedWordIndex)
          : (_hasRecorded ? true : false);
      final bool isCurrentWord = _isRecording && (i == _highlightedWordIndex);

      spans.add(
        TextSpan(
          text: '${_words[i]} ',
          style: TextStyle(
            fontSize: 18,
            fontWeight: (isHighlighted || isCurrentWord)
                ? FontWeight.bold
                : FontWeight.w500,
            color: isCurrentWord
                ? const Color(0xFF2563EB)
                : (isHighlighted
                    ? const Color(0xFF1D4ED8)
                    : (_isRecording
                        ? AppTheme.textPrimary.withValues(alpha: 0.35)
                        : AppTheme.textPrimary)),
            backgroundColor: isCurrentWord
                ? const Color(0xFF2563EB).withValues(alpha: 0.14)
                : Colors.transparent,
            height: 1.6,
          ),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context, true);
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: SafeArea(
          child: ResponsiveContentWrapper(
            maxWidth: 580.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // Custom Header with Gradient & Centered Icon
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (canPop)
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              padding: const EdgeInsets.all(8),
                            ),
                          )
                        else
                          const SizedBox(width: 48),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(999),
                            ),
                          ),
                          child: const Icon(
                            Icons.record_voice_over_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                        TextButton(
                          onPressed: _skipCalibration,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  const Text(
                    'Voice Calibration',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Read the phrase below so Smart Meeting AI recognizes your voice during meetings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    // Reading prompt card with live word highlighting & shuffle
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _isRecording
                            ? const Color(0xFFEFF6FF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isRecording
                              ? const Color(0xFF3B82F6)
                              : AppTheme.primaryColor.withValues(alpha: 0.12),
                          width: _isRecording ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isRecording
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.1)
                                : AppTheme.primaryColor.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Personalized voice sample badge (no manual change phrase option)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.record_voice_over_rounded,
                                size: 16,
                                color: AppTheme.primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Personalized Reading Sample',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Icon(
                            Icons.format_quote_rounded,
                            size: 28,
                            color: _isRecording
                                ? const Color(0xFF2563EB)
                                : AppTheme.primaryColor.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 8),
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              children: _buildHighlightedText(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Live Wave Visualizer during recording
                    if (_isRecording) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(12, (index) {
                          final double normalized = (_currentAmplitude + 60)
                              .clamp(0, 60) /
                              60;
                          final double waveHeight =
                              12 + (36 * normalized * ((index % 3 + 1) / 3));
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width: 4,
                            height: waveHeight.clamp(8.0, 48.0),
                            decoration: BoxDecoration(
                              color: _recordSeconds >= 4
                                  ? Colors.green
                                  : const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Recording: 00:${_recordSeconds.toString().padLeft(2, '0')} ${_recordSeconds >= 4 ? '✓ (Good length!)' : '(Speak for 4+ sec)'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _recordSeconds >= 4
                              ? Colors.green[700]
                              : const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Record button
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? Colors.red
                                  : AppTheme.primaryColor,
                              boxShadow: [
                                if (_isRecording)
                                  BoxShadow(
                                    color: Colors.red.withValues(
                                      alpha:
                                          0.3 +
                                          (_animationController.value * 0.4),
                                    ),
                                    spreadRadius:
                                        _animationController.value * 20,
                                    blurRadius: 15,
                                  ),
                                if (!_isRecording)
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.3,
                                    ),
                                    spreadRadius: 2,
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                              ],
                            ),
                            child: Icon(
                              _isRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isRecording
                          ? 'Tap to stop when done'
                          : (_hasRecorded
                              ? 'Voice captured (${_recordSeconds}s) ✓'
                              : 'Tap to start speaking'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _isRecording
                            ? Colors.red
                            : (_hasRecorded
                                ? Colors.green[700]
                                : AppTheme.textSecondary),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Complete Setup button
                    AnimatedOpacity(
                      opacity: (_hasRecorded && !_isRecording) ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: AppTheme.primaryGradient,
                          boxShadow: [
                            if (_hasRecorded && !_isRecording)
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: (_isUploading || (!_hasRecorded && !_isRecording))
                              ? null
                              : _finishSetup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isUploading
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Calibrating AI Voice...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  _isRecording
                                      ? 'Finish & Save Voice'
                                      : (_hasRecorded
                                          ? 'Complete Setup'
                                          : 'Record Phrase First'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
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
        ),
      ),
    ),
  );
}
}
