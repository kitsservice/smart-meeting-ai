import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  static String? _cachedBaseUrl;

  static String? _getEnv(String key) {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env[key];
      }
    } catch (_) {}
    return null;
  }

  static const String defaultProdUrl =
      'https://smart-meeting-ai-7qub.onrender.com/api/v1';

  static bool _isLocalAddress(String url) {
    final lower = url.toLowerCase();
    return lower.contains('127.0.0.1') ||
        lower.contains('localhost') ||
        lower.contains('10.0.2.2') ||
        lower.contains('192.168.') ||
        lower.contains('10.169.');
  }

  static List<String> get candidateBaseUrls {
    final list = <String>[];
    if (_cachedBaseUrl != null && _cachedBaseUrl!.isNotEmpty) {
      list.add(_cachedBaseUrl!);
    }
    final configured = _getEnv('PROD_API_BASE_URL')?.trim() ??
        _getEnv('API_BASE_URL')?.trim();
    if (configured != null &&
        configured.isNotEmpty &&
        !list.contains(configured)) {
      list.add(configured);
    }
    if (!list.contains(defaultProdUrl)) {
      list.add(defaultProdUrl);
    }
    // Only in local development debug mode include loopback
    if (!kReleaseMode) {
      const devDefaults = [
        'http://127.0.0.1:8000/api/v1',
        'http://10.0.2.2:8000/api/v1',
        'http://192.168.1.8:8000/api/v1',
      ];
      for (final d in devDefaults) {
        if (!list.contains(d)) list.add(d);
      }
    }
    return list;
  }

  static Uri _getHealthUri(String base) {
    if (base.endsWith('/api/v1')) {
      return Uri.parse(base.replaceAll('/api/v1', '/health'));
    }
    return Uri.parse('$base/health');
  }

  static Future<String> resolveBaseUrl() async {
    if (_cachedBaseUrl != null && _cachedBaseUrl!.isNotEmpty) {
      return _cachedBaseUrl!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('cached_api_base_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _cachedBaseUrl = savedUrl;
        return savedUrl;
      }
    } catch (_) {}

    // Fast probe candidates
    for (final candidate in candidateBaseUrls) {
      try {
        final probeUri = _getHealthUri(candidate);
        final res = await http.get(probeUri).timeout(const Duration(milliseconds: 1200));
        if (res.statusCode == 200) {
          _cachedBaseUrl = candidate;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_api_base_url', candidate);
          } catch (_) {}
          return candidate;
        }
      } catch (_) {}
    }

    _cachedBaseUrl = defaultProdUrl;
    return defaultProdUrl;
  }

  static String get baseUrl {
    if (_cachedBaseUrl != null && _cachedBaseUrl!.isNotEmpty) return _cachedBaseUrl!;
    final configured = _getEnv('API_BASE_URL')?.trim();
    if (configured != null &&
        configured.isNotEmpty &&
        configured.startsWith('https://') &&
        !_isLocalAddress(configured)) {
      return configured;
    }
    return defaultProdUrl;
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final http.Client _client = http.Client(); // Persistent client

  String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _getHeaders({bool isMultipart = false}) {
    String? token;
    try {
      token = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {}
    final headers = <String, String>{};
    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<bool> _isBaseUrlAlive(String base) async {
    try {
      final rootUri = _getHealthUri(base);
      final res = await _client.get(rootUri).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return true;
    } catch (_) {}
    try {
      final apiUri = Uri.parse('$base/health');
      final res = await _client.get(apiUri).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return true;
    } catch (_) {}
    return false;
  }

  Future<List<dynamic>> getMeetings() async {
    final userId = _currentUserId ?? '';
    if (userId.isEmpty) {
      return []; // Return empty list immediately if not logged in
    }

    // 1. Authoritative direct Supabase query: instant (<100ms) with zero cold-start delay
    try {
      final data = await Supabase.instance.client
          .from('meetings')
          .select('id, title, description, created_at, summary, transcript, action_items, user_id')
          .or('user_id.eq.$userId,description.ilike.%$userId%')
          .order('created_at', ascending: false)
          .limit(50);
      return _filterValidMeetings(data as List<dynamic>);
    } catch (e) {
      debugPrint('Direct Supabase fetch failed: $e, falling back to backend...');
    }

    // 2. Resilient fallback to backend API
    try {
      final base = await resolveBaseUrl();
      final url = Uri.parse('$base/meetings/?user_id=$userId');
      final response = await _client
          .get(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        _cachedBaseUrl = base;
        final list = jsonDecode(response.body) as List<dynamic>;
        return _filterValidMeetings(list);
      }
    } catch (e) {
      debugPrint('Backend meetings fetch fallback error: $e');
    }

    return [];
  }

  List<dynamic> _filterValidMeetings(List<dynamic> list) {
    return list.where((m) {
      final desc = (m['description'] ?? '').toString();
      final title = (m['title'] ?? '').toString();
      final transcript = (m['transcript'] ?? '').toString().trim();
      final summary = (m['summary'] ?? '').toString().trim();

      // Exclude aborted or discarded sessions
      if (desc.contains('Closed before start') ||
          desc.contains('Discarded by host')) {
        return false;
      }

      // Exclude empty room-code placeholders with no transcript or summary
      final hasTranscript = transcript.isNotEmpty &&
          transcript != 'null' &&
          transcript != 'NONE';
      final hasSummary =
          summary.isNotEmpty && summary != 'null' && summary != 'NONE';
      if (!hasTranscript && !hasSummary) {
        if (desc.contains('[ROOM_CODE:') ||
            title.startsWith('Meeting ') ||
            title.startsWith('Completed Meeting ')) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<Map<String, dynamic>?> getMeeting(String meetingId) async {
    String userId = '';
    try {
      userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}

    // 1. Authoritative direct Supabase query: instant and always current
    try {
      var query = Supabase.instance.client
          .from('meetings')
          .select('*')
          .eq('id', meetingId);

      if (userId.isNotEmpty) {
        query = query.or('user_id.eq.$userId,description.ilike.%$userId%');
      }

      final data = await query.maybeSingle();
      if (data != null) {
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('Direct Supabase getMeeting error: $e, falling back to backend');
    }

    // 2. Resilient fallback to backend API
    try {
      final base = await resolveBaseUrl();
      final url = Uri.parse('$base/meetings/$meetingId?user_id=$userId');
      final response = await _client
          .get(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        _cachedBaseUrl = base;
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 403) {
        debugPrint('Security: Access denied to meeting $meetingId for user $userId');
        return null;
      }
    } catch (e) {
      debugPrint('Backend getMeeting fallback failed: $e');
    }

    return null;
  }

  Future<bool> deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    final url = Uri.parse('$baseUrl/users/${user.id}');
    try {
      final response = await _client.delete(url, headers: _getHeaders());
      if (response.statusCode == 200) {
        await Supabase.instance.client.auth.signOut();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting account: $e');
    }
    return false;
  }

  Future<bool> deleteMeeting(String meetingId) async {
    final url = Uri.parse('$baseUrl/meetings/$meetingId');
    try {
      final response = await _client
          .delete(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting meeting via backend: $e');
    }

    // Direct Supabase fallback
    try {
      await Supabase.instance.client
          .from('meetings')
          .delete()
          .eq('id', meetingId);
      return true;
    } catch (e) {
      debugPrint('Direct Supabase delete error: $e');
    }
    return false;
  }

  Future<String?> createMeeting(String title, String description) async {
    final userId = _currentUserId;

    if (userId == null || userId.isEmpty) {
      debugPrint('createMeeting error: No authenticated user found');
      return null;
    }

    // If description contains a room code, check if room meeting already exists in Supabase
    if (description.contains('[ROOM_CODE:')) {
      final match = RegExp(r'\[ROOM_CODE:([0-9]{6})\]').firstMatch(description);
      if (match != null) {
        final code = match.group(1);
        try {
          final existing = await Supabase.instance.client
              .from('meetings')
              .select('id, description')
              .ilike('description', '%[ROOM_CODE:$code]%')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (existing != null) {
            final existingId = existing['id'].toString();
            String finalDesc = description;
            final existingDesc = (existing['description'] ?? '').toString();
            if (!finalDesc.contains('[MEMBERS:') &&
                existingDesc.contains('[MEMBERS:')) {
              final memMatch =
                  RegExp(r'\[MEMBERS:\[.*?\]\]').firstMatch(existingDesc);
              if (memMatch != null) {
                finalDesc = '$finalDesc ${memMatch.group(0)}'.trim();
              }
            }
            await Supabase.instance.client
                .from('meetings')
                .update({
                  'title': title,
                  'description': finalDesc,
                  'user_id': userId,
                })
                .eq('id', existingId);
            return existingId;
          }
        } catch (e) {
          debugPrint('Error reusing room meeting in createMeeting: $e');
        }
      }
    }

    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name'] ??
        user?.userMetadata?['name'] ??
        (user?.email?.split('@')[0] ?? 'Host');
    String descWithMembers = description;
    if (!descWithMembers.contains('[MEMBERS:')) {
      final membersJson = jsonEncode([
        {
          'user_id': userId,
          'name': userName,
          'is_host': true,
        }
      ]);
      descWithMembers = '$descWithMembers [MEMBERS:$membersJson]'.trim();
    }

    final url = Uri.parse('$baseUrl/meetings/');

    try {
      final response = await _client
          .post(
            url,
            headers: _getHeaders(),
            body: jsonEncode({
              'title': title,
              'description': descWithMembers,
              'user_id': userId,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['id']; // Return the meeting ID for audio upload
      } else {
        debugPrint('Failed to save meeting via backend: ${response.body}');
      }
    } catch (e) {
      debugPrint('Backend save failed, attempting direct Supabase insert: $e');
    }

    // Direct Supabase fallback: Guarantee meeting is ALWAYS created under this user_id
    try {
      final response = await Supabase.instance.client
          .from('meetings')
          .insert({
            'title': title,
            'description': description,
            'user_id': userId,
          })
          .select()
          .single();
      return response['id'];
    } catch (e) {
      debugPrint('Direct Supabase insert error: $e');
    }

    return null;
  }

  Future<bool> processAudio(
    String meetingId,
    String filePath, {
    String? language,
  }) async {
    if (_cachedBaseUrl == null || _cachedBaseUrl!.isEmpty) {
      await resolveBaseUrl();
    }

    String selectedLang = language ?? '';
    if (selectedLang.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        selectedLang = prefs.getString('setting_lang_priority') ?? 'Auto-Detect';
      } catch (_) {}
    }

    for (final base in candidateBaseUrls) {
      final url = Uri.parse(
        '$base/meetings/$meetingId/process-audio?language=${Uri.encodeComponent(selectedLang)}',
      );

      try {
        // Fast probe before committing 90-second upload to an unverified candidate
        if (_cachedBaseUrl != base) {
          final isAlive = await _isBaseUrlAlive(base);
          if (!isAlive) continue;
        }

        var request = http.MultipartRequest('POST', url);
        request.headers.addAll(_getHeaders(isMultipart: true));
        if (selectedLang.isNotEmpty) {
          request.fields['language'] = selectedLang;
        }

        // Attach the real audio file
        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 90));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('Audio processed successfully on $base!');
          _cachedBaseUrl = base;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_api_base_url', base);
          } catch (_) {}
          return true;
        } else {
          debugPrint('Failed to process audio on $base: ${response.body}');
        }
      } catch (e) {
        debugPrint('Error processing audio on $base: $e');
      }
    }
    return false;
  }

  Future<List<dynamic>> searchSemanticMeetings(String query) async {
    if (_cachedBaseUrl == null || _cachedBaseUrl!.isEmpty) {
      await resolveBaseUrl();
    }
    final userId = _currentUserId ?? '';
    for (final base in candidateBaseUrls) {
      final url = Uri.parse(
        '$base/meetings/search/semantic?query=${Uri.encodeComponent(query)}&user_id=$userId',
      );
      try {
        final response = await _client
            .get(url, headers: _getHeaders())
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          _cachedBaseUrl = base;
          return data['data'] as List<dynamic>;
        } else {
          debugPrint('Failed to semantic search on $base: ${response.body}');
        }
      } catch (e) {
        debugPrint('Error doing semantic search on $base: $e');
      }
    }
    return [];
  }

  Future<bool> isVoiceCalibrated([String? userId]) async {
    try {
      final uid = userId ?? _currentUserId;
      if (uid == null || uid.isEmpty) return false;
      final res = await Supabase.instance.client
          .from('users')
          .select('voice_profile_url, voice_embedding')
          .eq('id', uid)
          .maybeSingle();
      if (res == null) return false;
      final embedding = res['voice_embedding'];
      final bool hasEmbedding = embedding != null &&
          (embedding is List && embedding.length == 192);
      return hasEmbedding;
    } catch (e) {
      debugPrint('Error checking voice calibration: $e');
      return false;
    }
  }

  Future<bool> enrollVoice(String filePath, {String? fullNameOverride}) async {
    final userId = _currentUserId ?? '';
    String fullName = fullNameOverride ?? '';
    if (fullName.isEmpty) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        fullName = user?.userMetadata?['full_name'] ??
            user?.userMetadata?['name'] ??
            '';
        if (fullName.isEmpty && user?.email != null) {
          fullName = user!.email!.split('@')[0];
        }
      } catch (_) {}
    }
    if (userId.isEmpty) {
      debugPrint('Error enrolling voice: user not authenticated');
      return false;
    }

    for (final base in candidateBaseUrls) {
      final url = Uri.parse(
        '$base/users/enroll-voice?user_id=$userId&full_name=${Uri.encodeComponent(fullName)}',
      );

      try {
        if (_cachedBaseUrl != base && _isLocalAddress(base)) {
          final isAlive = await _isBaseUrlAlive(base);
          if (!isAlive) continue;
        }

        debugPrint('Attempting voice enrollment at: $url');
        var request = http.MultipartRequest('POST', url);
        request.headers.addAll(_getHeaders(isMultipart: true));

        // Attach the audio file
        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        // Render cold start can take 25-45s; allow 60s for full neural extraction
        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 60));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          debugPrint('Voice enrolled successfully on $base!');
          _cachedBaseUrl = base;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_api_base_url', base);
          } catch (_) {}
          return true;
        } else {
          debugPrint('Failed to enroll voice on $base (${response.statusCode}): ${response.body}');
        }
      } catch (e) {
        debugPrint('Error enrolling voice on $base: $e');
      }
    }

    debugPrint('All candidate base URLs failed for voice enrollment.');
    return false;
  }

  Future<bool> enrollVoiceMulti(
    List<String> filePaths, {
    String? fullNameOverride,
  }) async {
    final userId = _currentUserId ?? '';
    String fullName = fullNameOverride ?? '';
    if (fullName.isEmpty) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        fullName = user?.userMetadata?['full_name'] ??
            user?.userMetadata?['name'] ??
            '';
        if (fullName.isEmpty && user?.email != null) {
          fullName = user!.email!.split('@')[0];
        }
      } catch (_) {}
    }
    if (userId.isEmpty || filePaths.isEmpty) {
      debugPrint('Error enrolling multi-sample voice: user not authenticated or files empty');
      return false;
    }

    for (final base in candidateBaseUrls) {
      final url = Uri.parse(
        '$base/users/enroll-voice-multi?user_id=$userId&full_name=${Uri.encodeComponent(fullName)}',
      );

      try {
        if (_cachedBaseUrl != base && _isLocalAddress(base)) {
          final isAlive = await _isBaseUrlAlive(base);
          if (!isAlive) continue;
        }

        debugPrint('Attempting multi-sample voice enrollment at: $url (${filePaths.length} samples)');
        var request = http.MultipartRequest('POST', url);
        request.headers.addAll(_getHeaders(isMultipart: true));

        for (final p in filePaths) {
          request.files.add(await http.MultipartFile.fromPath('files', p));
        }

        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 75));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          debugPrint('Multi-sample voice enrolled successfully on $base!');
          _cachedBaseUrl = base;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_api_base_url', base);
          } catch (_) {}
          return true;
        } else {
          debugPrint('Failed to enroll multi-sample voice on $base (${response.statusCode}): ${response.body}');
        }
      } catch (e) {
        debugPrint('Error in multi-sample enrollment on $base: $e');
      }
    }
    // Fallback to single enrollment of last sample if multi-sample endpoint unavailable
    if (filePaths.isNotEmpty) {
      return enrollVoice(filePaths.last, fullNameOverride: fullNameOverride);
    }
    return false;
  }

  Future<Map<String, dynamic>?> verifyVoice(String filePath) async {
    final userId = _currentUserId ?? '';
    if (userId.isEmpty) return null;

    for (final base in candidateBaseUrls) {
      final url = Uri.parse('$base/users/verify-voice?user_id=$userId');

      try {
        if (_cachedBaseUrl != base && _isLocalAddress(base)) {
          final isAlive = await _isBaseUrlAlive(base);
          if (!isAlive) continue;
        }

        var request = http.MultipartRequest('POST', url);
        request.headers.addAll(_getHeaders(isMultipart: true));
        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 45));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic>) {
            return data;
          }
        }
      } catch (e) {
        debugPrint('Error testing voice match on $base: $e');
      }
    }
    return null;
  }

  Future<bool> updateActionItemStatus(
    String meetingId,
    String actionItemId,
    bool isCompleted,
  ) async {
    final url = Uri.parse(
      '$baseUrl/meetings/$meetingId/action-items/$actionItemId?is_completed=$isCompleted',
    );
    try {
      final response = await _client
          .patch(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('Error updating action item via backend, using Supabase: $e');
    }

    // Direct Supabase fallback
    try {
      final res = await Supabase.instance.client
          .from('meetings')
          .select('action_items')
          .eq('id', meetingId)
          .maybeSingle();

      if (res != null && res['action_items'] is List) {
        final items = List<dynamic>.from(res['action_items']);
        bool itemFound = false;
        for (var item in items) {
          if (item is Map && item['id']?.toString() == actionItemId) {
            item['is_completed'] = isCompleted;
            itemFound = true;
            break;
          }
        }
        if (itemFound) {
          await Supabase.instance.client
              .from('meetings')
              .update({'action_items': items})
              .eq('id', meetingId);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Direct Supabase updateActionItemStatus error: $e');
    }

    return false;
  }

  Future<bool> deleteActionItem(
    String meetingId,
    String actionItemId,
  ) async {
    final url = Uri.parse(
      '$baseUrl/meetings/$meetingId/action-items/$actionItemId',
    );
    try {
      final response = await _client
          .delete(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting action item via backend, using Supabase: $e');
    }

    // Direct Supabase fallback
    try {
      final res = await Supabase.instance.client
          .from('meetings')
          .select('action_items')
          .eq('id', meetingId)
          .maybeSingle();

      if (res != null && res['action_items'] is List) {
        final items = List<dynamic>.from(res['action_items']);
        final initialLength = items.length;
        items.removeWhere(
          (item) => item is Map && item['id']?.toString() == actionItemId,
        );

        if (items.length != initialLength) {
          await Supabase.instance.client
              .from('meetings')
              .update({'action_items': items})
              .eq('id', meetingId);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Direct Supabase deleteActionItem error: $e');
    }

    return false;
  }

  /// AI Chat with past meetings ("Ask Ares")
  Future<Map<String, dynamic>> askAres(
    String query, {
    String? meetingId,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return {'answer': 'Please enter a valid question.', 'sources': []};
    }

    final userId = _currentUserId;
    final url = Uri.parse('$baseUrl/meetings/ask');
    final payload = {
      'query': cleanQuery,
      'meeting_id': meetingId,
      'user_id': userId,
    };

    try {
      final response = await _client
          .post(
            url,
            headers: _getHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return {
          'answer': (decoded['answer'] ?? 'No response returned.').toString(),
          'sources': decoded['sources'] as List? ?? [],
        };
      }
    } catch (e) {
      debugPrint('Error contacting backend /meetings/ask: $e');
    }

    // Direct Supabase Search Fallback when backend is offline
    try {
      final meetingsRes = await Supabase.instance.client
          .from('meetings')
          .select('id, title, summary, action_items, created_at')
          .order('created_at', ascending: false)
          .limit(8);

      final meetings = meetingsRes as List<dynamic>;
      final matching = <String>[];
      final sources = <Map<String, dynamic>>[];
      final qLower = cleanQuery.toLowerCase();

      for (var m in meetings) {
        final title = (m['title'] ?? 'Untitled').toString();
        final summary = (m['summary'] ?? '').toString();
        final items = m['action_items'] is List ? (m['action_items'] as List) : [];

        bool matched = false;
        if (title.toLowerCase().contains(qLower) ||
            summary.toLowerCase().contains(qLower)) {
          matched = true;
        } else {
          for (var it in items) {
            final tStr = (it is Map ? it['task'] : it).toString().toLowerCase();
            if (tStr.contains(qLower)) {
              matched = true;
              break;
            }
          }
        }

        if (matched) {
          sources.add({'id': m['id'], 'title': title});
          matching.add(
            '📅 **$title**\n'
            '${summary.isNotEmpty ? summary : "No summary available."}\n'
            '${items.isNotEmpty ? "• Tasks: ${items.map((i) => i is Map ? i['task'] : i).join(', ')}" : ""}',
          );
        }
      }

      if (matching.isNotEmpty) {
        return {
          'answer':
              'Here is what was found in your meeting records matching your query:\n\n${matching.join("\n\n---\n\n")}',
          'sources': sources,
        };
      } else if (meetings.isNotEmpty) {
        return {
          'answer':
              'I searched your recent meetings (${meetings.map((m) => m['title']).take(3).join(', ')}), but did not find any direct mentions of "$cleanQuery". Try asking with different keywords or specifying a meeting title.',
          'sources': [],
        };
      }
    } catch (e) {
      debugPrint('Supabase direct query error in askAres: $e');
    }

    return {
      'answer':
          'Unable to query your meetings right now. Please check your internet connection.',
      'sources': [],
    };
  }

  /// Adds a custom action item to a meeting
  Future<bool> addCustomActionItem(
    String meetingId, {
    required String task,
    String? assignee,
  }) async {
    final newItem = {
      'id': 'manual_${DateTime.now().millisecondsSinceEpoch}',
      'task': task.trim(),
      'assignee': assignee?.trim().isNotEmpty == true ? assignee!.trim() : null,
      'is_completed': false,
    };

    try {
      final res = await Supabase.instance.client
          .from('meetings')
          .select('action_items')
          .eq('id', meetingId)
          .maybeSingle();

      List<dynamic> items = [];
      if (res != null && res['action_items'] is List) {
        items = List<dynamic>.from(res['action_items']);
      }
      items.add(newItem);

      await Supabase.instance.client
          .from('meetings')
          .update({'action_items': items})
          .eq('id', meetingId);
      return true;
    } catch (e) {
      debugPrint('Error adding action item: $e');
      return false;
    }
  }

  /// Fetches an aggregated daily executive report and short summary for a specific date (YYYY-MM-DD)
  Future<Map<String, dynamic>> getDailyReport({String? date, String? userId}) async {
    final targetDate = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final uid = userId ?? _currentUserId;

    final queryParams = <String, String>{'date': targetDate};
    if (uid != null && uid.isNotEmpty) {
      queryParams['user_id'] = uid;
    }

    final uri = Uri.parse('$baseUrl/meetings/daily-report').replace(
      queryParameters: queryParams,
    );

    try {
      final response = await _client
          .get(uri, headers: _getHeaders())
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error fetching daily report from backend: $e');
    }

    // Direct Supabase Fallback when backend is unreachable
    try {
      final start = '${targetDate}T00:00:00';
      final end = '${targetDate}T23:59:59.999999';

      var query = Supabase.instance.client
          .from('meetings')
          .select('id, title, description, created_at, summary, transcript, action_items, user_id')
          .gte('created_at', start)
          .lte('created_at', end);

      if (uid != null && uid.isNotEmpty) {
        query = query.or('user_id.eq.$uid,description.ilike.%$uid%');
      }

      final res = await query.order('created_at', ascending: true);
      final list = res as List<dynamic>;

      if (list.isEmpty) {
        return {
          'status': 'empty',
          'date': targetDate,
          'message': 'No meetings recorded on this date.',
          'total_meetings': 0,
          'total_duration_formatted': '0 mins',
          'attendees': [],
          'short_summary': 'No meetings were recorded on this date.',
          'key_decisions': [],
          'action_items': [],
          'action_items_by_assignee': {},
          'meeting_highlights': [],
        };
      }

      final allTasks = <Map<String, dynamic>>[];
      final attendeesSet = <String>{};
      final summaries = <String>[];

      for (var m in list) {
        final title = (m['title'] ?? 'Meeting').toString();
        final summary = (m['summary'] ?? '').toString();
        if (summary.isNotEmpty) {
          summaries.add('$title: ${summary.split(".")[0]}.');
        }
        final items = m['action_items'] is List ? (m['action_items'] as List) : [];
        for (var it in items) {
          if (it is Map) {
            final task = (it['task'] ?? it['text'] ?? '').toString();
            final assignee = (it['assignee'] ?? 'Unassigned').toString();
            if (task.isNotEmpty) {
              allTasks.add({
                'id': it['id'] ?? '',
                'task': task,
                'assignee': assignee,
                'meeting_title': title,
                'is_completed': it['is_completed'] == true,
              });
              if (assignee != 'Unassigned') attendeesSet.add(assignee);
            }
          }
        }
      }

      final shortSummary = summaries.isNotEmpty
          ? 'On $targetDate, ${list.length} meeting(s) took place. ${summaries.take(3).join(" ")} Total of ${allTasks.length} action item(s) logged.'
          : 'On $targetDate, ${list.length} meeting(s) took place with ${allTasks.length} action item(s) captured.';

      return {
        'status': 'success',
        'date': targetDate,
        'total_meetings': list.length,
        'total_duration_formatted': '${list.length * 15} mins',
        'attendees': attendeesSet.toList(),
        'short_summary': shortSummary,
        'key_decisions': [],
        'action_items': allTasks,
        'meeting_highlights': list.map((m) => {
          'id': m['id'],
          'title': m['title'] ?? 'Meeting',
          'short_summary': m['summary'] ?? '',
          'action_item_count': (m['action_items'] is List) ? (m['action_items'] as List).length : 0,
        }).toList(),
      };
    } catch (e) {
      debugPrint('Direct Supabase daily report fallback error: $e');
    }

    return {
      'status': 'error',
      'date': targetDate,
      'message': 'Failed to compile daily report. Please check your connection.',
    };
  }
}
