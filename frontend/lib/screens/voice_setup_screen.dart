import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';
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

  late AnimationController _animationController;
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Real-time speech tracking
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isSpeechAvailable = false;
  String _recognizedText = "";

  final String _targetPhrase =
      "Hi, I am setting up my Smart Meeting voice profile. I speak clearly and naturally, and this is my regular speaking voice.";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _isSpeechAvailable = await _speechToText.initialize();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioRecorder.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      final path = await _audioRecorder.stop();
      if (_isSpeechAvailable) await _speechToText.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
        _hasRecorded = path != null;
      });
    } else {
      // Start recording
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_enrollment.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, bitRate: 128000),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _hasRecorded = false;
          _recordedFilePath = null;
          _recognizedText = "";
        });

        if (_isSpeechAvailable) {
          _speechToText.listen(
            onResult: (result) {
              setState(() {
                _recognizedText = result.recognizedWords;
              });
            },
            cancelOnError: true,
            partialResults: true,
          );
        }
      }
    }
  }

  Future<void> _finishSetup() async {
    if (_recordedFilePath == null) return;

    setState(() => _isUploading = true);

    // Strict Validation Check
    if (_isSpeechAvailable && _recognizedText.isNotEmpty) {
      List<String> targetWords = _targetPhrase
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .split(' ');
      String recLower = _recognizedText.toLowerCase().replaceAll(
        RegExp(r'[^\w\s]'),
        '',
      );

      int matchCount = 0;
      for (String word in targetWords) {
        if (word.length > 2 && recLower.contains(word)) {
          // Only check significant words
          matchCount++;
        }
      }

      int totalSignificantWords = targetWords.where((w) => w.length > 2).length;
      if (matchCount < (totalSignificantWords * 0.7).floor()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Warning: Please read the FULL phrase clearly before saving.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isUploading = false);
        return;
      }
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final success = await ApiService().enrollVoice(_recordedFilePath!);

        if (success) {
          // Update local DB marker so we don't ask again
          await Supabase.instance.client.from('users').upsert({
            'id': user.id,
            'voice_profile_url': 'enrolled_in_ai',
          });

          if (mounted) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save voice profile.')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error uploading voice: $e')));
      }
    }

    setState(() => _isUploading = false);
  }

  List<TextSpan> _buildHighlightedText() {
    List<String> targetWords = _targetPhrase.split(' ');

    // Count frequencies of words spoken so far
    String recLower = _recognizedText.toLowerCase().replaceAll(
      RegExp(r'[^\w\s]'),
      '',
    );
    List<String> spokenWords = recLower
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    Map<String, int> spokenCounts = {};
    for (String w in spokenWords) {
      spokenCounts[w] = (spokenCounts[w] ?? 0) + 1;
    }

    Map<String, int> targetUsedCounts = {};

    List<TextSpan> spans = [];
    for (String word in targetWords) {
      String cleanWord = word.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

      bool isMatch = false;
      if (cleanWord.isNotEmpty) {
        int used = targetUsedCounts[cleanWord] ?? 0;
        int spoken = spokenCounts[cleanWord] ?? 0;

        // If the user has spoken this word more times than we've highlighted it, highlight it!
        if (spoken > used) {
          isMatch = true;
          targetUsedCounts[cleanWord] = used + 1;
        }
      }

      spans.add(
        TextSpan(
          text: '$word ',
          style: TextStyle(
            fontSize: 20, // Slightly larger for better readability
            fontWeight: isMatch ? FontWeight.bold : FontWeight.w500,
            color: isMatch
                ? AppTheme
                      .primaryColor // Professional Corporate Blue highlight
                : (_isRecording
                      ? AppTheme.textPrimary.withOpacity(0.3)
                      : AppTheme.textPrimary),
            height: 1.6,
          ),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Custom Header with Gradient
            Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: const BorderRadius.all(Radius.circular(999)),
                    ),
                    child: const Icon(
                      Icons.voice_chat,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Voice Calibration',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Read the phrase below so the AI can recognize you in meetings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  children: [
                    // Reading prompt card
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.red.withOpacity(0.05)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _isRecording
                                  ? Colors.red.withOpacity(
                                      0.5 + (_animationController.value * 0.5),
                                    )
                                  : AppTheme.primaryColor.withOpacity(0.1),
                              width: _isRecording ? 2.0 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _isRecording
                                    ? Colors.red.withOpacity(
                                        0.1 +
                                            (_animationController.value * 0.2),
                                      )
                                    : AppTheme.primaryColor.withOpacity(0.05),
                                blurRadius: 30,
                                spreadRadius: _isRecording
                                    ? (_animationController.value * 10)
                                    : 0,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.format_quote_rounded,
                                size: 40,
                                color: _isRecording
                                    ? Colors.red.withOpacity(0.5)
                                    : AppTheme.primaryColor.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  children: _buildHighlightedText(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const Spacer(),

                    // Record button
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.all(Radius.circular(999)),
                              color: _isRecording
                                  ? Colors.red
                                  : AppTheme.primaryColor,
                              boxShadow: [
                                if (_isRecording)
                                  BoxShadow(
                                    color: Colors.red.withOpacity(
                                      0.3 + (_animationController.value * 0.4),
                                    ),
                                    spreadRadius:
                                        _animationController.value * 30,
                                    blurRadius: 20,
                                  ),
                                if (!_isRecording)
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withOpacity(
                                      0.3,
                                    ),
                                    spreadRadius: 4,
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                              ],
                            ),
                            child: Icon(
                              _isRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isRecording
                          ? 'Listening...'
                          : (_hasRecorded
                                ? 'Voice saved! Tap to retry.'
                                : 'Tap to start recording'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isRecording
                            ? Colors.red
                            : AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Next button
                    AnimatedOpacity(
                      opacity: (_hasRecorded && !_isRecording) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: AppTheme.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: (_hasRecorded && !_isRecording)
                              ? _finishSetup
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Complete Setup',
                            style: TextStyle(
                              fontSize: 18,
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
    );
  }
}
