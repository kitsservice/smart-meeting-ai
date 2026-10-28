import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(MeetingTaskHandler());
}

class MeetingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Foreground service started ($starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('Foreground service destroyed (isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('Foreground notification button pressed: $id');
    FlutterForegroundTask.sendDataToMain(id);
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

class MeetingForegroundService {
  static final MeetingForegroundService _instance =
      MeetingForegroundService._internal();
  factory MeetingForegroundService() => _instance;
  MeetingForegroundService._internal();

  bool _initialized = false;

  /// Callbacks invoked when user taps interactive notification buttons
  static VoidCallback? onPauseRequested;
  static VoidCallback? onResumeRequested;
  static VoidCallback? onStopRequested;

  static const List<NotificationButton> recordingButtons = [
    NotificationButton(id: 'btn_pause', text: 'Pause'),
    NotificationButton(id: 'btn_stop', text: 'End Meeting'),
  ];

  static const List<NotificationButton> pausedButtons = [
    NotificationButton(id: 'btn_resume', text: 'Resume'),
    NotificationButton(id: 'btn_stop', text: 'End Meeting'),
  ];

  void init() {
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'meeting_foreground_service',
          channelName: 'Meeting Recording & Transcription',
          channelDescription:
              'Keeps audio recording, cloud upload, and AI transcription active even when the screen is locked.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    }
  }

  static void _onReceiveTaskData(Object data) {
    final cmd = data.toString();
    debugPrint('Received foreground task command: $cmd');
    if (cmd == 'btn_pause') {
      onPauseRequested?.call();
    } else if (cmd == 'btn_resume') {
      onResumeRequested?.call();
    } else if (cmd == 'btn_stop') {
      onStopRequested?.call();
    }
  }

  /// Request permissions on Android / iOS
  Future<void> requestPermissions() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      final notifPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notifPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (Platform.isAndroid) {
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
    } catch (e) {
      debugPrint('Error requesting foreground permissions: $e');
    }
  }

  /// Start foreground service while recording
  Future<void> startRecordingService({required String meetingTitle}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Smart Meeting AI: Recording Active',
          notificationText: 'Recording "$meetingTitle" • Tap to return to meeting',
          notificationButtons: recordingButtons,
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 2001,
          notificationTitle: 'Smart Meeting AI: Recording Active',
          notificationText: 'Recording "$meetingTitle" • Tap to return to meeting',
          notificationButtons: recordingButtons,
          notificationInitialRoute: '/',
          callback: startForegroundCallback,
        );
      }
    } catch (e) {
      debugPrint('Failed to start recording foreground service: $e');
    }
  }

  /// Update foreground service when meeting is paused or interrupted
  Future<void> updateToPaused({
    required String meetingTitle,
    bool isInterrupted = false,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: isInterrupted
              ? 'Smart Meeting AI: Audio Interrupted'
              : 'Smart Meeting AI: Recording Paused',
          notificationText: isInterrupted
              ? 'Meeting paused by system event • Tap Resume to continue'
              : 'Recording paused for "$meetingTitle" • Tap Resume',
          notificationButtons: pausedButtons,
        );
      }
    } catch (e) {
      debugPrint('Failed to update foreground service to paused: $e');
    }
  }

  /// Update foreground service when recording is resumed
  Future<void> updateToRecording({required String meetingTitle}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Smart Meeting AI: Recording Active',
          notificationText: 'Recording "$meetingTitle" • Tap to return to meeting',
          notificationButtons: recordingButtons,
        );
      }
    } catch (e) {
      debugPrint('Failed to update foreground service to recording: $e');
    }
  }

  /// Update foreground service notification while transcribing and uploading
  Future<void> updateToSavingAndTranscribing({required String meetingTitle}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Smart Meeting AI: Transcribing...',
          notificationText: 'Uploading audio & generating AI summary for "$meetingTitle"...',
          notificationButtons: const [],
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 2001,
          notificationTitle: 'Smart Meeting AI: Transcribing...',
          notificationText: 'Uploading audio & generating AI summary for "$meetingTitle"...',
          notificationButtons: const [],
          notificationInitialRoute: '/',
          callback: startForegroundCallback,
        );
      }
    } catch (e) {
      debugPrint('Failed to update foreground service to transcribing: $e');
    }
  }

  /// Stop foreground service once transcription and upload are completely finished
  Future<void> stopService() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        debugPrint('Foreground service stopped cleanly.');
      }
    } catch (e) {
      debugPrint('Failed to stop foreground service: $e');
    }
  }
}
