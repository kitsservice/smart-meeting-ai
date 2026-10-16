import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

class OfflineQueueService {
  static const String _queueKey = 'offline_upload_queue';
  final ApiService _apiService = ApiService();
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal() {
    _startAutoSync();
  }

  void _startAutoSync() {
    // 1. Reactive sync: listen to network status changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        syncPendingUploads();
      }
    });

    // 2. Periodic heartbeat fallback (every 45 seconds)
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      syncPendingUploads();
    });
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> queueMeeting(
    String title,
    String description,
    String filePath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    // Add new pending meeting with explicit user ownership
    queueJson.add(
      jsonEncode({
        'title': title,
        'description': description,
        'filePath': filePath,
        'userId': currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    await prefs.setStringList(_queueKey, queueJson);

    // Try syncing immediately if online
    syncPendingUploads();
  }

  Future<void> syncPendingUploads() async {
    if (_isSyncing) return; // Prevent concurrent overlapping sync operations

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return; // Still offline
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return; // Await authentication
    }

    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    if (queueJson.isEmpty) return;

    _isSyncing = true;
    final List<String> remainingQueue = [];

    try {
      for (final String item in queueJson) {
        try {
          final data = jsonDecode(item);
          final itemUserId = data['userId'] as String?;

          // STRICT USER ISOLATION:
          // If this recording belongs to another account on this phone, preserve it safely.
          if (itemUserId != null &&
              itemUserId.isNotEmpty &&
              itemUserId != currentUserId) {
            remainingQueue.add(item);
            continue;
          }

          final filePath = data['filePath'] as String?;
          // Guard: Verify file actually exists before creating meeting record to prevent ghost entries
          if (filePath == null || !File(filePath).existsSync()) {
            debugPrint(
              'Offline audio file does not exist: $filePath. Dropping from sync queue to avoid ghost meetings.',
            );
            continue;
          }

          // 1. Create meeting
          final String? meetingId = await _apiService.createMeeting(
            data['title'],
            data['description'],
          );

          // 2. Upload audio
          if (meetingId != null) {
            await _apiService.processAudio(meetingId, filePath);
            debugPrint('Successfully synced offline meeting: ${data['title']}');

            final notifsKey = 'app_notifications_$currentUserId';
            final notifs = prefs.getStringList(notifsKey) ?? [];
            notifs.insert(
              0,
              jsonEncode({
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'title': 'Transcription Complete',
                'body':
                    'Your meeting "${data['title']}" has been successfully transcribed and summarized.',
                'timestamp': DateTime.now().toIso8601String(),
                'isRead': false,
              }),
            );
            await prefs.setStringList(notifsKey, notifs);
          } else {
            remainingQueue.add(item); // Keep in queue if creation failed
          }
        } catch (e) {
          debugPrint('Error syncing item: $e');
          remainingQueue.add(item); // Keep in queue if error occurred
        }
      }

      // Save remaining items
      await prefs.setStringList(_queueKey, remainingQueue);
    } finally {
      _isSyncing = false;
    }
  }
}
