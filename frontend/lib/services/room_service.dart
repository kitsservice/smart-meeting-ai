import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

class RoomService {
  static final RoomService _instance = RoomService._internal();
  factory RoomService() => _instance;
  RoomService._internal();

  static const String _completedRoomsKey = 'completed_rooms_cache';

  /// Check if a 6-digit room code is completed/ended.
  /// Returns 'completed', 'active', 'waiting', or null.
  Future<String?> checkRoomStatus(String roomCode) async {
    final cleanCode = roomCode.trim();
    if (cleanCode.length != 6) return null;

    // 1. Fast local cache check
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedList = prefs.getStringList(_completedRoomsKey) ?? [];
      if (cachedList.contains(cleanCode)) {
        return 'completed';
      }
    } catch (e) {
      debugPrint('Local room cache check error: $e');
    }

    // 2. Direct Supabase Query (Fast & Cloud Reliable across devices)
    try {
      final res = await Supabase.instance.client
          .from('meetings')
          .select('id, description, created_at')
          .ilike('description', '%[ROOM_CODE:$cleanCode]%')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        final desc = (res['description'] ?? '').toString();
        if (desc.contains('[STATUS:completed]')) {
          await _cacheCompletedRoom(cleanCode);
          return 'completed';
        } else if (desc.contains('[STATUS:active]')) {
          return 'active';
        } else if (desc.contains('[STATUS:waiting]')) {
          return 'waiting';
        }
      }
    } catch (e) {
      debugPrint('Direct Supabase room status check error: $e');
    }

    // 3. Fallback to Backend HTTP
    try {
      final baseUrl = ApiService.baseUrl;
      final url = Uri.parse('$baseUrl/meetings/room-status/$cleanCode');
      final resp = await http.get(url).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final status = data['status'];
        if (status == 'completed') {
          await _cacheCompletedRoom(cleanCode);
          return 'completed';
        } else if (status == 'active' || status == 'waiting') {
          return status;
        }
      }
    } catch (e) {
      debugPrint('Backend room check error: $e');
    }

    return null;
  }

  /// Mark a room as completed (e.g., host ended the meeting), preserving joined members
  Future<void> markRoomCompleted(
    String roomCode, {
    String? summaryInfo,
    List<Map<String, dynamic>>? participants,
  }) async {
    final cleanCode = roomCode.trim();
    if (cleanCode.isEmpty) return;

    // Cache locally immediately so the current device knows instantly
    await _cacheCompletedRoom(cleanCode);

    final currentUser = Supabase.instance.client.auth.currentUser;
    final userId = currentUser?.id ?? '00000000-0000-0000-0000-000000000000';

    // Update or Insert in Supabase preserving joined members
    try {
      final existing = await Supabase.instance.client
          .from('meetings')
          .select('id, description')
          .ilike('description', '%[ROOM_CODE:$cleanCode]%')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      String membersPart = '';
      if (participants != null && participants.isNotEmpty) {
        final List<Map<String, dynamic>> allMembers = List.from(participants);
        if (existing != null) {
          final oldDesc = (existing['description'] ?? '').toString();
          final existingMembers = parseMembersFromDescription(oldDesc);
          for (final em in existingMembers) {
            final euid = (em['user_id'] ?? '').toString();
            if (euid.isNotEmpty &&
                !allMembers.any((m) => (m['user_id'] ?? '').toString() == euid)) {
              allMembers.add(em);
            }
          }
        }
        membersPart = ' [MEMBERS:${jsonEncode(allMembers)}]';
      } else if (existing != null) {
        final oldDesc = (existing['description'] ?? '').toString();
        if (oldDesc.contains('[MEMBERS:')) {
          final match = RegExp(r'\[MEMBERS:\[.*?\]\]').firstMatch(oldDesc);
          if (match != null) {
            membersPart = ' ${match.group(0)}';
          }
        }
      }

      final descText =
          '[ROOM_CODE:$cleanCode] [STATUS:completed]$membersPart ${summaryInfo ?? ""}'.trim();

      if (existing != null) {
        await Supabase.instance.client
            .from('meetings')
            .update({'description': descText})
            .eq('id', existing['id']);
      } else {
        await Supabase.instance.client.from('meetings').insert({
          'title': 'Completed Meeting $cleanCode',
          'description': descText,
          'user_id': userId,
        });
      }
    } catch (e) {
      debugPrint('Direct Supabase markRoomCompleted error: $e');
    }

    // Also notify Backend if available
    try {
      final baseUrl = ApiService.baseUrl;
      final url = Uri.parse('$baseUrl/meetings/room-status');
      await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'room_code': cleanCode,
              'status': 'completed',
              'summary': summaryInfo ?? '',
              'user_id': userId,
              'members': participants,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Register a room code when created by the Host
  Future<void> markRoomCreated(
    String roomCode, {
    String? hostName,
    String? hostId,
  }) async {
    final cleanCode = roomCode.trim();
    if (cleanCode.isEmpty) return;

    final currentUser = Supabase.instance.client.auth.currentUser;
    final userId = hostId ?? (currentUser?.id ?? '00000000-0000-0000-0000-000000000000');
    final name = hostName ??
        (currentUser?.userMetadata?['full_name'] ??
            (currentUser?.email?.split('@')[0] ?? 'Host'));

    final membersJson = jsonEncode([
      {
        'user_id': userId,
        'name': name,
        'is_host': true,
        'joined_at': DateTime.now().toIso8601String(),
      }
    ]);

    final descText =
        '[ROOM_CODE:$cleanCode] [STATUS:waiting] [MEMBERS:$membersJson]';

    try {
      await Supabase.instance.client.from('meetings').insert({
        'title': 'Meeting $cleanCode',
        'description': descText,
        'user_id': userId,
      });
    } catch (e) {
      debugPrint('Direct Supabase markRoomCreated error: $e');
    }
  }

  /// Record when a participant joins a room code
  Future<void> recordParticipantJoin(
    String roomCode,
    String userId,
    String userName, {
    bool isHost = false,
  }) async {
    final cleanCode = roomCode.trim();
    if (cleanCode.isEmpty) return;

    try {
      final existing = await Supabase.instance.client
          .from('meetings')
          .select('id, description')
          .ilike('description', '%[ROOM_CODE:$cleanCode]%')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        String desc = (existing['description'] ?? '').toString();
        List<Map<String, dynamic>> members = parseMembersFromDescription(desc);

        final idx = members.indexWhere((m) => m['user_id'] == userId);
        if (idx != -1) {
          members[idx]['name'] = userName;
          if (isHost) members[idx]['is_host'] = true;
        } else {
          members.add({
            'user_id': userId,
            'name': userName,
            'is_host': isHost,
            'joined_at': DateTime.now().toIso8601String(),
          });
        }

        final membersJson = jsonEncode(members);
        String newDesc;
        if (desc.contains('[MEMBERS:')) {
          newDesc = desc.replaceAll(
            RegExp(r'\[MEMBERS:\[.*?\]\]'),
            '[MEMBERS:$membersJson]',
          );
        } else {
          newDesc = '$desc [MEMBERS:$membersJson]';
        }

        await Supabase.instance.client
            .from('meetings')
            .update({'description': newDesc})
            .eq('id', existing['id']);
      }
    } catch (e) {
      debugPrint('Direct Supabase recordParticipantJoin error: $e');
    }
  }

  /// Get the current list of participants stored in Supabase
  Future<List<Map<String, dynamic>>> getRoomParticipants(String roomCode) async {
    final cleanCode = roomCode.trim();
    if (cleanCode.isEmpty) return [];

    try {
      final existing = await Supabase.instance.client
          .from('meetings')
          .select('description')
          .ilike('description', '%[ROOM_CODE:$cleanCode]%')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        final desc = (existing['description'] ?? '').toString();
        return parseMembersFromDescription(desc);
      }
    } catch (e) {
      debugPrint('Direct Supabase getRoomParticipants error: $e');
    }
    return [];
  }

  static List<Map<String, dynamic>> parseMembersFromDescription(String desc) {
    if (!desc.contains('[MEMBERS:')) return [];
    try {
      final match = RegExp(r'\[MEMBERS:(\[.*?\])\]').firstMatch(desc);
      if (match != null && match.group(1) != null) {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(
            decoded.map((x) => Map<String, dynamic>.from(x as Map)),
          );
        }
      }
    } catch (e) {
      debugPrint('parseMembersFromDescription error: $e');
    }
    return [];
  }

  /// Mark room as active when host starts
  Future<void> markRoomActive(String roomCode) async {
    final cleanCode = roomCode.trim();
    if (cleanCode.isEmpty) return;

    try {
      final existing = await Supabase.instance.client
          .from('meetings')
          .select('id, description')
          .ilike('description', '%[ROOM_CODE:$cleanCode]%')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        final desc = (existing['description'] ?? '').toString();
        String newDesc;
        if (desc.contains('[STATUS:waiting]')) {
          newDesc = desc.replaceAll('[STATUS:waiting]', '[STATUS:active]');
        } else if (!desc.contains('[STATUS:active]')) {
          newDesc = '$desc [STATUS:active]';
        } else {
          newDesc = desc;
        }

        await Supabase.instance.client
            .from('meetings')
            .update({'description': newDesc})
            .eq('id', existing['id']);
      }
    } catch (e) {
      debugPrint('Direct Supabase markRoomActive error: $e');
    }
  }

  Future<void> _cacheCompletedRoom(String roomCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedList = prefs.getStringList(_completedRoomsKey) ?? [];
      if (!cachedList.contains(roomCode)) {
        cachedList.add(roomCode);
        await prefs.setStringList(_completedRoomsKey, cachedList);
      }
    } catch (e) {
      debugPrint('Failed to cache completed room: $e');
    }
  }
}
