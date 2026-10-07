import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final meetingsProvider =
    StateNotifierProvider<MeetingsNotifier, AsyncValue<List<dynamic>>>((ref) {
      return MeetingsNotifier();
    });

class MeetingsNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  MeetingsNotifier() : super(const AsyncValue.loading()) {
    fetchMeetings();
  }

  Future<void> fetchMeetings() async {
    state = const AsyncValue.loading();
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
      print('Error deleting: $e');
    }
  }
}
