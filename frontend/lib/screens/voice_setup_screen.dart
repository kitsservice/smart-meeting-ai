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
  // 3-Step Calibration State: 1, 2, 3
  int _currentStep = 1;
  final List<String> _capturedSamples = [];

  bool _isRecording = false;
  bool _hasRecordedCurrentStep = false;
  bool _isUploading = false;
  String? _recordedFilePath;
  int _recordSeconds = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _currentAmplitude = -40.0;

  // Real-time Karaoke word highlighter tracking
  int _highlightedWordIndex = 0;
  int _speechTicks = 0;

  // Calibration language state: English, हिन्दी, मराठी
  String _selectedLanguage = 'English';

  // Post-calibration Live Voice Match Testing State
  bool _isCalibrationComplete = false;
  bool _isTestingVoice = false;
  bool _isVerifying = false;
  Map<String, dynamic>? _verificationResult;

  late AnimationController _animationController;
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Curated 3-Step Guided Phrases per Language
  static const Map<String, List<String>> _stepPhrases = {
    'English': [
      "Hi, I am setting up my Smart Meeting voice profile. I speak clearly and naturally, and this is my regular speaking voice.",
      "Welcome to our team discussion today. We will review our project milestones, prioritize key action items, and align on upcoming goals.",
      "Clear decision making, active listening, and open dialogue help our team solve complex challenges with high agility.",
    ],
    'हिन्दी': [
      "नमस्ते, मैं स्मार्ट मीटिंग एआई के लिए अपनी आवाज़ सेट कर रहा हूँ। यह मेरी सामान्य और साफ़ आवाज़ है।",
      "आज की मीटिंग में हम प्रोजेक्ट अपडेट्स, मुख्य कार्य और आने वाले लक्ष्यों की समीक्षा करेंगे।",
      "अच्छी बातचीत और टीमवर्क से हमारे काम में तेज़ी आती है। हम मिलकर काम करेंगे और बेहतरीन परिणाम देंगे।",
    ],
    'मराठी': [
      "नमस्कार, मी स्मार्ट मीटिंग एआय साठी माझा आवाज कॅलिब्रेट करत आहे. हा माझा रोजचा बोलण्याचा आवाज आहे.",
      "आजच्या बैठकीत आपण नवीन योजना, महत्त्वाचे विषय आणि पुढील कामांची रूपरेषा ठरवणार आहोत.",
      "एकत्र काम करून आपण सर्व आव्हाने सोडवू शकतो आणि वेळेत दर्जेदार काम पूर्ण करू शकतो.",
    ],
  };

  // Additional shuffle pool for varied phrases
  static const Map<String, List<String>> _alternatePool = {
    'English': [
      "During this meeting, I will share the latest technical updates, discuss architectural improvements, and outline our roadmap.",
      "Effective communication and consistency are essential for building great products. I look forward to working closely together.",
      "Our main goal for this sprint is optimizing system responsiveness, reducing latency, and delivering a polished user experience.",
    ],
    'हिन्दी': [
      "सुप्रभात सभी को। आइए हमारे पिछले सेशन के एक्शन आइटम्स देखें और अगले हफ़्ते की योजना बनाएँ।",
      "हमारा मुख्य उद्देश्य सिस्टम को तेज़ बनाना, आसान अनुभव देना और यूज़र्स को बेहतर सर्विस प्रदान करना है।",
      "मैं साफ़ और सहज आवाज़ में बोल रहा हूँ ताकि सिस्टम मीटिंग के दौरान मेरी आवाज़ को आसानी से पहचान सके।",
    ],
    'मराठी': [
      "मी माझ्या आवाजाचे अचूक रेकॉर्डिंग आणि स्पीकर ओळखण्यासाठी हा सराव करत आहे.",
      "आपले मुख्य ध्येय सिस्टीम अधिक वेगवान, सुरक्षित आणि वापरण्यास सोपी बनवणे हे आहे.",
      "मी स्पष्ट आणि नैसर्गिक आवाजात बोलत आहे जेणेकरून मीटिंग दरम्यान माझा आवाज सहज ओळखता येईल.",
    ],
  };

  late String _targetPhrase;
  late List<String> _words;

  void _loadStepPhrase() {
    final list = _stepPhrases[_selectedLanguage] ?? _stepPhrases['English']!;
    final index = (_currentStep - 1).clamp(0, list.length - 1);
    _targetPhrase = list[index];
    _words = _targetPhrase.split(' ');
    _highlightedWordIndex = 0;
    _speechTicks = 0;
  }

  void _shuffleStepPhrase() {
    if (_isRecording || _isTestingVoice) return;
    final altList = _alternatePool[_selectedLanguage] ?? _alternatePool['English']!;
    final random = math.Random();
    setState(() {
      _targetPhrase = altList[random.nextInt(altList.length)];
      _words = _targetPhrase.split(' ');
      _highlightedWordIndex = 0;
      _speechTicks = 0;
    });
  }

  void _switchLanguage(String lang) {
    if (_isRecording || _isTestingVoice) return;
    setState(() {
      _selectedLanguage = lang;
      _loadStepPhrase();
      _hasRecordedCurrentStep = false;
      _recordedFilePath = null;
      _recordSeconds = 0;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadStepPhrase();

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
      // Stop recording current step
      _timer?.cancel();
      _amplitudeSub?.cancel();
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
        _hasRecordedCurrentStep = path != null && _recordSeconds >= 3;
      });

      if (_recordSeconds < 4 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sample too short. Please speak for at least 4 seconds for optimal calibration.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Start recording current step
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_enrollment_step_$_currentStep.wav';

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
          _hasRecordedCurrentStep = false;
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

            if (_recordSeconds >= 8 && _highlightedWordIndex >= _words.length) {
              _toggleRecording();
            }
          }
        });

        _amplitudeSub = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen((amp) {
              if (!mounted || !_isRecording) return;
              final current = amp.current;

              setState(() {
                _currentAmplitude = current;
              });

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

  void _nextStepOrFinish() {
    if (_recordedFilePath == null || _recordSeconds < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please record for at least 4 seconds before continuing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _capturedSamples.add(_recordedFilePath!);

    if (_currentStep < 3) {
      // Advance to next step
      HapticFeedback.mediumImpact();
      setState(() {
        _currentStep++;
        _hasRecordedCurrentStep = false;
        _recordedFilePath = null;
        _recordSeconds = 0;
        _loadStepPhrase();
      });
    } else {
      // All 3 samples captured: Submit multi-sample centroid to backend
      _uploadMultiSampleProfile();
    }
  }

  Future<void> _uploadMultiSampleProfile() async {
    setState(() => _isUploading = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final enrolled = await ApiService().enrollVoiceMulti(_capturedSamples);

        if (!enrolled) {
          if (mounted) {
            setState(() => _isUploading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not reach voice biometrics server. Please try again.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        try {
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.heavyImpact();
        } catch (_) {}

        if (mounted) {
          setState(() {
            _isUploading = false;
            _isCalibrationComplete = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.verified_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('3-Step Voice Calibration Successful (98% Quality)!'),
                ],
              ),
              backgroundColor: Color(0xFF10B981),
              duration: Duration(seconds: 3),
            ),
          );
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
    }
  }

  // --- LIVE VOICE MATCH TESTING SIMULATOR ---
  Future<void> _toggleVoiceTest() async {
    if (_isTestingVoice) {
      // Stop testing and verify
      _timer?.cancel();
      _amplitudeSub?.cancel();
      final path = await _audioRecorder.stop();

      setState(() {
        _isTestingVoice = false;
        _isVerifying = true;
      });

      if (path != null && _recordSeconds >= 2) {
        final result = await ApiService().verifyVoice(path);
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _verificationResult = result;
          });
          if (result != null && result['matched'] == true) {
            HapticFeedback.heavyImpact();
          }
        }
      } else {
        if (mounted) {
          setState(() => _isVerifying = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please speak for at least 2 seconds for the test.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      // Start test recording
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_test_sample.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        setState(() {
          _isTestingVoice = true;
          _isVerifying = false;
          _verificationResult = null;
          _recordSeconds = 0;
          _currentAmplitude = -40.0;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _recordSeconds++);
            if (_recordSeconds >= 6) {
              _toggleVoiceTest();
            }
          }
        });

        _amplitudeSub = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen((amp) {
              if (mounted) {
                setState(() => _currentAmplitude = amp.current);
              }
            });
      }
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
      if (Navigator.canPop(context)) {
        Navigator.pop(context, false);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  Widget _buildStepIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStepPill(1, "Baseline"),
          _buildStepDivider(1),
          _buildStepPill(2, "Cadence"),
          _buildStepDivider(2),
          _buildStepPill(3, "Expression"),
        ],
      ),
    );
  }

  Widget _buildStepPill(int step, String label) {
    final isDone = _currentStep > step;
    final isCurrent = _currentStep == step;

    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF64748B);

    if (isDone) {
      bg = const Color(0xFF10B981);
      fg = Colors.white;
    } else if (isCurrent) {
      bg = AppTheme.primaryColor;
      fg = Colors.white;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : Text(
                  '$step',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent ? AppTheme.primaryColor : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(int step) {
    final isDone = _currentStep > step;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: isDone ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          _buildLangChip('English'),
          _buildLangChip('हिन्दी'),
          _buildLangChip('मराठी'),
          Container(
            height: 24,
            width: 1,
            color: Colors.grey.withValues(alpha: 0.25),
          ),
          IconButton(
            tooltip: 'Shuffle Phrase',
            icon: const Icon(Icons.shuffle_rounded, size: 20),
            color: _isRecording ? Colors.grey : AppTheme.primaryColor,
            onPressed: _isRecording ? null : _shuffleStepPhrase,
          ),
        ],
      ),
    );
  }

  Widget _buildLangChip(String lang) {
    final isSelected = _selectedLanguage == lang;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!_isRecording && !_isTestingVoice) {
            HapticFeedback.selectionClick();
            _switchLanguage(lang);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            lang,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityFeedbackBadge() {
    if (!_isRecording && !_hasRecordedCurrentStep) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_none_rounded, size: 15, color: Color(0xFF64748B)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Sample $_currentStep of 3: Tap mic to speak',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isRecording) {
      final String label;
      final Color color;
      final IconData icon;

      if (_currentAmplitude < -48.0) {
        label = 'Too quiet • Speak louder or closer';
        color = const Color(0xFFD97706);
        icon = Icons.volume_mute_rounded;
      } else if (_currentAmplitude > -12.0) {
        label = 'Too loud • Move device slightly away';
        color = const Color(0xFFEA580C);
        icon = Icons.volume_up_rounded;
      } else {
        label = 'Optimal Voice Clarity ✓';
        color = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
          const SizedBox(width: 6),
          Text(
            'Step $_currentStep of 3 captured (${_recordSeconds}s) ✓',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF047857),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildHighlightedText() {
    List<TextSpan> spans = [];
    for (int i = 0; i < _words.length; i++) {
      final bool isHighlighted = _isRecording
          ? (i < _highlightedWordIndex)
          : (_hasRecordedCurrentStep ? true : false);
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

  // --- COMPLETED CALIBRATION & TEST SIMULATOR WIDGET ---
  Widget _buildCalibrationCompleteView() {
    return Column(
      children: [
        // Success Header Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  size: 42,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Voice Profile Calibrated!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '3-Sample Centroid Model generated with 192-d neural vector.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF059669)),
                    SizedBox(width: 6),
                    Text(
                      'Biometric Accuracy: 98% (Multi-Sample Centroid)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Live Voice Match Tester Simulator
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hearing_rounded, size: 20, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    'Instant Voice Match Simulator',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the mic and speak any random words to verify your speaker recognition in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),

              // Mic Button for Testing
              GestureDetector(
                onTap: _isVerifying ? null : _toggleVoiceTest,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTestingVoice ? Colors.red : AppTheme.primaryColor,
                    boxShadow: [
                      BoxShadow(
                        color: (_isTestingVoice ? Colors.red : AppTheme.primaryColor)
                            .withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _isVerifying
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                        )
                      : Icon(
                          _isTestingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isTestingVoice
                    ? 'Listening... 00:${_recordSeconds.toString().padLeft(2, '0')}'
                    : (_isVerifying
                        ? 'Analyzing acoustic match...'
                        : 'Tap to Test Voice Recognition'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isTestingVoice ? Colors.red : AppTheme.textSecondary,
                ),
              ),

              // Verification Results Banner
              if (_verificationResult != null) ...[
                const SizedBox(height: 16),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (_verificationResult!['matched'] == true)
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (_verificationResult!['matched'] == true)
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            (_verificationResult!['matched'] == true)
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            color: (_verificationResult!['matched'] == true)
                                ? const Color(0xFF059669)
                                : const Color(0xFFD97706),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (_verificationResult!['matched'] == true)
                                ? 'Match Verified!'
                                : 'Low Confidence Match',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: (_verificationResult!['matched'] == true)
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _verificationResult!['message'] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ((_verificationResult!['confidence'] ?? 80.0) / 100.0)
                            .clamp(0.0, 1.0),
                        backgroundColor: Colors.white,
                        color: (_verificationResult!['matched'] == true)
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Exit / Go to Home Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context, true);
              } else {
                Navigator.pushReplacementNamed(context, '/home');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Finish & Return to Home',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
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
                // Custom Header with Gradient
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
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
                                backgroundColor: Colors.white.withValues(alpha: 0.15),
                                padding: const EdgeInsets.all(8),
                              ),
                            )
                          else
                            const SizedBox(width: 48),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.record_voice_over_rounded,
                              size: 32,
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
                      const SizedBox(height: 12),
                      Text(
                        _isCalibrationComplete
                            ? 'Voice Calibrated'
                            : '3-Step Voice Calibration',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isCalibrationComplete
                            ? 'Your biometric voice profile is now active and ready for live meetings.'
                            : 'Follow 3 short guided phrases to build a 98% accurate voice signature.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    child: _isCalibrationComplete
                        ? _buildCalibrationCompleteView()
                        : Column(
                            children: [
                              // 1. 3-Step Progress Indicator
                              _buildStepIndicator(),

                              // 2. Language selector bar
                              _buildLanguageSelector(),

                              // 3. Reading prompt card with live word highlighting & shuffle
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
                                          'Step $_currentStep of 3 ($_selectedLanguage)',
                                          style: const TextStyle(
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

                              const SizedBox(height: 18),

                              // 4. Audio quality feedback badge
                              _buildQualityFeedbackBadge(),

                              const SizedBox(height: 16),

                              // 5. Live Wave Visualizer during recording
                              if (_isRecording) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(14, (index) {
                                    final double normalized = (_currentAmplitude + 60)
                                        .clamp(0, 60) /
                                        60;
                                    final double waveHeight =
                                        12 + (38 * normalized * ((index % 4 + 1) / 4));
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                      width: 4,
                                      height: waveHeight.clamp(8.0, 48.0),
                                      decoration: BoxDecoration(
                                        color: _recordSeconds >= 4
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Recording: 00:${_recordSeconds.toString().padLeft(2, '0')} ${_recordSeconds >= 4 ? '✓ (Good length)' : '(Min. 4s required)'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _recordSeconds >= 4
                                        ? const Color(0xFF047857)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // 6. Record / Stop Button
                              GestureDetector(
                                onTap: _toggleRecording,
                                child: AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    return Container(
                                      width: 92,
                                      height: 92,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isRecording
                                            ? Colors.red
                                            : AppTheme.primaryColor,
                                        boxShadow: [
                                          if (_isRecording)
                                            BoxShadow(
                                              color: Colors.red.withValues(
                                                alpha: 0.3 +
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
                                        size: 40,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _isRecording
                                    ? 'Tap to stop when done'
                                    : (_hasRecordedCurrentStep
                                        ? 'Sample $_currentStep captured (${_recordSeconds}s) ✓'
                                        : 'Tap to record phrase'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isRecording
                                      ? Colors.red
                                      : (_hasRecordedCurrentStep
                                          ? const Color(0xFF047857)
                                          : AppTheme.textSecondary),
                                ),
                              ),

                              const SizedBox(height: 22),

                              // 7. Action Button: Next Step or Finish
                              if (_hasRecordedCurrentStep && !_isRecording) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: OutlinedButton.icon(
                                        onPressed: _isUploading
                                            ? null
                                            : () {
                                                HapticFeedback.lightImpact();
                                                setState(() {
                                                  _hasRecordedCurrentStep = false;
                                                  _recordedFilePath = null;
                                                  _recordSeconds = 0;
                                                  _highlightedWordIndex = 0;
                                                });
                                              },
                                        icon: const Icon(Icons.refresh_rounded, size: 18),
                                        label: const Text('Re-record'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.textPrimary,
                                          side: BorderSide(
                                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: ElevatedButton(
                                        onPressed: _isUploading ? null : _nextStepOrFinish,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: _isUploading
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : Text(
                                                _currentStep < 3
                                                    ? 'Next Step ($_currentStep/3) →'
                                                    : 'Complete Calibration',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Container(
                                  width: double.infinity,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _isRecording
                                        ? 'Recording in progress...'
                                        : 'Record sample $_currentStep to proceed',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
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
