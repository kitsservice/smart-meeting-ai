import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';

final meetingsProvider =
    StateNotifierProvider<MeetingsNotifier, AsyncValue<List<dynamic>>>((ref) {
      return MeetingsNotifier();
    });

class MeetingsNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  static const String _cacheKey = 'ares_cached_meetings_json_v1';
  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _inFlightFetch;

  MeetingsNotifier() : super(const AsyncValue.loading()) {
    _loadFromCacheAndFetch();
    _listenToAuthChanges();
  }

  /// Instantly load cached meetings (<20ms) then refresh from network
  Future<void> _loadFromCacheAndFetch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson);
        if (decoded is List && decoded.isNotEmpty) {
          state = AsyncValue.data(decoded);
          debugPrint('Loaded ${decoded.length} meetings from local cache.');
        }
      }
    } catch (e) {
      debugPrint('Error reading cached meetings: $e');
    }

    await fetchMeetings();
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        final event = data.event;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.userUpdated) {
          fetchMeetings();
        } else if (event == AuthChangeEvent.signedOut) {
          clear();
        }
      },
      onError: (err) {
        debugPrint('MeetingsNotifier auth stream error: $err');
      },
    );
  }

  Future<void> clear() async {
    state = const AsyncValue.data([]);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }

  Future<void> fetchMeetings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      state = const AsyncValue.data([]);
      return;
    }

    if (_inFlightFetch != null) {
      return _inFlightFetch!;
    }

    _inFlightFetch = _doFetchMeetings();
    try {
      await _inFlightFetch;
    } finally {
      _inFlightFetch = null;
    }
  }

  Future<void> _doFetchMeetings() async {
    // Retain cached data during fetch to avoid layout flicker
    state = const AsyncLoading<List<dynamic>>().copyWithPrevious(state);
    try {
      final meetings = await ApiService().getMeetings();
      state = AsyncValue.data(meetings);
      _saveToCache(meetings);
    } catch (e, st) {
      // If we already have cached data, preserve it gracefully on network drops
      if (state.hasValue && state.value!.isNotEmpty) {
        debugPrint('Network fetch failed, retaining cached meetings: $e');
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> _saveToCache(List<dynamic> meetings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(meetings));
    } catch (e) {
      debugPrint('Error saving meetings to cache: $e');
    }
  }

  Future<void> deleteMeeting(String id) async {
    try {
      final success = await ApiService().deleteMeeting(id);
      if (success) {
        if (state.hasValue) {
          final currentList = state.value!;
          final updated =
              currentList.where((m) => m['id'].toString() != id).toList();
          state = AsyncValue.data(updated);
          _saveToCache(updated);
        }
      }
    } catch (e) {
      debugPrint('Error deleting meeting: $e');
    }
  }

  void updateActionItem(String meetingId, String itemId, bool isCompleted) {
    if (!state.hasValue) return;
    final currentList = state.value!;
    final updatedList = currentList.map((m) {
      if (m['id'].toString() == meetingId && m['action_items'] is List) {
        final items = List<dynamic>.from(m['action_items']);
        final updatedItems = items.map((item) {
          if (item is Map && item['id']?.toString() == itemId) {
            final copy = Map<String, dynamic>.from(item);
            copy['is_completed'] = isCompleted;
            return copy;
          }
          return item;
        }).toList();
        final mCopy = Map<String, dynamic>.from(m);
        mCopy['action_items'] = updatedItems;
        return mCopy;
      }
      return m;
    }).toList();
    state = AsyncValue.data(updatedList);
    _saveToCache(updatedList);
  }

  void deleteActionItem(String meetingId, String itemId) {
    if (!state.hasValue) return;
    final currentList = state.value!;
    final updatedList = currentList.map((m) {
      if (m['id'].toString() == meetingId && m['action_items'] is List) {
        final items = List<dynamic>.from(m['action_items']);
        items.removeWhere(
          (item) => item is Map && item['id']?.toString() == itemId,
        );
        final mCopy = Map<String, dynamic>.from(m);
        mCopy['action_items'] = items;
        return mCopy;
      }
      return m;
    }).toList();
    state = AsyncValue.data(updatedList);
    _saveToCache(updatedList);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
