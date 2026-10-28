import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/permission_sheet.dart';
import '../services/notification_service.dart';
import '../services/calendar_service.dart';
import '../providers/meetings_provider.dart';

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

  static const List<String> holidayKeywords = [
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

  static bool isHolidayTitle(String title) {
    final lower = title.toLowerCase();
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

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<ScheduledEvent>> _events = {};
  String _activeTabFilter = 'All';

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(meetingsProvider.notifier).fetchMeetings();
      }
    });
  }

  Map<DateTime, List<dynamic>> _groupRecordedMeetings(List<dynamic> allMeetings) {
    final Map<DateTime, List<dynamic>> map = {};
    for (final m in allMeetings) {
      if (m is Map) {
        final rawDate = m['created_at']?.toString() ?? '';
        if (rawDate.isNotEmpty) {
          try {
            final parsed = DateTime.parse(rawDate).toLocal();
            final key = DateTime(parsed.year, parsed.month, parsed.day);
            map.putIfAbsent(key, () => []).add(m);
          } catch (_) {}
        }
      }
    }
    return map;
  }

  List<dynamic> _getAllEventsForDay(
    DateTime day,
    Map<DateTime, List<dynamic>> recordedMap,
  ) {
    final dateKey = DateTime(day.year, day.month, day.day);
    final scheduled = _events[dateKey] ?? [];
    final recorded = recordedMap[dateKey] ?? [];
    return [...scheduled, ...recorded];
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

      if (!mounted) return;
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
      if (mounted) {
        final confirmed = await PermissionSheet.show(
          context,
          type: AresPermissionType.calendar,
        );
        if (!confirmed) return;
      }
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
    final targetDate = _selectedDay ?? _focusedDay;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleMeetingModalSheet(initialDate: targetDate),
    );

    if (result != null && mounted) {
      final title = result['title'] as String;
      final time = result['time'] as TimeOfDay;
      final selectedDate = _selectedDay ?? _focusedDay;
      final eventDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        time.hour,
        time.minute,
      );
      final event = ScheduledEvent(
        title: title,
        date: eventDateTime,
      );
      final dateKey = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );

      setState(() {
        if (_events[dateKey] == null) _events[dateKey] = [];
        _events[dateKey]!.add(event);
      });

      await _saveEvents();
      await LocalNotificationService().scheduleMeetingNotifications(
        event.title,
        event.date,
      );
      await CalendarService().addToDeviceCalendar(
        title: event.title,
        startTime: event.date,
        description: 'Scheduled with Ares-Smart Meeting',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Meeting "$title" scheduled successfully!',
            ),
            backgroundColor: AppTheme.accentColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meetingsAsync = ref.watch(meetingsProvider);
    final allRecordedMeetings = meetingsAsync.value ?? [];
    final recordedMeetingsMap = _groupRecordedMeetings(allRecordedMeetings);

    final targetDate = _selectedDay ?? _focusedDay;
    final targetDateKey = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final scheduledForDay = _getEventsForDay(targetDate);
    final recordedForDay = recordedMeetingsMap[targetDateKey] ?? [];
    final totalEventsForDay = scheduledForDay.length + recordedForDay.length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(
          'Schedule & Calendar',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800),
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
            tooltip: 'Sync Calendar & History',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing calendar and meeting history...')),
              );
              await _syncDeviceCalendar();
              if (mounted) {
                await ref.read(meetingsProvider.notifier).fetchMeetings();
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calendar & history synced successfully!')),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // The Calendar (Background - Responsive)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ResponsiveContentWrapper(
              maxWidth: Responsive.maxContentWidth,
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
              eventLoader: (day) => _getAllEventsForDay(day, recordedMeetingsMap),
              daysOfWeekHeight: 24, // Fixes the vertical clipping
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
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
                  shape: BoxShape.circle,
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
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 3,
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return const SizedBox.shrink();

                  final hasRecorded = events.any((e) => e is Map);
                  final hasScheduled = events.any((e) => e is ScheduledEvent && e.isMeeting);
                  final hasHoliday = events.any((e) => e is ScheduledEvent && !e.isMeeting);

                  return Positioned(
                    bottom: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasRecorded)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (hasScheduled)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (hasHoliday)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  );
                },
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
          ),

          // Draggable Events Sheet (Responsive max width & centering)
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (BuildContext context, ScrollController scrollController) {
              return ResponsiveContentWrapper(
                maxWidth: Responsive.maxContentWidth,
                alignment: Alignment.bottomCenter,
                child: Container(
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

                    // Sheet Header with Date & Legend
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Responsive.horizontalPadding(context),
                        vertical: 4.0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDay != null
                                  ? 'Events on ${_selectedDay!.day.toString().padLeft(2, '0')}/${_selectedDay!.month.toString().padLeft(2, '0')}/${_selectedDay!.year.toString().substring(2)}'
                                  : 'Events',
                              style: TextStyle(
                                fontSize: Responsive.value(context, mobile: 18.0, narrow: 14.5),
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildLegendDot(const Color(0xFF10B981), 'History'),
                              const SizedBox(width: 8),
                              _buildLegendDot(AppTheme.primaryColor, 'Scheduled'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Filter Chips (All, Recorded, Scheduled)
                    if (totalEventsForDay > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 6.0,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip(
                                label: 'All ($totalEventsForDay)',
                                isSelected: _activeTabFilter == 'All',
                                onTap: () => setState(() => _activeTabFilter = 'All'),
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                label: '🎙️ Recorded (${recordedForDay.length})',
                                isSelected: _activeTabFilter == 'Recorded',
                                onTap: () => setState(() => _activeTabFilter = 'Recorded'),
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                label: '📅 Scheduled (${scheduledForDay.length})',
                                isSelected: _activeTabFilter == 'Scheduled',
                                onTap: () => setState(() => _activeTabFilter = 'Scheduled'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),

                    Expanded(
                      child: totalEventsForDay == 0
                          ? SingleChildScrollView(
                              controller: scrollController,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 20.0,
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
                                        'Your calendar is open. Schedule a meeting or start recording to view AI meeting history.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
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
                                                horizontal: 14,
                                                vertical: 11,
                                              ),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              HapticFeedback.lightImpact();
                                              Navigator.pushNamed(context, '/active_meeting');
                                            },
                                            icon: const Icon(
                                              Icons.mic_rounded,
                                              size: 18,
                                              color: AppTheme.primaryColor,
                                            ),
                                            label: const Text(
                                              'Record Now',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                color: AppTheme.primaryColor,
                                                width: 1.2,
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 11,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 6.0,
                              ),
                              children: [
                                if (_activeTabFilter == 'All') ...[
                                  if (recordedForDay.isNotEmpty) ...[
                                    _buildSectionHeader(
                                      'PREVIOUS RECORDED MEETINGS',
                                      recordedForDay.length,
                                      const Color(0xFF10B981),
                                      Icons.graphic_eq_rounded,
                                    ),
                                    for (final meeting in recordedForDay)
                                      _buildRecordedMeetingCard(context, meeting),
                                    const SizedBox(height: 8),
                                  ],
                                  if (scheduledForDay.isNotEmpty) ...[
                                    _buildSectionHeader(
                                      'SCHEDULED EVENTS',
                                      scheduledForDay.length,
                                      AppTheme.primaryColor,
                                      Icons.event_note_rounded,
                                    ),
                                    for (final event in scheduledForDay)
                                      _buildScheduledEventCard(context, event),
                                  ],
                                ] else if (_activeTabFilter == 'Recorded') ...[
                                  if (recordedForDay.isEmpty)
                                    _buildEmptyFilterState(
                                      icon: Icons.history_edu_rounded,
                                      title: 'No recorded meetings on this date',
                                      subtitle: 'Meetings recorded in Ares will automatically appear here on their date.',
                                    )
                                  else
                                    for (final meeting in recordedForDay)
                                      _buildRecordedMeetingCard(context, meeting),
                                ] else if (_activeTabFilter == 'Scheduled') ...[
                                  if (scheduledForDay.isEmpty)
                                    _buildEmptyFilterState(
                                      icon: Icons.event_available_rounded,
                                      title: 'No scheduled events on this date',
                                      subtitle: 'Tap below to schedule a meeting for this date.',
                                      actionButton: ElevatedButton.icon(
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
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    for (final event in scheduledForDay)
                                      _buildScheduledEventCard(context, event),
                                ],
                                const SizedBox(height: 32),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    Color accentColor,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: accentColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFilterState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? actionButton,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (actionButton != null) ...[
              const SizedBox(height: 16),
              actionButton,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordedMeetingCard(
    BuildContext context,
    dynamic rawMeeting,
  ) {
    final Map<String, dynamic> meeting = rawMeeting is Map
        ? Map<String, dynamic>.from(rawMeeting)
        : <String, dynamic>{};

    final title = (meeting['title']?.toString() ?? '').trim();
    final displayTitle = title.isNotEmpty ? title : 'Untitled Meeting';
    final rawDate = meeting['created_at']?.toString() ?? '';

    String timeStr = 'Recorded';
    if (rawDate.isNotEmpty) {
      try {
        final parsedDate = DateTime.parse(rawDate).toLocal();
        int hourValue = parsedDate.hour;
        final ampm = hourValue >= 12 ? 'PM' : 'AM';
        if (hourValue == 0) hourValue = 12;
        if (hourValue > 12) hourValue -= 12;
        final hourStr = hourValue.toString().padLeft(2, '0');
        final minuteStr = parsedDate.minute.toString().padLeft(2, '0');
        timeStr = '$hourStr:$minuteStr $ampm';
      } catch (_) {}
    }

    int durationMinutes = 0;
    if (meeting['_cached_duration'] is int) {
      durationMinutes = meeting['_cached_duration'] as int;
    } else if (meeting['duration_seconds'] != null) {
      durationMinutes = (meeting['duration_seconds'] as num).round() ~/ 60;
    } else if (meeting['transcript'] != null) {
      final transcriptStr = meeting['transcript'].toString().trim();
      if (transcriptStr.isNotEmpty) {
        final words = transcriptStr.split(RegExp(r'\s+')).length;
        durationMinutes = (words / 130).ceil();
      }
    }

    final summary = (meeting['summary']?.toString() ?? '').trim();
    final actionItems = meeting['action_items'] is List ? meeting['action_items'] as List : [];
    final hasTranscript = meeting['transcript'] != null &&
        meeting['transcript'].toString().trim().isNotEmpty;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final isHost = (meeting['user_id'] ?? '').toString() == currentUserId;

    final List<String> subtitleParts = [timeStr];
    if (durationMinutes > 0) {
      subtitleParts.add('$durationMinutes min');
    }
    if (actionItems.isNotEmpty) {
      subtitleParts.add('${actionItems.length} tasks');
    }
    final String subtitleText = subtitleParts.join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          onTap: () async {
            HapticFeedback.lightImpact();
            final result = await Navigator.pushNamed(
              context,
              '/meeting_details',
              arguments: meeting,
            );
            if (result == true) {
              ref.read(meetingsProvider.notifier).fetchMeetings();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  subtitleText,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 12,
                            color: Color(0xFF10B981),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Recorded',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onSelected: (val) async {
                        if (val == 'view') {
                          final res = await Navigator.pushNamed(
                            context,
                            '/meeting_details',
                            arguments: meeting,
                          );
                          if (res == true) {
                            ref.read(meetingsProvider.notifier).fetchMeetings();
                          }
                        } else if (val == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppTheme.cardBg(ctx),
                              title: const Text(
                                'Delete Meeting',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                              content: Text(
                                'Are you sure you want to delete "$displayTitle"?',
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.dangerColor,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ref.read(meetingsProvider.notifier).deleteMeeting(meeting['id'].toString());
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Meeting "$displayTitle" deleted')),
                              );
                            }
                          }
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 18, color: AppTheme.primaryColor),
                              SizedBox(width: 10),
                              Text('View Details', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        if (isHost)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.dangerColor),
                                SizedBox(width: 10),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.dangerColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppTheme.dividerColor),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            hasTranscript
                                ? Icons.auto_awesome_rounded
                                : Icons.description_outlined,
                            size: 15,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              summary.isNotEmpty
                                  ? 'AI Summary & Transcript'
                                  : 'View Meeting Details',
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduledEventCard(
    BuildContext context,
    ScheduledEvent currentEvent,
  ) {
    final isFinished = currentEvent.isFinished;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isFinished
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : AppTheme.cardBorder(context),
          width: isFinished ? 1.5 : 1.0,
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (!currentEvent.isMeeting
                          ? const Color(0xFFF59E0B)
                          : isFinished
                              ? const Color(0xFF10B981)
                              : AppTheme.primaryColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  !currentEvent.isMeeting
                      ? Icons.celebration_rounded
                      : isFinished
                          ? Icons.check_circle_rounded
                          : Icons.event_note_rounded,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentEvent.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: AppTheme.textSecondary.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            currentEvent.isMeeting
                                ? (isFinished
                                    ? '${TimeOfDay.fromDateTime(currentEvent.date).format(context)} • Ended'
                                    : TimeOfDay.fromDateTime(currentEvent.date).format(context))
                                : 'All Day',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (!currentEvent.isMeeting
                          ? const Color(0xFFF59E0B)
                          : isFinished
                              ? const Color(0xFF10B981)
                              : AppTheme.primaryColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (!currentEvent.isMeeting
                            ? const Color(0xFFF59E0B)
                            : isFinished
                                ? const Color(0xFF10B981)
                                : AppTheme.primaryColor)
                        .withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      !currentEvent.isMeeting
                          ? Icons.celebration_rounded
                          : isFinished
                              ? Icons.check_circle_rounded
                              : Icons.schedule_rounded,
                      size: 12,
                      color: !currentEvent.isMeeting
                          ? const Color(0xFFF59E0B)
                          : isFinished
                              ? const Color(0xFF10B981)
                              : AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      !currentEvent.isMeeting
                          ? 'Holiday'
                          : isFinished
                              ? 'Completed'
                              : 'Scheduled',
                      style: TextStyle(
                        color: !currentEvent.isMeeting
                            ? const Color(0xFFF59E0B)
                            : isFinished
                                ? const Color(0xFF10B981)
                                : AppTheme.primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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
                constraints: const BoxConstraints(),
                onSelected: (value) {
                  if (value == 'toggle') {
                    _toggleEventCompleted(currentEvent);
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
                                ? Icons.replay_rounded
                                : Icons.check_circle_rounded,
                            size: 18,
                            color: isFinished
                                ? AppTheme.primaryColor
                                : const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isFinished ? 'Mark as Pending' : 'Mark as Completed',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppTheme.dangerColor,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Delete Event',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.dangerColor,
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
            const Divider(height: 1, color: AppTheme.dividerColor),
            const SizedBox(height: 10),
            if (isFinished)
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            size: 15,
                            color: Color(0xFF10B981),
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Meeting Completed',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                      final result = await Navigator.pushNamed(
                        context,
                        '/active_meeting',
                        arguments: {'title': currentEvent.title},
                      );
                      if (result == true ||
                          (result is Map && result['completed'] == true)) {
                        setState(() {
                          currentEvent.isCompleted = true;
                        });
                        _saveEvents();
                      } else {
                        _loadEvents();
                      }
                    },
                    icon: const Icon(
                      Icons.replay_rounded,
                      size: 15,
                      color: AppTheme.primaryColor,
                    ),
                    label: const Text(
                      'Restart',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
                        _toggleEventCompleted(currentEvent);
                      },
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 15,
                        color: Color(0xFF10B981),
                      ),
                      label: const Text(
                        'Mark Completed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: const Color(0xFF10B981).withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.pushNamed(
                          context,
                          '/active_meeting',
                          arguments: {'title': currentEvent.title},
                        );
                        if (result == true ||
                            (result is Map && result['completed'] == true)) {
                          setState(() {
                            currentEvent.isCompleted = true;
                          });
                          _saveEvents();
                        } else {
                          _loadEvents();
                        }
                      },
                      icon: const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Start Meeting',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
  }
}

class _ScheduleMeetingModalSheet extends StatefulWidget {
  final DateTime initialDate;

  const _ScheduleMeetingModalSheet({
    required this.initialDate,
  });

  @override
  State<_ScheduleMeetingModalSheet> createState() =>
      _ScheduleMeetingModalSheetState();
}

class _ScheduleMeetingModalSheetState
    extends State<_ScheduleMeetingModalSheet> {
  late final TextEditingController _titleController;
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null && mounted) {
      setState(() => _selectedTime = time);
    }
  }

  void _onSave() {
    HapticFeedback.lightImpact();
    final rawTitle = _titleController.text.trim();
    final meetingTitle = rawTitle.isNotEmpty
        ? rawTitle
        : 'Meeting (${_selectedTime.format(context)})';

    Navigator.of(context).pop({
      'title': meetingTitle,
      'time': _selectedTime,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                      controller: _titleController,
                      autofocus: false,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Enter meeting title',
                        hintStyle: TextStyle(color: AppTheme.textSecondary),
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
                    onTap: _pickTime,
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
                            _selectedTime.format(context),
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
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _onSave,
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
  }
}
