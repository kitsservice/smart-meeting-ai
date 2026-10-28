import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String musicalChannelId = 'meeting_musical_alerts_v1';
  static const String musicalChannelName = 'Meeting Music Alerts (5-Min Reminder)';
  static const String musicalSoundName = 'meeting_chime';

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // App icon

    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Explicitly register the high-priority musical notification channel on Android
    final Int64List vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 800]);
    final AndroidNotificationChannel musicalChannel = AndroidNotificationChannel(
      musicalChannelId,
      musicalChannelName,
      description: 'Plays melodic chime music 5 minutes before scheduled meetings',
      importance: Importance.max,
      sound: const RawResourceAndroidNotificationSound(musicalSoundName),
      playSound: true,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(musicalChannel);

    // Request permissions for Android 13+ (POST_NOTIFICATIONS and exact alarms)
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  /// Builds high-priority platform specifics that play the custom meeting chime sound
  NotificationDetails _buildMusicalChimeNotificationDetails() {
    final Int64List vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 800]);

    return NotificationDetails(
      android: AndroidNotificationDetails(
        musicalChannelId,
        musicalChannelName,
        channelDescription:
            'Plays melodic chime music 5 minutes before scheduled meetings',
        importance: Importance.max,
        priority: Priority.max,
        sound: const RawResourceAndroidNotificationSound(musicalSoundName),
        playSound: true,
        enableVibration: true,
        vibrationPattern: vibrationPattern,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: const DarwinNotificationDetails(
        sound: '$musicalSoundName.wav',
        presentSound: true,
        presentAlert: true,
        presentBanner: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  Future<void> scheduleMeetingNotifications(
    String title,
    DateTime meetingDate,
  ) async {
    final int baseId = Random().nextInt(10000);

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: AndroidNotificationDetails(
        'meeting_reminders',
        'Meeting Reminders',
        channelDescription: 'Notifications for upcoming scheduled meetings',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    // 1. Schedule Morning Notification (8:00 AM on the day of the meeting)
    final DateTime morningTime = DateTime(
      meetingDate.year,
      meetingDate.month,
      meetingDate.day,
      8,
      0, // 8:00 AM
    );

    if (morningTime.isAfter(DateTime.now())) {
      final hourStr = meetingDate.hour > 12
          ? meetingDate.hour - 12
          : (meetingDate.hour == 0 ? 12 : meetingDate.hour);
      final amPm = meetingDate.hour >= 12 ? 'PM' : 'AM';
      final minStr = meetingDate.minute.toString().padLeft(2, '0');
      final timeStr = '$hourStr:$minStr $amPm';

      await flutterLocalNotificationsPlugin.zonedSchedule(
        baseId + 1,
        'Today is your meeting: $title',
        'You have a meeting scheduled for later today at $timeStr.',
        tz.TZDateTime.from(morningTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    // 2. Schedule 30-minute Warning
    final DateTime thirtyMinsBefore = meetingDate.subtract(
      const Duration(minutes: 30),
    );

    if (thirtyMinsBefore.isAfter(DateTime.now())) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        baseId + 2,
        'Meeting in 30 minutes!',
        'Your meeting "$title" is starting soon.',
        tz.TZDateTime.from(thirtyMinsBefore, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    // 3. Schedule 5-Minute Warning WITH Custom Notification Music / Chime
    final DateTime fiveMinsBefore = meetingDate.subtract(
      const Duration(minutes: 5),
    );

    final musicalDetails = _buildMusicalChimeNotificationDetails();

    if (fiveMinsBefore.isAfter(DateTime.now())) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        baseId + 3,
        '🔔 Meeting in 5 minutes!',
        'Your meeting "$title" is starting in 5 minutes. Get ready!',
        tz.TZDateTime.from(fiveMinsBefore, tz.local),
        musicalDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } else if (meetingDate.isAfter(DateTime.now())) {
      // If the meeting was scheduled less than 5 minutes from now, alert immediately!
      await flutterLocalNotificationsPlugin.show(
        baseId + 3,
        '🔔 Meeting Starting Soon!',
        'Your meeting "$title" is starting shortly.',
        musicalDetails,
      );
    }
  }

  /// Instantly test-plays the 5-minute melodic chime notification
  Future<void> testPlayMeetingChimeNotification({
    String title = 'Demo Meeting Preview',
  }) async {
    final musicalDetails = _buildMusicalChimeNotificationDetails();
    await flutterLocalNotificationsPlugin.show(
      Random().nextInt(10000),
      '🔔 Meeting in 5 minutes!',
      'Your meeting "$title" is starting in 5 minutes.',
      musicalDetails,
    );
  }

  /// Schedule a targeted notification reminder for an action item / task deadline
  Future<int> scheduleActionItemReminder({
    required String taskTitle,
    required DateTime reminderTime,
    String? meetingTitle,
    int? customId,
  }) async {
    final int notifId = customId ?? (Random().nextInt(80000) + 10000);

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: AndroidNotificationDetails(
        'action_item_reminders',
        'Action Item Reminders',
        channelDescription: 'Alerts and deadlines for meeting action items',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    if (reminderTime.isAfter(DateTime.now())) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notifId,
        'Action Item Reminder',
        meetingTitle != null && meetingTitle.isNotEmpty
            ? '$taskTitle (from $meetingTitle)'
            : taskTitle,
        tz.TZDateTime.from(reminderTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    return notifId;
  }

  /// Instantly trigger a local notification confirmation
  Future<void> showInstantNotification({
    required String title,
    required String body,
  }) async {
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: AndroidNotificationDetails(
        'general_alerts',
        'General Alerts',
        channelDescription: 'Instant confirmations and updates',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await flutterLocalNotificationsPlugin.show(
      Random().nextInt(10000),
      title,
      body,
      platformChannelSpecifics,
    );
  }

  /// Cancel a scheduled notification by ID
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }
}
