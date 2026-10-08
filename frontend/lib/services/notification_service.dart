import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:math';
import 'package:flutter/material.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
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

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );
    
    // Request permission for newer Android versions
    await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
  }

  Future<void> scheduleMeetingNotifications(String title, DateTime meetingDate) async {
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
      final hourStr = meetingDate.hour > 12 ? meetingDate.hour - 12 : (meetingDate.hour == 0 ? 12 : meetingDate.hour);
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
    final DateTime thirtyMinsBefore = meetingDate.subtract(const Duration(minutes: 30));

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
}
