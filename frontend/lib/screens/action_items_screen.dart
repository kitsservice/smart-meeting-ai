import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/meetings_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';

class ActionItemsScreen extends ConsumerStatefulWidget {
  const ActionItemsScreen({super.key});

  @override
  ConsumerState<ActionItemsScreen> createState() => _ActionItemsScreenState();
}

class _ActionItemsScreenState extends ConsumerState<ActionItemsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // List of maps: {'meetingTitle': '...', 'task': '...', 'isCompleted': false, 'id': '...'}
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTasks();
    });
  }

  void _extractTasksFromMeetings(List<dynamic> meetings) {
    final recentMeetings = meetings.take(15).toList();
    final List<Map<String, dynamic>> extractedTasks = [];

    for (final meeting in recentMeetings) {
      final items = meeting['action_items'];
      if (items is! List) continue;

      final meetingTitle = meeting['title'] ?? 'Untitled Meeting';
      final meetingId = meeting['id'].toString();

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        if (item is Map) {
          extractedTasks.add({
            'id': item['id'] ?? '${meetingId}_task_$i',
            'meetingId': meetingId,
            'meetingTitle': meetingTitle,
            'task': item['task']?.toString() ?? 'Empty Task',
            'assignee': item['assignee'],
            'isCompleted': item['is_completed'] ?? false,
            'isRealObject': item.containsKey('id'),
          });
        } else {
          extractedTasks.add({
            'id': '${meetingId}_task_$i',
            'meetingId': meetingId,
            'meetingTitle': meetingTitle,
            'task': item.toString(),
            'isCompleted': false,
            'isRealObject': false,
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _tasks = extractedTasks;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTasks() async {
    // 1. Instant render from Riverpod in-memory cache
    final cachedMeetings = ref.read(meetingsProvider).value;
    if (cachedMeetings != null && cachedMeetings.isNotEmpty) {
      _extractTasksFromMeetings(cachedMeetings);
    } else {
      setState(() => _isLoading = true);
    }

    // 2. Background sync
    try {
      await ref.read(meetingsProvider.notifier).fetchMeetings();
      final freshMeetings = ref.read(meetingsProvider).value ?? [];
      _extractTasksFromMeetings(freshMeetings);
    } catch (e) {
      debugPrint('Error loading tasks via Riverpod: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleTask(String taskId, bool? value) async {
    final taskIndex = _tasks.indexWhere((t) => t['id'] == taskId);
    if (taskIndex < 0) return;

    HapticFeedback.lightImpact();
    final task = _tasks[taskIndex];
    final newValue = value ?? false;

    // Optimistic UI update locally
    setState(() {
      _tasks[taskIndex]['isCompleted'] = newValue;
    });

    // Update in-memory Riverpod meetings cache so all screens stay in sync
    ref.read(meetingsProvider.notifier).updateActionItem(
      task['meetingId'],
      task['id'],
      newValue,
    );

    if (task['isRealObject'] == true) {
      final success = await _apiService.updateActionItemStatus(
        task['meetingId'],
        task['id'],
        newValue,
      );
      if (!success) {
        // Revert on failure
        setState(() {
          _tasks[taskIndex]['isCompleted'] = !newValue;
        });
        ref.read(meetingsProvider.notifier).updateActionItem(
          task['meetingId'],
          task['id'],
          !newValue,
        );
      }
    }
  }

  Future<void> _scheduleReminderForTask(Map<String, dynamic> task) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (pickedTime == null || !mounted) return;

    final reminderDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (reminderDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a future time for the reminder.')),
      );
      return;
    }

    await LocalNotificationService().scheduleActionItemReminder(
      taskTitle: task['task'],
      reminderTime: reminderDateTime,
      meetingTitle: task['meetingTitle'],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminder set for ${pickedDate.day}/${pickedDate.month} at ${pickedTime.format(context)}',
          ),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    }
  }

  Future<void> _syncTaskToCalendar(Map<String, dynamic> task) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (pickedTime == null || !mounted) return;

    final startDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final success = await CalendarService().addToDeviceCalendar(
      title: 'Action Item: ${task['task']}',
      startTime: startDateTime,
      description: 'From meeting: ${task['meetingTitle']}\nAssignee: ${task['assignee'] ?? 'Unassigned'}',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Task added to your Device Calendar!'
                : 'Could not add to Calendar. Please grant calendar permission in device settings.',
          ),
          backgroundColor: success ? AppTheme.primaryColor : AppTheme.dangerColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingTasks = _tasks.where((t) => !t['isCompleted']).toList();
    final completedTasks = _tasks.where((t) => t['isCompleted']).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Action Items',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Action Items',
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadTasks();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : _tasks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.task_alt_rounded,
                        size: 52,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'All Caught Up!',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No pending action items found. Tasks mentioned in your meetings will automatically appear here with assignees.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pushNamed(context, '/active_meeting');
                      },
                      icon: const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Start a Meeting',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                if (pendingTasks.isEmpty && completedTasks.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.celebration_rounded,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'All tasks completed! 🎉',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Great job staying on top of your meeting action items.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (pendingTasks.isNotEmpty) ...[
                  const Text(
                    'Pending Tasks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...pendingTasks.map((t) => _buildTaskCard(t)),
                  const SizedBox(height: 32),
                ],

                if (completedTasks.isNotEmpty) ...[
                  const Text(
                    'Completed',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...completedTasks.map(
                    (t) => _buildTaskCard(t, isCompletedList: true),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildTaskCard(
    Map<String, dynamic> task, {
    bool isCompletedList = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCompletedList
            ? AppTheme.backgroundColor
            : AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: isCompletedList ? const [] : AppTheme.cardShadow(context),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: task['isCompleted'],
            onChanged: (val) => _toggleTask(task['id'], val),
            activeColor: AppTheme.primaryColor,
            checkColor: Colors.white,
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            title: Text(
              task['task'],
              style: TextStyle(
                color: isCompletedList
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                decoration: isCompletedList
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Icon(
                    Icons.mic,
                    size: 14,
                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      task['meetingTitle'],
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (task['assignee'] != null &&
                      task['assignee'].toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task['assignee'],
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isCompletedList)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _scheduleReminderForTask(task),
                    icon: const Icon(Icons.notifications_active_outlined, size: 16),
                    label: const Text('Remind Me', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _syncTaskToCalendar(task),
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: const Text('Add to Calendar', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
