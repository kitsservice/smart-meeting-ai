import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ActionItemsScreen extends StatefulWidget {
  const ActionItemsScreen({super.key});

  @override
  State<ActionItemsScreen> createState() => _ActionItemsScreenState();
}

class _ActionItemsScreenState extends State<ActionItemsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // List of maps: {'meetingTitle': '...', 'task': '...', 'isCompleted': false, 'id': '...'}
  List<Map<String, dynamic>> _tasks = [];
  final Set<String> _completedTaskIds = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);

    try {
      final meetings = await _apiService.getMeetings();
      List<Map<String, dynamic>> extractedTasks = [];

      // Only check the 10 most recent meetings to avoid spamming the API
      final recentMeetings = meetings.take(10).toList();

      for (var meeting in recentMeetings) {
        List<dynamic> items = [];

        // If action_items is not in the list response, fetch full details
        if (meeting['action_items'] == null) {
          final fullDetails = await _apiService.getMeeting(
            meeting['id'].toString(),
          );
          if (fullDetails != null && fullDetails['action_items'] != null) {
            items = fullDetails['action_items'];
          }
        } else {
          items = meeting['action_items'];
        }

        final meetingTitle = meeting['title'] ?? 'Untitled Meeting';
        final meetingId = meeting['id'].toString();

        for (int i = 0; i < items.length; i++) {
          var item = items[i];
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

      setState(() {
        _tasks = extractedTasks;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading tasks: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleTask(String taskId, bool? value) async {
    final taskIndex = _tasks.indexWhere((t) => t['id'] == taskId);
    if (taskIndex < 0) return;

    final task = _tasks[taskIndex];
    final newValue = value ?? false;

    // Optimistic UI update
    setState(() {
      _tasks[taskIndex]['isCompleted'] = newValue;
    });

    if (task['isRealObject'] == true) {
      // Send to backend
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
      }
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
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : _tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.task_alt,
                    size: 64,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No action items found.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Record a meeting to generate AI tasks.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
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
            : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: isCompletedList
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: CheckboxListTile(
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
    );
  }
}
