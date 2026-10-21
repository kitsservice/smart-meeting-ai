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
          ),
          path: path,
        );
        _savedPath = path;
        _meetingTitle = title;
        _roomCode = roomCode;
        _isRecording = true;
        _hasStarted = true;
        _recordDuration = 0;

        _startTimer();
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

  Future<void> pauseRecording() async {
    if (!_isRecording) return;
    try {
      await _audioRecorder.pause();
      _isRecording = false;
      _timer?.cancel();
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
      _startTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('MeetingRecordingService resume error: $e');
    }
  }

  Future<String?> stopRecording() async {
    _timer?.cancel();
    _timer = null;
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
    notifyListeners();
    return finalPath;
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _isRecording = false;
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
