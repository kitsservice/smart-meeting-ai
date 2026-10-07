import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class MeetingsListScreen extends StatefulWidget {
  const MeetingsListScreen({super.key});

  @override
  State<MeetingsListScreen> createState() => _MeetingsListScreenState();
}

class _MeetingsListScreenState extends State<MeetingsListScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _allMeetings = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isSemanticSearch = false;
  List<dynamic> _semanticResults = [];

  @override
  void initState() {
    super.initState();
    _refreshMeetings();
  }

  Future<void> _refreshMeetings() async {
    setState(() {
      _isLoading = true;
      _isSemanticSearch = false;
      _searchQuery = '';
      _semanticResults.clear();
    });
    final meetings = await _apiService.getMeetings();
    if (!mounted) return;
    setState(() {
      _allMeetings = meetings;
      _isLoading = false;
    });
  }

  Future<void> _performSemanticSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _isSemanticSearch = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _isSemanticSearch = true;
    });

    final results = await _apiService.searchSemanticMeetings(query);

    setState(() {
      _semanticResults = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase();

    // Normal local filtering
    final filteredMeetings = _allMeetings.where((meeting) {
      final title = (meeting['title'] ?? '').toString().toLowerCase();
      final summary = (meeting['summary'] ?? '').toString().toLowerCase();
      return title.contains(query) || summary.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('My Meetings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshMeetings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: AppTheme.dividerColor, width: 1.5),
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
                      color: AppTheme.primaryColor.withOpacity(0.1),
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
                    color: AppTheme.textSecondary.withOpacity(0.7),
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

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  )
                : _isSemanticSearch
                ? _buildSemanticList()
                : _buildNormalList(filteredMeetings),
          ),
        ],
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

        // Format date to DD/MM/YY
        String dateStr = 'Today';
        if (rawDate.isNotEmpty) {
          try {
            final parsedDate = DateTime.parse(rawDate);
            final day = parsedDate.day.toString().padLeft(2, '0');
            final month = parsedDate.month.toString().padLeft(2, '0');
            final year = (parsedDate.year % 100).toString().padLeft(2, '0');
            dateStr = '$day/$month/$year';
          } catch (_) {
            dateStr = rawDate.split('T').first.replaceAll('-', '/'); // Fallback
          }
        }

        // Calculate original meeting duration
        int durationMinutes = 0;
        if (meeting.containsKey('duration_seconds') &&
            meeting['duration_seconds'] != null) {
          durationMinutes = (meeting['duration_seconds'] as num).round() ~/ 60;
        } else if (meeting['transcript'] != null &&
            meeting['transcript'].toString().trim().isNotEmpty) {
          // Estimate original duration: Average speaking rate is ~130 words per minute
          final wordCount = meeting['transcript']
              .toString()
              .trim()
              .split(RegExp(r'\s+'))
              .length;
          durationMinutes = (wordCount / 130).ceil();
        }

        final durationText = durationMinutes > 0
            ? ' • $durationMinutes min'
            : '';

        return GestureDetector(
          onTap: () async {
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
            margin: const EdgeInsets.only(bottom: 12), // Reduced from 16
            padding: const EdgeInsets.all(16), // Reduced from 20
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.dividerColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10, // Reduced from 12
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10), // Reduced from 12
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: AppTheme.primaryColor,
                    size: 22, // Reduced from 24
                  ),
                ),
                const SizedBox(width: 14), // Reduced from 16
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16, // Reduced from 17
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4), // Reduced from 6
                      Text(
                        '$dateStr$durationText', // REAL original data
                        style: const TextStyle(
                          fontSize: 12, // Reduced from 13
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8), // Reduced from 12
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: AppTheme.accentColor,
                            size: 14,
                          ),
                          const SizedBox(width: 4), // Reduced from 6
                          Text(
                            'AI Summary Available',
                            style: TextStyle(
                              fontSize: 11, // Reduced from 12
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
