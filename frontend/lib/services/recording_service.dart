import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'foreground_service.dart';

class MeetingRecordingService extends ChangeNotifier {
  static final MeetingRecordingService _instance =
      MeetingRecordingService._internal();
  factory MeetingRecordingService() => _instance;
  MeetingRecordingService._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  AudioRecorder get recorder => _audioRecorder;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _hasStarted = false;
  bool get hasStarted => _hasStarted;

  bool _isParticipant = false;
  bool get isParticipant => _isParticipant;

  bool _isInterrupted = false;
  bool get isInterrupted => _isInterrupted;

  String _meetingTitle = 'Live Meeting';
  String get meetingTitle => _meetingTitle;

  String? _roomCode;
  String? get roomCode => _roomCode;

  String? _savedPath;
  String? get savedPath => _savedPath;

  int _recordDuration = 0;
  int get recordDuration => _recordDuration;

  Timer? _timer;
  RealtimeChannel? roomChannel;
  List<Map<String, dynamic>> participants = [];

  StreamSubscription<RecordState>? _stateSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  double _currentAmplitude = 0.0;
  double get currentAmplitude => _currentAmplitude;

  final List<double> _waveformSamples = List.filled(28, 0.06);
  List<double> get waveformSamples => List.unmodifiable(_waveformSamples);

  /// High-frequency notifiers for real-time waveform visualizers without triggering
  /// full-screen rebuilds on the parent widget tree.
  final ValueNotifier<List<double>> waveformNotifier =
      ValueNotifier<List<double>>(List.filled(28, 0.06));
  final ValueNotifier<double> amplitudeNotifier = ValueNotifier<double>(0.0);

  bool get hasSession => _hasStarted || _isRecording;

  void setSessionInfo({
    required String title,
    String? roomCode,
    bool isParticipant = false,
  }) {
    _meetingTitle = title;
    _roomCode = roomCode;
    _isParticipant = isParticipant;
    notifyListeners();
  }

  void markStarted() {
    _hasStarted = true;
    notifyListeners();
  }

  Future<bool> startRecording({
    required String path,
    required String title,
    String? roomCode,
  }) async {
    if (_isRecording) return true;
    try {
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 16000,
            numChannels: 1,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
            audioInterruption: AudioInterruptionMode.pause,
          ),
          path: path,
        );
        _savedPath = path;
        _meetingTitle = title;
        _roomCode = roomCode;
        _isRecording = true;
        _hasStarted = true;
        _isInterrupted = false;
        _recordDuration = 0;

        _startTimer();
        _startAmplitudeMonitoring();
        _startStateMonitoring();

        // Wire foreground notification button actions to this service
        MeetingForegroundService.onPauseRequested = () => pauseRecording();
        MeetingForegroundService.onResumeRequested = () => resumeRecording();

        MeetingForegroundService().startRecordingService(meetingTitle: title);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('MeetingRecordingService start error: $e');
    }
    return false;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordDuration++;
      notifyListeners();
    });
  }

  void _startStateMonitoring() {
    _stateSubscription?.cancel();
    _stateSubscription = _audioRecorder.onStateChanged().listen(
      (state) {
        if (state == RecordState.pause && _isRecording) {
          // Interruption occurred (phone call, alarm, audio focus loss)
          debugPrint('Audio recording interrupted by system.');
          _isRecording = false;
          _isInterrupted = true;
          _timer?.cancel();
          _stopAmplitudeMonitoring();
          MeetingForegroundService().updateToPaused(
            meetingTitle: _meetingTitle,
            isInterrupted: true,
          );
          notifyListeners();
        } else if (state == RecordState.record && !_isRecording && _isInterrupted) {
          // Automatically resumed by system
          debugPrint('Audio recording resumed after interruption.');
          _isRecording = true;
          _isInterrupted = false;
          _startTimer();
          _startAmplitudeMonitoring();
          MeetingForegroundService().updateToRecording(
            meetingTitle: _meetingTitle,
          );
          notifyListeners();
        }
      },
      onError: (err) {
        debugPrint('Audio record state stream error: $err');
      },
    );
  }

  void _startAmplitudeMonitoring() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 70))
        .listen(
      (amp) {
        final db = amp.current;
        double normalized = 0.06;
        if (db > -55) {
          normalized = ((db + 55) / 55).clamp(0.06, 1.0);
        }
        _currentAmplitude = normalized;
        _waveformSamples.removeAt(0);
        _waveformSamples.add(normalized);

        // Update dedicated notifiers directly without triggering whole-screen rebuilds
        amplitudeNotifier.value = normalized;
        waveformNotifier.value = List.unmodifiable(_waveformSamples);
      },
      onError: (err) {
        debugPrint('Amplitude monitoring error: $err');
      },
    );
  }

  void _stopAmplitudeMonitoring() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _currentAmplitude = 0.0;
    amplitudeNotifier.value = 0.0;
    for (int i = 0; i < _waveformSamples.length; i++) {
      _waveformSamples[i] = 0.06;
    }
    waveformNotifier.value = List.unmodifiable(_waveformSamples);
  }

  Future<void> pauseRecording() async {
    if (!_isRecording) return;
    try {
      await _audioRecorder.pause();
      _isRecording = false;
      _timer?.cancel();
      _stopAmplitudeMonitoring();
      MeetingForegroundService().updateToPaused(
        meetingTitle: _meetingTitle,
        isInterrupted: false,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('MeetingRecordingService pause error: $e');
    }
  }

  Future<void> resumeRecording() async {
    if (_isRecording) return;
    try {
      await _audioRecorder.resume();
      _isRecording = true;
      _isInterrupted = false;
      _startTimer();
      _startAmplitudeMonitoring();
      MeetingForegroundService().updateToRecording(
        meetingTitle: _meetingTitle,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('MeetingRecordingService resume error: $e');
    }
  }

  Future<String?> stopRecording() async {
    _timer?.cancel();
    _timer = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _stopAmplitudeMonitoring();

    String? finalPath;
    try {
      if (await _audioRecorder.isRecording() || _isRecording) {
        finalPath = await _audioRecorder.stop();
      }
    } catch (e) {
      debugPrint('MeetingRecordingService stop error: $e');
    }
    finalPath = finalPath ?? _savedPath;
    _isRecording = false;
    _isInterrupted = false;
    notifyListeners();
    return finalPath;
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _stopAmplitudeMonitoring();
    _isRecording = false;
    _isInterrupted = false;
    _hasStarted = false;
    _isParticipant = false;
    _recordDuration = 0;
    _savedPath = null;
    _roomCode = null;
    participants = [];
    roomChannel = null;
    notifyListeners();
  }
}
