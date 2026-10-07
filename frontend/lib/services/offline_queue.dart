import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'api_service.dart';

class OfflineQueueService {
  static const String _queueKey = 'offline_upload_queue';
  final ApiService _apiService = ApiService();
  Timer? _syncTimer;

  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal() {
    _startAutoSync();
  }

  void _startAutoSync() {
    // Check every 30 seconds if internet is back and we have queued files
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncPendingUploads();
    });
  }

  Future<void> queueMeeting(
    String title,
    String description,
    String filePath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];

    // Add new pending meeting
    queueJson.add(
      jsonEncode({
        'title': title,
        'description': description,
        'filePath': filePath,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    await prefs.setStringList(_queueKey, queueJson);

    // Try syncing immediately
    syncPendingUploads();
  }

  Future<void> syncPendingUploads() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return; // Still offline
    }

    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    if (queueJson.isEmpty) return;

    List<String> failedQueue = [];

    for (String item in queueJson) {
      try {
        final data = jsonDecode(item);

        // 1. Create meeting
        String? meetingId = await _apiService.createMeeting(
          data['title'],
          data['description'],
        );

        // 2. Upload audio
        if (meetingId != null) {
          await _apiService.processAudio(meetingId, data['filePath']);
          print('Successfully synced offline meeting: ${data['title']}');

          final notifs = prefs.getStringList('app_notifications') ?? [];
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
          await prefs.setStringList('app_notifications', notifs);
        } else {
          failedQueue.add(item); // Keep it in queue if creation failed
        }
      } catch (e) {
        print('Error syncing item: $e');
        failedQueue.add(
          item,
        ); // Keep in queue if network error occurred during upload
      }
    }

    // Save only the ones that failed
    await prefs.setStringList(_queueKey, failedQueue);
  }
}
