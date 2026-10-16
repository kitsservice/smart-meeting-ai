import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/calendar_service.dart';

class ScheduledEvent {
  final String title;
  final DateTime date;
  final bool isMeeting;
  bool isCompleted;

  ScheduledEvent({
    required this.title,
    required this.date,
    this.isMeeting = true,
    this.isCompleted = false,
  });

  bool get isFinished {
    if (!isMeeting) return false;
    if (isCompleted) return true;
    final now = DateTime.now();
    return now.isAfter(date.add(const Duration(minutes: 15)));
  }

  static bool isHolidayTitle(String title) {
    final lower = title.toLowerCase();
    const holidayKeywords = [
      'dussehra',
      'dasara',
      'vijayadashami',
      'diwali',
      'deepavali',
      'eid',
      'christmas',
      'new year',
      'republic day',
      'independence day',
      'gandhi jayanti',
      'holi',
      'pongal',
      'onam',
      'navratri',
      'muharram',
      'good friday',
      'baisakhi',
      'raksha bandhan',
      'janmashtami',
      'ganesh chaturthi',
      'holiday',
      'jayanti',
      'festival',
    ];
    return holidayKeywords.any((k) => lower.contains(k));
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'date': date.toIso8601String(),
    'isMeeting': isMeeting,
    'isCompleted': isCompleted,
  };

  factory ScheduledEvent.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String? ?? '';
    bool isMeeting = json['isMeeting'] ?? true;
    if (isHolidayTitle(title)) {
      isMeeting = false;
    }
    final parsedDate = DateTime.parse(json['date']);
    final isCompleted = json['isCompleted'] as bool? ??
        (isMeeting &&
            DateTime.now().isAfter(parsedDate.add(const Duration(minutes: 15))));
    return ScheduledEvent(
      title: title,
      date: parsedDate,
      isMeeting: isMeeting,
      isCompleted: isCompleted,
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<ScheduledEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = prefs.getString('scheduled_events');
    if (eventsJson != null) {
      final List<dynamic> decoded = jsonDecode(eventsJson);
      final events = decoded.map((e) => ScheduledEvent.fromJson(e)).toList();

      Map<DateTime, List<ScheduledEvent>> groupedEvents = {};
      for (var event in events) {
        final dateKey = DateTime(
          event.date.year,
          event.date.month,
          event.date.day,
        );
        if (groupedEvents[dateKey] == null) {
          groupedEvents[dateKey] = [];
        }
        groupedEvents[dateKey]!.add(event);
      }

      setState(() {
        _events = groupedEvents;
      });
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    List<ScheduledEvent> allEvents = [];
    for (var list in _events.values) {
      allEvents.addAll(list);
    }

    final encoded = jsonEncode(allEvents.map((e) => e.toJson()).toList());
    await prefs.setString('scheduled_events', encoded);
  }

  List<ScheduledEvent> _getEventsForDay(DateTime day) {
    final dateKey = DateTime(day.year, day.month, day.day);
    return _events[dateKey] ?? [];
  }

  void _deleteEvent(ScheduledEvent event) {
    final dateKey = DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
    );
    setState(() {
      _events[dateKey]?.remove(event);
      if (_events[dateKey]?.isEmpty ?? false) {
        _events.remove(dateKey);
      }
    });
    _saveEvents();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${event.title}" from schedule'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _toggleEventCompleted(ScheduledEvent event) {
    setState(() {
      event.isCompleted = !event.isCompleted;
    });
    _saveEvents();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          event.isCompleted
              ? 'Marked "${event.title}" as Completed'
              : 'Marked "${event.title}" as Scheduled',
        ),
        backgroundColor:
            event.isCompleted ? const Color(0xFF10B981) : AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _syncDeviceCalendar() async {
    final dc.DeviceCalendarPlugin deviceCalendarPlugin =
        dc.DeviceCalendarPlugin();
    var permissionsGranted = await deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !permissionsGranted.data!) {
      permissionsGranted = await deviceCalendarPlugin.requestPermissions();
      if (!permissionsGranted.isSuccess || !permissionsGranted.data!) {
        return; // Permission denied
      }
    }

