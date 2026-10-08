import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulators to connect to Windows localhost
  static String get baseUrl {
    return 'https://smart-meeting-ai-7qub.onrender.com/api/v1';
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final http.Client _client = http.Client(); // Persistent client

  Map<String, String> _getHeaders({bool isMultipart = false}) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final headers = <String, String>{};
    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<dynamic>> getMeetings() async {
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? '';
    final url = Uri.parse('$baseUrl/meetings/?user_id=$userId');
    try {
      final response = await _client.get(url, headers: _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        print('Failed to load meetings: ${response.body}');
      }
    } catch (e) {
      print('Error fetching meetings: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> getMeeting(String meetingId) async {
    final url = Uri.parse('$baseUrl/meetings/$meetingId');
    try {
      final response = await _client.get(url, headers: _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        print('Failed to load meeting details: ${response.body}');
      }
    } catch (e) {
      print('Error fetching meeting details: $e');
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
      print('Error deleting account: $e');
    }
    return false;
  }

  Future<bool> deleteMeeting(String meetingId) async {
    final url = Uri.parse('$baseUrl/meetings/$meetingId');
    try {
      final response = await _client.delete(url, headers: _getHeaders());
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      print('Error deleting meeting: $e');
    }
    return false;
  }

  Future<String?> createMeeting(String title, String description) async {
    final url = Uri.parse('$baseUrl/meetings/');
    final user = Supabase.instance.client.auth.currentUser;

    try {
      final response = await _client.post(
        url,
        headers: _getHeaders(),
        body: jsonEncode({
          'title': title,
          'description': description,
          'user_id': user?.id,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['id']; // Return the meeting ID for audio upload
      } else {
        print('Failed to save meeting: ${response.body}');
      }
    } catch (e) {
      print('Error calling backend: $e');
    }
    return null;
  }

  Future<void> processAudio(String meetingId, String filePath) async {
    final url = Uri.parse('$baseUrl/meetings/$meetingId/process-audio');

    try {
      var request = http.MultipartRequest('POST', url);
      request.headers.addAll(_getHeaders(isMultipart: true));

      // Attach the real audio file
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        print('Audio processed successfully!');
      } else {
        print('Failed to process audio: ${response.body}');
      }
    } catch (e) {
      print('Error processing audio: $e');
    }
  }

  Future<List<dynamic>> searchSemanticMeetings(String query) async {
    final url = Uri.parse(
      '$baseUrl/meetings/search/semantic?query=${Uri.encodeComponent(query)}',
    );
    try {
      final response = await _client.get(url, headers: _getHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] as List<dynamic>;
      } else {
        print('Failed to semantic search: ${response.body}');
      }
    } catch (e) {
      print('Error doing semantic search: $e');
    }
    return [];
  }

  Future<bool> enrollVoice(String filePath) async {
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? '';
    final fullName = user?.userMetadata?['full_name'] ?? '';
    if (userId.isEmpty) return false;

    final url = Uri.parse(
      '$baseUrl/users/enroll-voice?user_id=$userId&full_name=${Uri.encodeComponent(fullName)}',
    );

    try {
      var request = http.MultipartRequest('POST', url);
      request.headers.addAll(_getHeaders(isMultipart: true));

      // Attach the audio file
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        print('Voice enrolled successfully!');
        return true;
      } else {
        print('Failed to enroll voice: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error enrolling voice: $e');
      return false;
    }
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
      final response = await _client.patch(url, headers: _getHeaders());
      if (response.statusCode == 200) {
        return true;
      } else {
        print('Failed to update action item: ${response.body}');
      }
    } catch (e) {
      print('Error updating action item: $e');
    }
    return false;
  }
}
