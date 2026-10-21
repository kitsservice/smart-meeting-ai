import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';

final meetingsProvider =
    StateNotifierProvider<MeetingsNotifier, AsyncValue<List<dynamic>>>((ref) {
      return MeetingsNotifier();
    });

class MeetingsNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _inFlightFetch;

  MeetingsNotifier() : super(const AsyncValue.loading()) {
    fetchMeetings();
    _listenToAuthChanges();
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

  void clear() {
    state = const AsyncValue.data([]);
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
    state = const AsyncLoading<List<dynamic>>().copyWithPrevious(state);
    try {
      final meetings = await ApiService().getMeetings();
      state = AsyncValue.data(meetings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteMeeting(String id) async {
    try {
      final success = await ApiService().deleteMeeting(id);
      if (success) {
        if (state.hasValue) {
          final currentList = state.value!;
          state = AsyncValue.data(
            currentList.where((m) => m['id'].toString() != id).toList(),
          );
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
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
