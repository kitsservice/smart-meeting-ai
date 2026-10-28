import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarService {
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;
  CalendarService._internal();

  final dc.DeviceCalendarPlugin _deviceCalendarPlugin =
      dc.DeviceCalendarPlugin();

  /// Checks if calendar read/write permissions are granted
  Future<bool> hasPermissions() async {
    try {
      final res = await _deviceCalendarPlugin.hasPermissions();
      return res.isSuccess && (res.data ?? false);
    } catch (e) {
      debugPrint('Error checking calendar permissions: $e');
      return false;
    }
  }

  /// Requests calendar permissions
  Future<bool> requestPermissions() async {
    try {
      final res = await _deviceCalendarPlugin.requestPermissions();
      return res.isSuccess && (res.data ?? false);
    } catch (e) {
      debugPrint('Error requesting calendar permissions: $e');
      return false;
    }
  }

  /// Retrieves available writable calendars or the default one
  Future<List<dc.Calendar>> getCalendars() async {
    try {
      final hasPerm = await hasPermissions();
      if (!hasPerm) {
        final granted = await requestPermissions();
        if (!granted) return [];
      }

      final res = await _deviceCalendarPlugin.retrieveCalendars();
      if (res.isSuccess && res.data != null) {
        return res.data!;
      }
      return [];
    } catch (e) {
      debugPrint('Error retrieving calendars: $e');
      return [];
    }
  }

  /// Adds a meeting or action item task event to the device's native calendar (Google Calendar / Apple Calendar)
  Future<bool> addToDeviceCalendar({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
  }) async {
    try {
      final hasPerm = await hasPermissions();
      if (!hasPerm) {
        final granted = await requestPermissions();
        if (!granted) return false;
      }

      final calendars = await getCalendars();
      if (calendars.isEmpty) return false;

      // Select primary or first non-read-only calendar
      final writableCalendar = calendars.firstWhere(
        (c) => !(c.isReadOnly ?? false),
        orElse: () => calendars.first,
      );

      if (writableCalendar.id == null) return false;

      final actualEndTime = endTime ?? startTime.add(const Duration(hours: 1));

      final dc.Event event = dc.Event(
        writableCalendar.id,
        title: title,
        description: description,
        start: tz.TZDateTime.from(startTime, tz.local),
        end: tz.TZDateTime.from(actualEndTime, tz.local),
        location: location,
        reminders: [
          dc.Reminder(minutes: 5),
          dc.Reminder(minutes: 30),
        ],
      );

      final createRes = await _deviceCalendarPlugin.createOrUpdateEvent(event);
      return createRes?.isSuccess ?? false;
    } catch (e) {
      debugPrint('Error adding to device calendar: $e');
      return false;
    }
  }
}
