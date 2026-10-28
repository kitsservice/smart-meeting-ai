import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/meetings_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';

class ActionItemsScreen extends ConsumerStatefulWidget {
  const ActionItemsScreen({super.key});

  @override
  ConsumerState<ActionItemsScreen> createState() => _ActionItemsScreenState();
}

class _ActionItemsScreenState extends ConsumerState<ActionItemsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // Filter & Search
  String _activeFilter = 'All'; // 'All', 'Pending', 'Completed'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // List of maps: {'meetingTitle': '...', 'task': '...', 'isCompleted': false, 'id': '...'}
  List<Map<String, dynamic>> _tasks = [];

  // Map of taskId -> ISO string reminder DateTime
  Map<String, String> _remindersMap = {};

  @override
  void initState() {
    super.initState();
    _loadReminders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTasks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('action_item_reminders');
    if (jsonStr != null) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          setState(() {
            _remindersMap = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
          });
        }
      } catch (e) {
        debugPrint('Error decoding action_item_reminders: $e');
      }
    }
  }

  Future<void> _saveReminder(String taskId, DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _remindersMap[taskId] = dt.toIso8601String();
    });
    await prefs.setString('action_item_reminders', jsonEncode(_remindersMap));
  }

  Future<void> _removeReminder(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _remindersMap.remove(taskId);
    });
    await prefs.setString('action_item_reminders', jsonEncode(_remindersMap));
  }

  void _extractTasksFromMeetings(List<dynamic> meetings) {
    final recentMeetings = meetings.take(25).toList();
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
            'id': item['id']?.toString() ?? '${meetingId}_task_$i',
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
    final cachedMeetings = ref.read(meetingsProvider).value;
    if (cachedMeetings != null && cachedMeetings.isNotEmpty) {
      _extractTasksFromMeetings(cachedMeetings);
    } else {
      setState(() => _isLoading = true);
    }

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

    setState(() {
      _tasks[taskIndex]['isCompleted'] = newValue;
    });

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

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Action Item',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this task?\n\n"${task['task']}"',
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    final taskId = task['id'];
    final meetingId = task['meetingId'];

    setState(() {
      _tasks.removeWhere((t) => t['id'] == taskId);
    });
    _removeReminder(taskId);

    ref.read(meetingsProvider.notifier).deleteActionItem(meetingId, taskId);

    final success = await _apiService.deleteActionItem(meetingId, taskId);
    if (!success) {
      _loadTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete task. Please try again.'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action item deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Interactive Smart Reminder Bottom Sheet
  Future<void> _showSmartReminderSheet(Map<String, dynamic> task) async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();

    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.alarm_on_rounded, color: AppTheme.primaryColor, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Set Smart Reminder',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Plays melodic notification chime when task is due.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              // Option 1: Tomorrow 9:00 AM
              _buildReminderOption(
                sheetContext,
                title: 'Tomorrow Morning',
                subtitle: '9:00 AM',
                icon: Icons.wb_sunny_outlined,
                targetDateTime: DateTime(now.year, now.month, now.day + 1, 9, 0),
              ),

              // Option 2: In 2 Days
              _buildReminderOption(
                sheetContext,
                title: 'In 2 Days',
                subtitle: '9:00 AM',
                icon: Icons.event_available_outlined,
                targetDateTime: DateTime(now.year, now.month, now.day + 2, 9, 0),
              ),

              // Option 3: Next Monday
              _buildReminderOption(
                sheetContext,
                title: 'Next Week (Monday)',
                subtitle: '9:00 AM',
                icon: Icons.date_range_outlined,
                targetDateTime: DateTime(
                  now.year,
                  now.month,
                  now.day + (DateTime.monday - now.weekday + 7) % 7 + (now.weekday == DateTime.monday ? 7 : 0),
                  9,
                  0,
                ),
              ),

              // Option 4: Custom Date & Time Picker
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_calendar_rounded, color: AppTheme.accentColor, size: 20),
                ),
                title: const Text('Pick Custom Date & Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Choose any specific time', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                onTap: () async {
                  Navigator.pop(sheetContext);
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

                  final customDt = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                  if (customDt.isAfter(DateTime.now())) {
                    _applyReminder(task, customDt);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a future time for the reminder.')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      _applyReminder(task, selected);
    }
  }

  Widget _buildReminderOption(
    BuildContext sheetContext, {
    required String title,
    required String subtitle,
    required IconData icon,
    required DateTime targetDateTime,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.primaryColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      onTap: () => Navigator.pop(sheetContext, targetDateTime),
    );
  }

  Future<void> _applyReminder(Map<String, dynamic> task, DateTime dt) async {
    await LocalNotificationService().scheduleActionItemReminder(
      taskTitle: task['task'],
      reminderTime: dt,
      meetingTitle: task['meetingTitle'],
    );
    await _saveReminder(task['id'], dt);

    if (mounted) {
      final hourStr = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final minStr = dt.minute.toString().padLeft(2, '0');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔔 Reminder set for ${dt.day}/${dt.month} at $hourStr:$minStr $amPm!',
          ),
          backgroundColor: AppTheme.accentColor,
          duration: const Duration(seconds: 3),
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

  /// Add Custom Action Item Dialog
  Future<void> _showAddActionItemDialog() async {
    final taskController = TextEditingController();
    final assigneeController = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(dialogCtx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_task_rounded, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('Add Action Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: taskController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'What needs to be done?',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: assigneeController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Assignee (e.g. Rahul, John)',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (taskController.text.trim().isNotEmpty) {
                Navigator.pop(dialogCtx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Add Task', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (added == true && taskController.text.trim().isNotEmpty) {
      final taskText = taskController.text.trim();
      final assigneeText = assigneeController.text.trim();

      final firstMeetingId = _tasks.isNotEmpty ? _tasks.first['meetingId'] : 'general';
      final firstMeetingTitle = _tasks.isNotEmpty ? _tasks.first['meetingTitle'] : 'General Tasks';

      final newMap = {
        'id': 'manual_${DateTime.now().millisecondsSinceEpoch}',
        'meetingId': firstMeetingId,
        'meetingTitle': firstMeetingTitle,
        'task': taskText,
        'assignee': assigneeText.isNotEmpty ? assigneeText : null,
        'isCompleted': false,
        'isRealObject': false,
      };

      setState(() {
        _tasks.insert(0, newMap);
      });

      if (firstMeetingId != 'general') {
        _apiService.addCustomActionItem(
          firstMeetingId,
          task: taskText,
          assignee: assigneeText,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action item added!'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter tasks by active tab and search query
    final filtered = _tasks.where((t) {
      if (_activeFilter == 'Pending' && t['isCompleted'] == true) return false;
      if (_activeFilter == 'Completed' && t['isCompleted'] == false) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final taskMatch = t['task'].toString().toLowerCase().contains(q);
        final titleMatch = t['meetingTitle'].toString().toLowerCase().contains(q);
        final assigneeMatch = (t['assignee'] ?? '').toString().toLowerCase().contains(q);
        return taskMatch || titleMatch || assigneeMatch;
      }
      return true;
    }).toList();

    final pendingCount = _tasks.where((t) => !t['isCompleted']).length;
    final completedCount = _tasks.where((t) => t['isCompleted']).length;
    final totalCount = _tasks.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Action Items',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddActionItemDialog,
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'New Task',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const ActionItemsSkeleton()
          : Column(
              children: [
                // 1. Progress Banner (if tasks exist)
                if (totalCount > 0)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.cardBorder(context)),
                      boxShadow: AppTheme.cardShadow(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$completedCount of $totalCount Completed',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: progress == 1.0 ? const Color(0xFF10B981) : AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: AppTheme.dividerColor,
                            color: progress == 1.0 ? const Color(0xFF10B981) : AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                // 2. Search Field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search tasks, meetings, assignees...',
                        hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 3. Filter Chips: All | Pending | Completed
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildFilterChip('All', totalCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', pendingCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('Completed', completedCount),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 4. Tasks List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.task_alt_rounded,
                                  size: 48,
                                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No matching action items'
                                      : (_activeFilter == 'Completed'
                                          ? 'No completed tasks yet'
                                          : 'All caught up!'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Try a different search term.'
                                      : 'Action items extracted from meetings appear here.',
                                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final task = filtered[index];
                            return _buildTaskCard(task);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _activeFilter == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _activeFilter = label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isCompleted = task['isCompleted'] == true;
    final taskId = task['id'].toString();
    final reminderIso = _remindersMap[taskId];
    DateTime? reminderDate;
    if (reminderIso != null) {
      try {
        reminderDate = DateTime.parse(reminderIso);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCompleted ? AppTheme.backgroundColor : AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isCompleted ? AppTheme.dividerColor : AppTheme.cardBorder(context),
        ),
        boxShadow: isCompleted ? const [] : AppTheme.cardShadow(context),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: isCompleted,
            onChanged: (val) => _toggleTask(taskId, val),
            activeColor: AppTheme.primaryColor,
            checkColor: Colors.white,
            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            title: Text(
              task['task'],
              style: TextStyle(
                color: isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Icon(
                    Icons.mic_none_rounded,
                    size: 13,
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
                  if (task['assignee'] != null && task['assignee'].toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

          // Active Smart Reminder Badge (if set)
          if (reminderDate != null)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm_on_rounded, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Reminder: ${reminderDate.day}/${reminderDate.month} at ${reminderDate.hour > 12 ? reminderDate.hour - 12 : (reminderDate.hour == 0 ? 12 : reminderDate.hour)}:${reminderDate.minute.toString().padLeft(2, '0')} ${reminderDate.hour >= 12 ? 'PM' : 'AM'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _removeReminder(taskId),
                    child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),

          // Bottom Action Row (Remind Me | Add to Calendar | Delete)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 8),
            child: Row(
              children: [
                if (!isCompleted) ...[
                  TextButton.icon(
                    onPressed: () => _showSmartReminderSheet(task),
                    icon: const Icon(Icons.notifications_active_outlined, size: 15),
                    label: const Text('Remind Me', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _syncTaskToCalendar(task),
                    icon: const Icon(Icons.calendar_today_outlined, size: 14),
                    label: const Text('Add to Calendar', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.dangerColor),
                  tooltip: 'Delete Task',
                  splashRadius: 18,
                  onPressed: () => _deleteTask(task),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
