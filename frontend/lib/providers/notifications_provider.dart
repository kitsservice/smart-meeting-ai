import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'],
        title: json['title'],
        body: json['body'],
        timestamp: DateTime.parse(json['timestamp']),
        isRead: json['isRead'] ?? false,
      );
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<AppNotification>>((ref) {
      return NotificationsNotifier();
    });

class NotificationsNotifier extends StateNotifier<List<AppNotification>> {
  NotificationsNotifier() : super([]) {
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('app_notifications') ?? [];
    state = data.map((e) => AppNotification.fromJson(jsonDecode(e))).toList();
  }

  Future<void> addNotification(String title, String body) async {
    final newNotif = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      timestamp: DateTime.now(),
    );
    final newState = [newNotif, ...state];
    state = newState;
    await _saveState(newState);
  }

  Future<void> markAllAsRead() async {
    final newState = state
        .map(
          (n) => AppNotification(
            id: n.id,
            title: n.title,
            body: n.body,
            timestamp: n.timestamp,
            isRead: true,
          ),
        )
        .toList();
    state = newState;
    await _saveState(newState);
  }

  Future<void> clearAll() async {
    state = [];
    await _saveState([]);
  }

  Future<void> _saveState(List<AppNotification> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'app_notifications',
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  bool get hasUnread => state.any((n) => !n.isRead);
}
