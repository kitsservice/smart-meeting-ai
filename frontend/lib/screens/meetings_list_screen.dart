import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/meetings_provider.dart';
import '../services/api_service.dart';
import '../services/offline_queue.dart';
import '../theme/app_theme.dart';

class MeetingsListScreen extends ConsumerStatefulWidget {
  const MeetingsListScreen({super.key});

  @override
  ConsumerState<MeetingsListScreen> createState() => _MeetingsListScreenState();
}

class _MeetingsListScreenState extends ConsumerState<MeetingsListScreen> {
  final ApiService _apiService = ApiService();
  bool _isRefreshing = false;
  String _searchQuery = '';
  bool _isSemanticSearch = false;
  List<dynamic> _semanticResults = [];
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMeetings();
    });
  }

  Future<void> _refreshMeetings() async {
    if (!mounted) return;
    setState(() {
      _isRefreshing = true;
      _isSemanticSearch = false;
      _searchQuery = '';
      _semanticResults.clear();
    });

    try {
      // Trigger sync for current user's queued audio
      OfflineQueueService().syncPendingUploads();
      await ref.read(meetingsProvider.notifier).fetchMeetings();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _performSemanticSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _isSemanticSearch = false);
      return;
    }

    setState(() {
      _isRefreshing = true;
      _isSemanticSearch = true;
    });

    final results = await _apiService.searchSemanticMeetings(query);

    if (mounted) {
      setState(() {
        _semanticResults = results;
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase();
    final meetingsAsync = ref.watch(meetingsProvider);
    final allMeetings = meetingsAsync.value ?? [];
    final displayedMeetings =
        _isSemanticSearch ? _semanticResults : allMeetings;

    // Normal local filtering with date chips
    final filteredMeetings = displayedMeetings.where((meeting) {
      final title = (meeting['title'] ?? '').toString().toLowerCase();
      final summary = (meeting['summary'] ?? '').toString().toLowerCase();
      final matchesQuery = title.contains(query) || summary.contains(query);
      if (!matchesQuery) return false;

      if (_selectedFilter == 'Today') {
        final rawDate = meeting['created_at']?.toString() ?? '';
        if (rawDate.isNotEmpty) {
          try {
            final date = DateTime.parse(rawDate).toLocal();
            final now = DateTime.now();
            return date.year == now.year &&
                date.month == now.month &&
                date.day == now.day;
          } catch (_) {
            return false;
          }
        }
        return false;
      } else if (_selectedFilter == 'This Week') {
        final rawDate = meeting['created_at']?.toString() ?? '';
        if (rawDate.isNotEmpty) {
          try {
            final date = DateTime.parse(rawDate).toLocal();
            final now = DateTime.now();
            final difference = now.difference(date).inDays;
            return difference >= 0 && difference <= 7;
          } catch (_) {
            return false;
          }
        }
        return false;
      }
      return true;
    }).toList();

    final isLoading =
        _isRefreshing || (meetingsAsync.isLoading && allMeetings.isEmpty);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('My Meetings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              HapticFeedback.lightImpact();
              _refreshMeetings();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                boxShadow: AppTheme.cardShadow(context),
                border: Border.all(
                  color: AppTheme.cardBorder(context),
                  width: 1.0,
                ),
              ),
              child: TextField(
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    if (value.isEmpty) _isSemanticSearch = false;
                  });
                },
                onSubmitted: _performSemanticSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.primaryColor,
                      size: 18,
                    ),
                  ),
                  hintText: 'Ask AI about your meetings...',
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.search_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          onPressed: () => _performSemanticSearch(_searchQuery),
                        )
                      : null,
                ),
              ),
            ),
          ),

          // Quick Filter Chips (All, Today, This Week)
          if (!_isSemanticSearch)
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
              child: Row(
                children: [
                  _buildFilterChip('All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Today'),
                  const SizedBox(width: 8),
                  _buildFilterChip('This Week'),
                ],
              ),
            ),

          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  )
                : _isSemanticSearch
                ? _buildSemanticList()
                : filteredMeetings.isEmpty
                ? RefreshIndicator(
                    onRefresh: _refreshMeetings,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.12,
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    query.isNotEmpty
                                        ? Icons.search_off_rounded
                                        : Icons.mic_none_rounded,
                                    size: 52,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  query.isNotEmpty
                                      ? 'No meetings match "$query"'
                                      : (_selectedFilter != 'All'
                                          ? 'No meetings for $_selectedFilter'
                                          : 'No meetings recorded yet'),
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    letterSpacing: -0.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  query.isNotEmpty
                                      ? 'Try searching with different keywords or clear your search query.'
                                      : 'Start recording your first meeting to get automatic AI transcripts, intelligent summaries, and action items.',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                if (query.isNotEmpty)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      setState(() {
                                        _searchQuery = '';
                                        _isSemanticSearch = false;
                                      });
                                    },
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 16),
                                    label: const Text('Clear Search'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primaryColor,
                                      side: const BorderSide(
                                          color: AppTheme.primaryColor),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                  )
                                else ...[
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pushNamed(
                                          context, '/active_meeting');
                                    },
                                    icon: const Icon(
                                      Icons.play_circle_fill_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Start New Meeting',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 14),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _refreshMeetings();
                                    },
                                    icon: const Icon(Icons.refresh_rounded,
                                        size: 16,
                                        color: AppTheme.textSecondary),
                                    label: const Text(
                                      'Refresh List',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refreshMeetings,
                    child: _buildNormalList(filteredMeetings),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedFilter = label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSemanticList() {
    if (_semanticResults.isEmpty) {
      return const Center(
        child: Text(
          'AI found no matching conversations.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _semanticResults.length,
      itemBuilder: (context, index) {
        final result = _semanticResults[index];
        final chunkText = result['chunk_text'] ?? '';
        final similarity = (result['similarity'] ?? 0.0) * 100;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: AppTheme.primaryColor,
            ), // Highlight AI results
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: AppTheme.primaryColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AI Match (${similarity.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '"...$chunkText..."',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      // We only have meeting_id, we need full meeting.
                      final meeting = await _apiService.getMeeting(
                        result['meeting_id'],
                      );
                      if (meeting != null && context.mounted) {
                        final res = await Navigator.pushNamed(
                          context,
                          '/meeting_details',
                          arguments: meeting,
                        );
                        if (res == true) {
                          _refreshMeetings();
                        }
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Go to Meeting'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNormalList(List<dynamic> filteredMeetings) {
    if (filteredMeetings.isEmpty) {
      return const Center(
        child: Text(
          'No meetings found.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: filteredMeetings.length,
      itemBuilder: (context, index) {
        final meeting = filteredMeetings[index];
        final title = meeting['title'] ?? 'Untitled Meeting';
        final rawDate = meeting['created_at'] ?? '';

        // Format date to DD/MM/YY hh:mm AM/PM
        String dateStr = 'Today';
        if (rawDate.isNotEmpty) {
          try {
            final parsedDate = DateTime.parse(rawDate).toLocal();
            final day = parsedDate.day.toString().padLeft(2, '0');
            final month = parsedDate.month.toString().padLeft(2, '0');
            final year = (parsedDate.year % 100).toString().padLeft(2, '0');

            int hourValue = parsedDate.hour;
            final ampm = hourValue >= 12 ? 'PM' : 'AM';
            if (hourValue == 0) hourValue = 12;
            if (hourValue > 12) hourValue -= 12;

            final hourStr = hourValue.toString().padLeft(2, '0');
            final minuteStr = parsedDate.minute.toString().padLeft(2, '0');
            dateStr = '$day/$month/$year $hourStr:$minuteStr $ampm';
          } catch (_) {
            dateStr = rawDate.split('T').first.replaceAll('-', '/'); // Fallback
          }
        }

        // Calculate original meeting duration efficiently without regex split allocations
        int durationMinutes = 0;
        if (meeting.containsKey('duration_seconds') &&
            meeting['duration_seconds'] != null) {
          durationMinutes = (meeting['duration_seconds'] as num).round() ~/ 60;
        } else if (meeting['transcript'] != null) {
          final transcriptStr = meeting['transcript'].toString();
          if (transcriptStr.trim().isNotEmpty) {
            final wordCount = _fastWordCount(transcriptStr);
            durationMinutes = (wordCount / 130).ceil();
          }
        }

        final durationText = durationMinutes > 0
            ? ' • $durationMinutes min'
            : '';

        final currentUserId =
            Supabase.instance.client.auth.currentUser?.id ?? '';
        final isHost = (meeting['user_id'] ?? '').toString() == currentUserId;

        return GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            final result = await Navigator.pushNamed(
              context,
              '/meeting_details',
              arguments: meeting,
            );
            if (result == true) {
              // The meeting was deleted, refresh the list!
              _refreshMeetings();
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: AppTheme.cardBorder(context),
                width: 1,
              ),
              boxShadow: AppTheme.cardShadow(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isHost
                        ? AppTheme.primaryColor.withValues(alpha: 0.08)
                        : const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isHost ? Icons.mic_rounded : Icons.groups_rounded,
                    color: isHost ? AppTheme.primaryColor : const Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dateStr$durationText',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!isHost)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.login_rounded,
                          color: Color(0xFF6366F1),
                          size: 11,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Joined',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: AppTheme.accentColor,
                          size: 12,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppTheme.textSecondary,
                  size: 14,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _fastWordCount(String text) {
    int words = 0;
    bool inWord = false;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) <= 32) {
        inWord = false;
      } else if (!inWord) {
        inWord = true;
        words++;
      }
    }
    return words;
  }
}
