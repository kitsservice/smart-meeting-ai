import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_queue.dart';
import '../theme/app_theme.dart';

class ActiveMeetingScreen extends ConsumerStatefulWidget {
  const ActiveMeetingScreen({super.key});

  @override
  ConsumerState<ActiveMeetingScreen> createState() =>
      _ActiveMeetingScreenState();
}

class _ActiveMeetingScreenState extends ConsumerState<ActiveMeetingScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool isRecording = false;
  bool isProcessing = false;

  int _recordDuration = 0;
  Timer? _timer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/meeting_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: path,
        );

        setState(() => isRecording = true);
        _startTimer();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required.')),
          );
        }
      }
    } catch (e) {
      print('Failed to start recording: $e');
    }
  }

  Future<void> _pauseOrResumeRecording() async {
    if (isRecording) {
      await _audioRecorder.pause();
      setState(() => isRecording = false);
      _animationController.stop();
    } else {
      await _audioRecorder.resume();
      setState(() => isRecording = true);
      _animationController.repeat();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (isRecording) setState(() => _recordDuration++);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> endMeeting() async {
    // Stop recording immediately to ensure file is saved correctly
    String? savedPath;
    if (isRecording) {
      savedPath = await _audioRecorder.stop();
      setState(() => isRecording = false);
      _animationController.stop();
    }

    final bool? shouldSave = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Icon(
                Icons.stop_circle_rounded,
                color: AppTheme.dangerColor,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'End Meeting',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Are you sure you want to end this meeting? Do you want to save the transcript or discard it?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white.withOpacity(0.05),
                      ),
                      child: const Text(
                        'Discard',
                        style: TextStyle(
                          color: AppTheme.dangerColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save & Generate',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (shouldSave == null) return;

    setState(() => isProcessing = true);

    if (shouldSave == true && savedPath != null) {
      // Save and queue for transcription
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final meetingTitle =
          args?['title'] ??
          "Meeting ${DateTime.now().toLocal().toString().split(' ')[0]}";

      await OfflineQueueService().queueMeeting(
        meetingTitle,
        "Recorded for ${_formatDuration(_recordDuration)}",
        savedPath,
      );

      // SHOW SUCCESS NOTIFICATION
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Meeting successfully recorded and saved!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.accentColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
    // If discard, the temp file will just be overwritten next time

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Read the passed arguments for the header
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final displayTitle = args?['title'] ?? 'Live Meeting';

    return WillPopScope(
      onWillPop: () async {
        await endMeeting();
        return false; // Prevent automatic pop, endMeeting handles it
      },
      child: Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: endMeeting,
          ),
          title: Text(
            displayTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        body: Stack(
          children: [
            // Ambient Background Gradient
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(seconds: 1),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: isRecording ? 1.5 : 1.0,
                    colors: [
                      AppTheme.primaryColor.withOpacity(
                        isRecording ? 0.2 : 0.05,
                      ),
                      AppTheme.darkSurface,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // Sleek Timer
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isRecording
                                ? AppTheme.dangerColor
                                : Colors.grey,
                            borderRadius: const BorderRadius.all(Radius.circular(999)),
                            boxShadow: isRecording
                                ? [
                                    BoxShadow(
                                      color: AppTheme.dangerColor.withOpacity(
                                        0.6,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatDuration(_recordDuration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w200,
                            letterSpacing: 2,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Center(
                      child: isProcessing
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: AppTheme.primaryColor,
                                ),
                                SizedBox(height: 24),
                                Text(
                                  'Processing Transcript...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            )
                          : RepaintBoundary(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Premium Pulse Rings
                                  ...List.generate(3, (index) {
                                    return AnimatedBuilder(
                                      animation: _animationController,
                                      builder: (context, child) {
                                        final delay = index * 0.33;
                                        double value =
                                            (_animationController.value +
                                                delay) %
                                            1.0;
                                        final size = 120 + (value * 200);
                                        return Container(
                                          width: size,
                                          height: size,
                                          decoration: BoxDecoration(
                                            borderRadius: const BorderRadius.all(Radius.circular(999)),
                                            color: AppTheme.primaryColor
                                                .withOpacity(
                                                  isRecording
                                                      ? (1.0 - value) * 0.15
                                                      : 0,
                                                ),
                                            border: Border.all(
                                              color: AppTheme.primaryColor
                                                  .withOpacity(
                                                    isRecording
                                                        ? (1.0 - value) * 0.3
                                                        : 0,
                                                  ),
                                              width: 1,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }),
                                  // Central Mic Button (Glassmorphism)
                                  Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.all(Radius.circular(999)),
                                      color: Colors.white.withOpacity(0.05),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.1),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryColor
                                              .withOpacity(0.2),
                                          blurRadius: 40,
                                          spreadRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isRecording
                                          ? Icons.mic_rounded
                                          : Icons.mic_off_rounded,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),

                  // Floating Control Bar
                  Container(
                    margin: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 48,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildControlButton(
                          isRecording
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          isRecording ? 'Pause' : 'Resume',
                          Colors.white.withOpacity(0.1),
                          Colors.white,
                          _pauseOrResumeRecording,
                        ),
                        // End Button gets premium danger styling
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: endMeeting,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppTheme.dangerColor.withOpacity(0.2),
                                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                                  border: Border.all(
                                    color: AppTheme.dangerColor,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.dangerColor.withOpacity(
                                        0.3,
                                      ),
                                      blurRadius: 16,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.stop_rounded,
                                  color: AppTheme.dangerColor,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'End Meeting',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        _buildControlButton(
                          Icons.edit_note_rounded,
                          'Add Note',
                          Colors.white.withOpacity(0.1),
                          Colors.white,
                          _showAddNoteDialog,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ), // Closes Scaffold
    ); // Closes WillPopScope
  }

  Widget _buildControlButton(
    IconData icon,
    String label,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.all(Radius.circular(999))),
            child: Icon(icon, color: iconColor, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _showAddNoteDialog() async {
    String newNote = '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        String tempNote = '';
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Add Meeting Note',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type important points here...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  maxLines: 3,
                  onChanged: (val) => tempNote = val,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, tempNote),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Save Note',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && result.trim().isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final List<String> notes = prefs.getStringList('manual_notes') ?? [];
      notes.insert(0, result.trim());
      await prefs.setStringList('manual_notes', notes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved! It will appear in your Notes tab.'),
            backgroundColor: AppTheme.accentColor,
          ),
        );
      }
    }
  }
}