    final calendarsResult = await deviceCalendarPlugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || calendarsResult.data == null) return;

    for (var calendar in calendarsResult.data!) {
      if (calendar.id != null) {
        final startDate = DateTime.now().subtract(const Duration(days: 30));
        final endDate = DateTime.now().add(const Duration(days: 90));
        final eventsResult = await deviceCalendarPlugin.retrieveEvents(
          calendar.id,
          dc.RetrieveEventsParams(startDate: startDate, endDate: endDate),
        );

        if (eventsResult.isSuccess && eventsResult.data != null) {
          final isHolidayCal =
              (calendar.name?.toLowerCase().contains('holiday') ?? false) ||
              (calendar.name?.toLowerCase().contains('festival') ?? false) ||
              (calendar.isReadOnly == true);

          for (var event in eventsResult.data!) {
            if (event.start != null && event.title != null) {
              final isAllDay = event.allDay ?? false;
              final isHoliday =
                  isHolidayCal ||
                  isAllDay ||
                  ScheduledEvent.isHolidayTitle(event.title!);
              final isMeeting = !isHoliday;
              final eventDate = event.start!;
              final dateKey = DateTime(
                eventDate.year,
                eventDate.month,
                eventDate.day,
              );
              final scheduled = ScheduledEvent(
                title: event.title!,
                date: eventDate,
                isMeeting: isMeeting,
                isCompleted: isMeeting &&
                    DateTime.now().isAfter(
                      eventDate.add(const Duration(minutes: 15)),
                    ),
              );

              if (_events[dateKey] == null) _events[dateKey] = [];
              final existingIndex = _events[dateKey]!.indexWhere(
                (e) =>
                    e.title.toLowerCase().trim() ==
                    scheduled.title.toLowerCase().trim(),
              );
              if (existingIndex >= 0) {
                scheduled.isCompleted =
                    _events[dateKey]![existingIndex].isCompleted ||
                    scheduled.isCompleted;
                _events[dateKey]![existingIndex] = scheduled;
              } else {
                _events[dateKey]!.add(scheduled);
              }
            }
          }
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
    _saveEvents();
  }

  Future<void> _showAddEventDialog() async {
    if (_selectedDay == null) return;
    String newEventTitle = '';
    TimeOfDay selectedTime = TimeOfDay.now();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 32,
                      ),
                      decoration: const BoxDecoration(
                        color: AppTheme.backgroundColor,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(32)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: AppTheme.dividerColor,
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            ),
                          ),
                          const Text(
                            'Schedule Meeting',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add a new meeting to your schedule.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 24),

                          // Title TextField
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.dividerColor),
                            ),
                            child: TextField(
                              autofocus: false,
                              onChanged: (val) => newEventTitle = val,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Enter meeting title',
                                hintStyle:
                                    TextStyle(color: AppTheme.textSecondary),
                                icon: Icon(
                                  Icons.title,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Time Picker
                          GestureDetector(
                            onTap: () async {
                              FocusScope.of(sheetContext).unfocus();
                              final time = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (time != null && sheetContext.mounted) {
                                setModalState(() => selectedTime = time);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.dividerColor),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    selectedTime.format(context),
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: AppTheme.textSecondary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Save Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                if (newEventTitle.trim().isNotEmpty) {
                                  Navigator.pop(sheetContext, {
                                    'title': newEventTitle.trim(),
                                    'time': selectedTime,
                                  });
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Save Meeting',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      final title = result['title'] as String;
      final time = result['time'] as TimeOfDay;
      final eventDateTime = DateTime(
        _selectedDay!.year,
        _selectedDay!.month,
        _selectedDay!.day,
        time.hour,
        time.minute,
      );
      final event = ScheduledEvent(
        title: title,
        date: eventDateTime,
      );
      final dateKey = DateTime(
        _selectedDay!.year,
        _selectedDay!.month,
        _selectedDay!.day,
      );

      setState(() {
        if (_events[dateKey] == null) _events[dateKey] = [];
        _events[dateKey]!.add(event);
      });

      _saveEvents();
      LocalNotificationService().scheduleMeetingNotifications(
        event.title,
        event.date,
      );
      CalendarService().addToDeviceCalendar(
        title: event.title,
        startTime: event.date,
        description: 'Scheduled with Ares-Smart Meeting',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsForDay = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(
          'Schedule Meeting',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Schedule Meeting',
            onPressed: () {
              HapticFeedback.lightImpact();
              _showAddEventDialog();
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync Device Calendar',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing calendar...')),
              );
              await _syncDeviceCalendar();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calendar synced successfully!')),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // The Calendar (Background)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TableCalendar(
              firstDay: DateTime(2020, 1, 1),
              lastDay: DateTime(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
                CalendarFormat.week: 'Week',
              },
              selectedDayPredicate: (day) {
                return isSameDay(_selectedDay, day);
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                }
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              eventLoader: _getEventsForDay,
              daysOfWeekHeight: 24, // Fixes the vertical clipping
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                todayDecoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(12),
                ),
                todayTextStyle: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
                defaultTextStyle: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                weekendTextStyle: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
                outsideDaysVisible: false,
                markerDecoration: const BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                markersMaxCount: 1,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: true,
                formatButtonShowsNext: false,
                formatButtonTextStyle: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                formatButtonDecoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                titleCentered: true,
                titleTextStyle: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                leftChevronIcon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: AppTheme.textPrimary,
                    size: 20,
                  ),
                ),
                rightChevronIcon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textPrimary,
                    size: 20,
                  ),
                ),
                headerPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                weekendStyle: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          // Draggable Events Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Drag Handle
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.dividerColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 8.0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _selectedDay != null
                              ? 'Events on ${_selectedDay!.day.toString().padLeft(2, '0')}/${_selectedDay!.month.toString().padLeft(2, '0')}/${_selectedDay!.year.toString().substring(2)}'
                              : 'Events',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Expanded(
                      child: eventsForDay.isEmpty
                          ? SingleChildScrollView(
                              controller: scrollController,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32.0,
                                  vertical: 28.0,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.08),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.event_available_rounded,
                                          size: 40,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No meetings for this day',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Your calendar is open. Schedule a meeting to stay organized and receive AI summaries.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          _showAddEventDialog();
                                        },
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Schedule Meeting',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryColor,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 11,
                                          ),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              itemCount: eventsForDay.length,
                              itemBuilder: (context, index) {
                                final currentEvent = eventsForDay[index];
                                final isFinished = currentEvent.isFinished;

                                return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.cardBg(context),
                                      borderRadius:
                                          BorderRadius.circular(AppTheme.radiusCard),
                                      border: Border.all(
                                        color: isFinished
                                            ? const Color(0xFF10B981)
                                                .withValues(alpha: 0.35)
                                            : AppTheme.cardBorder(context),
                                        width: isFinished ? 1.5 : 1.0,
                                      ),
                                      boxShadow: AppTheme.cardShadow(context),
                                    ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: (!currentEvent.isMeeting
                                                      ? const Color(0xFFF59E0B)
                                                      : isFinished
                                                          ? const Color(
                                                              0xFF10B981,
                                                            )
                                                          : AppTheme
                                                              .primaryColor)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              !currentEvent.isMeeting
                                                  ? Icons.celebration_rounded
                                                  : isFinished
                                                      ? Icons
                                                          .check_circle_rounded
                                                      : Icons
                                                          .event_note_rounded,
                                              color: !currentEvent.isMeeting
                                                  ? const Color(0xFFF59E0B)
                                                  : isFinished
                                                      ? const Color(0xFF10B981)
                                                      : AppTheme.primaryColor,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  currentEvent.title,
                                                  style: const TextStyle(
                                                    color:
                                                        AppTheme.textPrimary,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    letterSpacing: -0.3,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.access_time_rounded,
                                                      size: 14,
                                                      color: AppTheme
                                                          .textSecondary
                                                          .withValues(
                                                              alpha: 0.8),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        currentEvent.isMeeting
                                                            ? (isFinished
                                                                ? '${TimeOfDay.fromDateTime(currentEvent.date).format(context)} • Ended'
                                                                : TimeOfDay.fromDateTime(
                                                                    currentEvent
                                                                        .date,
                                                                  ).format(
                                                                    context,
                                                                  ))
                                                            : 'All Day',
                                                        style: const TextStyle(
                                                          color: AppTheme
                                                              .textSecondary,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Badge: "Completed", "Scheduled", or "Holiday"
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (!currentEvent.isMeeting
                                                      ? const Color(0xFFF59E0B)
                                                      : isFinished
                                                          ? const Color(
                                                              0xFF10B981,
                                                            )
                                                          : AppTheme
                                                              .primaryColor)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: (!currentEvent.isMeeting
                                                        ? const Color(
                                                            0xFFF59E0B,
                                                          )
                                                        : isFinished
                                                            ? const Color(
                                                                0xFF10B981,
                                                              )
                                                            : AppTheme
                                                                .primaryColor)
                                                    .withValues(alpha: 0.3),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  !currentEvent.isMeeting
                                                      ? Icons
                                                          .celebration_rounded
                                                      : isFinished
                                                          ? Icons
                                                              .check_circle_rounded
                                                          : Icons
                                                              .schedule_rounded,
                                                  size: 12,
                                                  color: !currentEvent.isMeeting
                                                      ? const Color(
                                                          0xFFF59E0B,
                                                        )
                                                      : isFinished
                                                          ? const Color(
                                                              0xFF10B981,
                                                            )
                                                          : AppTheme
                                                              .primaryColor,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  !currentEvent.isMeeting
                                                      ? 'Holiday'
                                                      : isFinished
                                                          ? 'Completed'
                                                          : 'Scheduled',
                                                  style: TextStyle(
                                                    color:
                                                        !currentEvent.isMeeting
                                                            ? const Color(
                                                                0xFFF59E0B,
                                                              )
                                                            : isFinished
                                                                ? const Color(
                                                                    0xFF10B981,
                                                                  )
                                                                : AppTheme
                                                                    .primaryColor,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.more_vert_rounded,
                                              size: 20,
                                              color: AppTheme.textSecondary,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(),
                                            onSelected: (value) {
                                              if (value == 'toggle') {
                                                _toggleEventCompleted(
                                                    currentEvent);
                                              } else if (value == 'delete') {
                                                _deleteEvent(currentEvent);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (currentEvent.isMeeting)
                                                PopupMenuItem(
                                                  value: 'toggle',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        isFinished
                                                            ? Icons
                                                                .replay_rounded
                                                            : Icons
                                                                .check_circle_rounded,
                                                        size: 18,
                                                        color: isFinished
                                                            ? AppTheme
                                                                .primaryColor
                                                            : const Color(
                                                                0xFF10B981,
                                                              ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Text(
                                                        isFinished
                                                            ? 'Mark as Pending'
                                                            : 'Mark as Completed',
                                                        style: const TextStyle(
                                                            fontSize: 13),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      size: 18,
                                                      color:
                                                          AppTheme.dangerColor,
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text(
                                                      'Delete Event',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: AppTheme
                                                            .dangerColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (currentEvent.isMeeting) ...[
                                        const SizedBox(height: 12),
                                        const Divider(
                                          height: 1,
                                          color: AppTheme.dividerColor,
                                        ),
                                        const SizedBox(height: 10),
                                        if (isFinished)
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF10B981)
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.task_alt_rounded,
                                                        size: 15,
                                                        color:
                                                            Color(0xFF10B981),
                                                      ),
                                                      SizedBox(width: 6),
                                                      Flexible(
                                                        child: Text(
                                                          'Meeting Completed',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                Color(0xFF10B981),
                                                          ),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Spacer(),
                                              OutlinedButton.icon(
                                                onPressed: () async {
                                                  final result =
                                                      await Navigator.pushNamed(
                                                    context,
                                                    '/active_meeting',
                                                    arguments: {
                                                      'title':
                                                          currentEvent.title,
                                                    },
                                                  );
                                                  if (result == true ||
                                                      (result is Map &&
                                                          result['completed'] ==
                                                              true)) {
                                                    setState(() {
                                                      currentEvent.isCompleted =
                                                          true;
                                                    });
                                                    _saveEvents();
                                                  } else {
                                                    _loadEvents();
                                                  }
                                                },
                                                icon: const Icon(
                                                  Icons.replay_rounded,
                                                  size: 15,
                                                  color:
                                                      AppTheme.primaryColor,
                                                ),
                                                label: const Text(
                                                  'Restart',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color:
                                                        AppTheme.primaryColor,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(
                                                    color:
                                                        AppTheme.primaryColor,
                                                    width: 1.2,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 8,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () {
                                                    _toggleEventCompleted(
                                                        currentEvent);
                                                  },
                                                  icon: const Icon(
                                                    Icons
                                                        .check_circle_outline_rounded,
                                                    size: 15,
                                                    color:
                                                        Color(0xFF10B981),
                                                  ),
                                                  label: const Text(
                                                    'Mark Completed',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                      color:
                                                          Color(0xFF10B981),
                                                    ),
                                                  ),
                                                  style: OutlinedButton.styleFrom(
                                                    side: BorderSide(
                                                      color: const Color(
                                                              0xFF10B981)
                                                          .withValues(alpha: 0.5),
                                                      width: 1.2,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 8,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  onPressed: () async {
                                                    final result =
                                                        await Navigator.pushNamed(
                                                      context,
                                                      '/active_meeting',
                                                      arguments: {
                                                        'title':
                                                            currentEvent.title,
                                                      },
                                                    );
                                                    if (result == true ||
                                                        (result is Map &&
                                                            result['completed'] ==
                                                                true)) {
                                                      setState(() {
                                                        currentEvent.isCompleted =
                                                            true;
                                                      });
                                                      _saveEvents();
                                                    } else {
                                                      _loadEvents();
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons
                                                        .play_circle_fill_rounded,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                  label: const Text(
                                                    'Start Meeting',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppTheme.primaryColor,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 8,
                                                    ),
                                                    elevation: 0,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
