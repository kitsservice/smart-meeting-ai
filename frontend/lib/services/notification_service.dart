import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:math';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

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

    // Request permission for newer Android versions
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
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

    // Only schedule if 8:00 AM hasn't passed yet
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

    // Only schedule if the 30-min warning hasn't passed yet
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
