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
  void onNotificationButtonPressed(String id) {}

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

  void init() {
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterForegroundTask.initCommunicationPort();

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
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 2001,
          notificationTitle: 'Smart Meeting AI: Recording Active',
          notificationText: 'Recording "$meetingTitle" • Tap to return to meeting',
          notificationInitialRoute: '/',
          callback: startForegroundCallback,
        );
      }
    } catch (e) {
      debugPrint('Failed to start recording foreground service: $e');
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
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 2001,
          notificationTitle: 'Smart Meeting AI: Transcribing...',
          notificationText: 'Uploading audio & generating AI summary for "$meetingTitle"...',
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
