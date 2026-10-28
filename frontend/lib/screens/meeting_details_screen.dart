import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/calendar_service.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/meetings_provider.dart';
import '../widgets/note_dialog_sheet.dart';
import '../widgets/shimmer_loading.dart';
import 'ask_ares_screen.dart';

class MeetingDetailsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;
  const MeetingDetailsScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<MeetingDetailsScreen> createState() =>
      _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends ConsumerState<MeetingDetailsScreen> {
  static final RegExp _sentenceSplitRegex = RegExp(r'(?<=\.)\s+');
  static final RegExp _timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})\]');
  static final RegExp _timestampStripRegex = RegExp(r'\[\d{1,2}:\d{2}\]\s*');
  Map<String, dynamic>? _fullMeeting;
  bool _isLoading = true;
  bool _isFullTextView = false;
  List<String> _meetingNotes = [];

  bool _hasFetched = false;
  String? _cachedTranscript;
  List<_TranscriptSegment> _cachedSegments = [];
  Timer? _pollingTimer;

  void _startPollingIfNeeded(String id) {
    _pollingTimer?.cancel();
    final clean = (_fullMeeting?['transcript'] ?? '').toString().trim();
    final isDone = clean.isNotEmpty &&
        clean != 'null' &&
        clean != 'NONE' &&
        clean != 'Loading transcript...' &&
        clean != 'No transcript available.' &&
        clean != 'No speech detected.' &&
        clean != 'Transcription could not be completed.';

    if (!isDone) {
      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }
        await _fetchFullDetails(id, background: true);
        final updated = (_fullMeeting?['transcript'] ?? '').toString().trim();
        if (updated.isNotEmpty &&
            updated != 'null' &&
            updated != 'NONE' &&
            updated != 'Loading transcript...' &&
            updated != 'No transcript available.') {
          timer.cancel();
          ref.read(meetingsProvider.notifier).fetchMeetings();
        }
      });
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  List<_TranscriptSegment> _getSegments(String transcript) {
    if (_cachedTranscript == transcript && _cachedSegments.isNotEmpty) {
      return _cachedSegments;
    }
    _cachedTranscript = transcript;
    _cachedSegments = _parseTranscriptSegments(transcript);
    return _cachedSegments;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasFetched && _fullMeeting == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['id'] != null) {
        _hasFetched = true;
        _fullMeeting = Map<String, dynamic>.from(args);
        final hasTranscript = _fullMeeting!['transcript'] != null &&
            _fullMeeting!['transcript'].toString().isNotEmpty;
        final hasSummary = _fullMeeting!['summary'] != null &&
            _fullMeeting!['summary'].toString().isNotEmpty;
        // Instant render: if meeting already has data, display immediately
        _isLoading = !hasTranscript && !hasSummary;
        _fetchFullDetails(args['id'].toString(), background: hasTranscript || hasSummary);
        _startPollingIfNeeded(args['id'].toString());
      } else if (args is String && args.isNotEmpty) {
        _hasFetched = true;
        _fetchFullDetails(args);
        _startPollingIfNeeded(args);
      }
    }
  }

  Future<void> _fetchFullDetails(String id, {bool background = false}) async {
    if (id.startsWith('demo_')) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    Map<String, dynamic>? details;
    try {
      details = await ApiService().getMeeting(id);
    } catch (e) {
      debugPrint('ApiService.getMeeting error: $e');
    }

    // If ApiService returned null or missing transcript, attempt direct Supabase fallback
    if (details == null || details['transcript'] == null) {
      try {
        final data = await Supabase.instance.client
            .from('meetings')
            .select('*')
            .eq('id', id)
            .maybeSingle();
        if (data != null) {
          details = Map<String, dynamic>.from(data);
        }
      } catch (e) {
        debugPrint('Direct fetch fallback error: $e');
      }
    }

    List<String> localNotes = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      localNotes = prefs.getStringList('meeting_notes_$id') ?? [];
    } catch (e) {
      debugPrint('SharedPreferences error: $e');
    }

    if (mounted) {
      setState(() {
        if (details != null) {
          _fullMeeting = details;
        }
        _meetingNotes = localNotes;
        final t = (_fullMeeting?['transcript'] ?? '').toString().trim();
        final hasTranscript = t.isNotEmpty &&
            t != 'null' &&
            t != 'NONE' &&
            t != 'Loading transcript...' &&
            t != 'No transcript available.';
        final hasSummary = (_fullMeeting?['summary'] ?? '').toString().trim().isNotEmpty;
        _isLoading = !hasTranscript && !hasSummary;
      });
    }
  }

  String _getMeetingId() {
    if (_fullMeeting != null && _fullMeeting!['id'] != null) {
      return _fullMeeting!['id'].toString();
    }
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (rawArgs is Map && rawArgs['id'] != null) {
      return rawArgs['id'].toString();
    } else if (rawArgs is String && rawArgs.isNotEmpty) {
      return rawArgs;
    }
    return '';
  }

  Future<void> _saveNote(String note) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return;
    final id = _getMeetingId();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _meetingNotes.insert(0, trimmed);
    });

    await prefs.setStringList('meeting_notes_$id', _meetingNotes);
  }



  Widget _buildEmptyTranscriptWidget({
    required bool isNoSpeech,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.cardBorder(context),
                  width: 1,
                ),
                boxShadow: AppTheme.cardShadow(context),
              ),
              child: Icon(
                isNoSpeech
                    ? Icons.mic_off_rounded
                    : Icons.speaker_notes_off_rounded,
                size: 40,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isNoSpeech
                  ? 'No speech detected in this recording'
                  : 'No transcription available yet.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppTheme.cardBorder(context),
          width: 1.0,
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isFullTextView = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: !_isFullTextView
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Live',
                    style: TextStyle(
                      color: !_isFullTextView
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isFullTextView = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _isFullTextView
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Full Text',
                    style: TextStyle(
                      color: _isFullTextView
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullTextView(String transcript, String? meetingId) {
    final clean = transcript.trim();
    final bool isNoSpeech = clean == 'No speech detected.';
    final bool isStillLoading = clean == 'Loading transcript...' || (_isLoading && clean.isEmpty);

    if (isStillLoading) {
      return const TranscriptSkeleton();
    }

    if (clean.isEmpty ||
        clean == 'NONE' ||
        clean == 'null' ||
        clean == 'No transcript available.' ||
        isNoSpeech) {
      return _buildEmptyTranscriptWidget(
        isNoSpeech: isNoSpeech,
      );
    }

    final segments = _getSegments(transcript);
    final spans = <InlineSpan>[];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.timeString != null) {
        spans.add(
          TextSpan(
            text: '[${seg.timeString}] ',
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: '${seg.speaker}: ',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: seg.speakerColor,
          ),
        ),
      );
      spans.add(
        TextSpan(
          text: i < segments.length - 1 ? '${seg.text}\n\n' : seg.text,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: AppTheme.cardBorder(context),
            width: 1,
          ),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: AppTheme.textPrimary,
              letterSpacing: 0.2,
            ),
            children: spans,
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(_TranscriptSegment item, int index) {
    final isYou = item.speaker.toLowerCase().trim() == 'you' ||
        item.speaker.toLowerCase().contains('host');

    return Padding(
      padding: EdgeInsets.only(
        bottom: item.isNewSpeaker ? 6.0 : 12.0,
        top: item.isNewSpeaker && index != 0 ? 18.0 : 0.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speaker Avatar
          SizedBox(
            width: 44,
            child: item.isNewSpeaker
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.speakerColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: item.speakerColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: isYou
                          ? Icon(
                              Icons.person_rounded,
                              size: 18,
                              color: item.speakerColor,
                            )
                          : Text(
                              item.speaker.isNotEmpty
                                  ? item.speaker[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: item.speakerColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),

          // Message content + Speaker badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isNewSpeaker)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Speaker pill badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: item.speakerColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: item.speakerColor.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isYou
                                    ? Icons.mic_rounded
                                    : Icons.record_voice_over_rounded,
                                size: 12,
                                color: item.speakerColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                item.speaker,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: item.speakerColor,
                                  fontSize: 12.5,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.timeString != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.cardBorder(context),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 3.5),
                                Text(
                                  item.timeString!,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                // Speech Bubble Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(
                        item.isNewSpeaker ? 4 : AppTheme.radiusCard,
                      ),
                      topRight: const Radius.circular(AppTheme.radiusCard),
                      bottomLeft: const Radius.circular(AppTheme.radiusCard),
                      bottomRight: const Radius.circular(AppTheme.radiusCard),
                    ),
                    border: Border.all(
                      color: AppTheme.cardBorder(context),
                      width: 1,
                    ),
                    boxShadow: AppTheme.cardShadow(context),
                  ),
                  child: SelectableText(
                    item.text,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: AppTheme.textPrimary,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptionTab(String transcript, String? meetingId) {
    final clean = transcript.trim();
    final bool isNoSpeech = clean == 'No speech detected.';
    final bool isStillLoading = clean == 'Loading transcript...' || (_isLoading && clean.isEmpty);
    final bool isEmpty = clean.isEmpty ||
        clean == 'NONE' ||
        clean == 'null' ||
        clean == 'No transcript available.' ||
        isNoSpeech;

    if (isStillLoading) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildTopToggle(),
          ),
          const TranscriptSkeleton(),
        ],
      );
    }

    if (isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildTopToggle(),
          ),
          _buildEmptyTranscriptWidget(
            isNoSpeech: isNoSpeech,
          ),
        ],
      );
    }

    if (_isFullTextView) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildTopToggle(),
          ),
          _buildFullTextView(transcript, meetingId),
        ],
      );
    }

    final segments = _getSegments(transcript);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      itemCount: segments.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 12.0, 8.0, 16.0),
            child: _buildTopToggle(),
          );
        }
        return _buildChatBubble(segments[index - 1], index - 1);
      },
    );
  }

  void _confirmDeleteMeetingNote(int index) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.dangerColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'Delete Note?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this note from the meeting? This action cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final id = _getMeetingId();
              final prefs = await SharedPreferences.getInstance();
              setState(() {
                _meetingNotes.removeAt(index);
              });
              if (id.isNotEmpty) {
                await prefs.setStringList('meeting_notes_$id', _meetingNotes);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Note deleted'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () => _showNoteDialog(),
              icon: const Icon(Icons.add_rounded, size: 22, color: Colors.white),
              label: const Text(
                'Add Meeting Note',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _meetingNotes.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.note_alt_outlined,
                              size: 44,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No Notes Yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Capture important thoughts and takeaways from this meeting.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => _showNoteDialog(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add First Note'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: _meetingNotes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final note = _meetingNotes[index];
                    final lines = note
                        .split('\n')
                        .map((l) => l.trim())
                        .where((l) => l.isNotEmpty)
                        .toList();
                    final title =
                        lines.isNotEmpty ? lines.first : 'Meeting Note';
                    final body =
                        lines.length > 1 ? lines.skip(1).join('\n') : '';
                    final wordCount = note
                        .trim()
                        .split(RegExp(r'\s+'))
                        .where((w) => w.isNotEmpty)
                        .length;

                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(
                          color: AppTheme.cardBorder(context),
                          width: 1.0,
                        ),
                        boxShadow: AppTheme.cardShadow(context),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showNoteDialog(index: index),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(
                                            Icons.push_pin_rounded,
                                            color: AppTheme.primaryColor,
                                            size: 13,
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            'Meeting Note',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryColor,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    // Copy action
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Copy Note',
                                      icon: Icon(
                                        Icons.copy_rounded,
                                        size: 17,
                                        color: AppTheme.textSecondary.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        Clipboard.setData(
                                          ClipboardData(text: note),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Note copied to clipboard!',
                                            ),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 14),
                                    // Edit action
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Edit Note',
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: AppTheme.textSecondary.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _showNoteDialog(index: index),
                                    ),
                                    const SizedBox(width: 14),
                                    // Delete action
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Delete Note',
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: AppTheme.dangerColor.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _confirmDeleteMeetingNote(index),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                    height: 1.35,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.short_text_rounded,
                                      size: 15,
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$wordCount ${wordCount == 1 ? 'word' : 'words'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textSecondary
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        Text(
                                          'Edit',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryColor
                                                .withValues(alpha: 0.9),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          size: 16,
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.9),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showNoteDialog({int? index}) async {
    HapticFeedback.lightImpact();
    final String currentText = (index != null && index >= 0 && index < _meetingNotes.length)
        ? _meetingNotes[index]
        : '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => NoteDialogSheet(
        initialText: currentText,
        isEditing: index != null,
        title: index != null ? 'Edit Meeting Note' : 'New Meeting Note',
        subtitle: index != null
            ? 'Update your captured meeting note'
            : 'First line will be used as note title',
        hintText: 'Type your meeting note here...',
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      if (index != null && index >= 0 && index < _meetingNotes.length) {
        final id = _getMeetingId();
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _meetingNotes[index] = result;
        });
        if (id.isNotEmpty) {
          await prefs.setStringList('meeting_notes_$id', _meetingNotes);
        }
      } else {
        await _saveNote(result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    final Map<String, dynamic> initialMeeting = (rawArgs is Map)
        ? Map<String, dynamic>.from(rawArgs)
        : (rawArgs is String ? {'id': rawArgs} : <String, dynamic>{});

    final meeting = _fullMeeting ?? initialMeeting;

    final meetingId = meeting['id'];
    final title = meeting['title'] ?? 'Meeting';
    final dateStr = (meeting['created_at'] ?? '').split('T').first;

    String summary =
        meeting['summary'] ??
        (initialMeeting['summary'] ?? 'This feature is coming soon.');

    if (summary.trim().isEmpty ||
        summary.toLowerCase() == 'none' ||
        summary == 'null' ||
        summary == 'Summary is being generated...' ||
        summary.toLowerCase().contains('failed to generate summary') ||
        summary.toLowerCase().contains('404 not_found')) {
      summary = 'This feature is coming soon.';
    }
    final rawTranscript =
        meeting['transcript'] ?? initialMeeting['transcript'];
    final transcript = (rawTranscript != null &&
            rawTranscript.toString().trim().isNotEmpty &&
            rawTranscript.toString().trim() != 'null' &&
            rawTranscript.toString().trim() != 'NONE')
        ? rawTranscript.toString()
        : (_isLoading ? 'Loading transcript...' : 'No transcript available.');

    List<dynamic> actionItems = [];
    if (meeting['action_items'] != null && meeting['action_items'] is List) {
      actionItems = meeting['action_items'];
    }

    final int tabIndex = (widget.initialTabIndex != 0)
        ? widget.initialTabIndex
        : (initialMeeting['initial_tab_index'] as int? ??
            initialMeeting['initialTabIndex'] as int? ??
            0);

    return DefaultTabController(
      length: 3,
      initialIndex: tabIndex.clamp(0, 2),
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.smart_toy_rounded,
                color: AppTheme.primaryColor,
              ),
              tooltip: 'Ask Ares about this meeting',
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AskAresScreen(
                      meetingId: meetingId,
                      meetingTitle: title,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.copy_rounded,
                color: AppTheme.primaryColor,
              ),
              onPressed: () {
                final shareText =
                    "Meeting: $title\nDate: $dateStr\n\nSummary:\n$summary\n\nTranscript:\n$transcript";
                Clipboard.setData(ClipboardData(text: shareText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Meeting details copied to clipboard!'),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.share_rounded,
                color: AppTheme.primaryColor,
              ),
              onPressed: () {
                final shareText =
                    "Meeting: $title\nDate: $dateStr\n\nSummary:\n$summary\n\nTranscript:\n$transcript";
                SharePlus.instance.share(
                  ShareParams(text: shareText, subject: 'Meeting Details: $title'),
                );
              },
            ),
            if (meetingId != null)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppTheme.dangerColor,
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppTheme.surfaceColor,
                      title: const Text(
                        'Delete Meeting',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                      content: const Text(
                        'Are you sure you want to delete this meeting?',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: AppTheme.dangerColor),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    final success = await ApiService().deleteMeeting(
                      meetingId.toString(),
                    );
                    if (success) {
                      ref.read(meetingsProvider.notifier).fetchMeetings();
                      if (context.mounted) {
                        Navigator.pop(context, true);
                      }
                    }
                  }
                },
              ),
          ],
          bottom: TabBar(
            onTap: (_) => HapticFeedback.selectionClick(),
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryColor,
            tabs: const [
              Tab(text: 'Transcript'),
              Tab(text: 'Notes'),
              Tab(text: 'AI Summary'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Transcription Tab (Virtualized Lazy Loading)
            _buildTranscriptionTab(transcript, meetingId?.toString()),

            // Notes Tab
            _buildNotesTab(),

            // AI Summary Tab
            SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.summarize,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Meeting Summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (actionItems.isNotEmpty) ...[
                    const Text(
                      'Action Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...actionItems.map(
                      (item) {
                        final String itemText = item is Map
                            ? (item['task']?.toString() ?? item.toString())
                            : item.toString();
                        final String? assignee = item is Map ? item['assignee']?.toString() : null;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          itemText,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                            height: 1.3,
                                          ),
                                        ),
                                        if (assignee != null && assignee.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Assignee: $assignee',
                                              style: const TextStyle(
                                                color: AppTheme.primaryColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      final now = DateTime.now();
                                      final pickedDate = await showDatePicker(
                                        context: context,
                                        initialDate: now.add(const Duration(days: 1)),
                                        firstDate: now,
                                        lastDate: now.add(const Duration(days: 365)),
                                      );
                                      if (pickedDate == null || !context.mounted) return;

                                      final pickedTime = await showTimePicker(
                                        context: context,
                                        initialTime: const TimeOfDay(hour: 9, minute: 0),
                                      );
                                      if (pickedTime == null || !context.mounted) return;

                                      final reminderTime = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      );

                                      if (reminderTime.isBefore(DateTime.now())) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Please select a future time.')),
                                          );
                                        }
                                        return;
                                      }

                                      await LocalNotificationService().scheduleActionItemReminder(
                                        taskTitle: itemText,
                                        reminderTime: reminderTime,
                                        meetingTitle: title,
                                      );

                                      if (context.mounted) {
                                        final timeLabel = pickedTime.format(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Reminder set for ${pickedDate.day}/${pickedDate.month} at $timeLabel'),
                                            backgroundColor: AppTheme.primaryColor,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.notifications_active_outlined, size: 14),
                                    label: const Text('Remind Me', style: TextStyle(fontSize: 11)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.primaryColor,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final now = DateTime.now();
                                      final pickedDate = await showDatePicker(
                                        context: context,
                                        initialDate: now.add(const Duration(days: 1)),
                                        firstDate: now,
                                        lastDate: now.add(const Duration(days: 365)),
                                      );
                                      if (pickedDate == null || !context.mounted) return;

                                      final pickedTime = await showTimePicker(
                                        context: context,
                                        initialTime: const TimeOfDay(hour: 10, minute: 0),
                                      );
                                      if (pickedTime == null || !context.mounted) return;

                                      final startDateTime = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      );

                                      final success = await CalendarService().addToDeviceCalendar(
                                        title: 'Action Item: $itemText',
                                        startTime: startDateTime,
                                        description: 'Meeting: $title\nAssignee: ${assignee ?? "Unassigned"}',
                                      );

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              success
                                                  ? 'Added to Device Calendar!'
                                                  : 'Calendar permission denied.',
                                            ),
                                            backgroundColor: success ? AppTheme.primaryColor : AppTheme.dangerColor,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_today_outlined, size: 14),
                                    label: const Text('Add to Calendar', style: TextStyle(fontSize: 11)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.accentColor,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_TranscriptSegment> _parseTranscriptSegments(String transcript) {
    final List<String> rawLines = transcript.split('\n');
    final List<String> processedLines = [];

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > 120 &&
          !trimmed.substring(0, trimmed.length > 30 ? 30 : trimmed.length).contains(':')) {
        final sentences = trimmed.split(_sentenceSplitRegex);
        for (final s in sentences) {
          final sTrim = s.trim();
          if (sTrim.isNotEmpty) processedLines.add(sTrim);
        }
      } else {
        processedLines.add(trimmed);
      }
    }

    final List<_TranscriptSegment> segments = [];
    String currentSpeaker = "Speaker 1";
    Color currentSpeakerColor = AppTheme.primaryColor;

    for (int i = 0; i < processedLines.length; i++) {
      final line = processedLines[i];
      Duration? segTimestamp;
      String? segTimeString;

      // Extract [MM:SS] or [HH:MM:SS] timestamp if present
      final timestampMatch = _timestampRegex.firstMatch(line);
      if (timestampMatch != null) {
        final minutes = int.tryParse(timestampMatch.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(timestampMatch.group(2) ?? '0') ?? 0;
        segTimestamp = Duration(minutes: minutes, seconds: seconds);
        segTimeString =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      }

      // Clean line without the timestamp tag
      final cleanLine =
          line.replaceAll(_timestampStripRegex, '').trim();

      String text = cleanLine;
      bool isNewSpeaker = false;

      final colonIndex = cleanLine.indexOf(':');
      if (colonIndex != -1 && colonIndex < 50) {
        final potentialSpeaker = cleanLine
            .substring(0, colonIndex)
            .trim()
            .replaceAll('[', '')
            .replaceAll(']', '');
        if (potentialSpeaker != currentSpeaker || i == 0) {
          currentSpeaker = potentialSpeaker;
          isNewSpeaker = true;

          final lower = currentSpeaker.toLowerCase();
          if (lower == 'you' || lower.contains('host')) {
            currentSpeakerColor = AppTheme.primaryColor;
          } else {
            const palette = [
              AppTheme.accentColor,
              Colors.teal,
              Colors.deepOrange,
              Colors.purple,
              Colors.indigo,
              Colors.amber,
              Colors.pink,
              Colors.cyan,
            ];
            final hash = currentSpeaker.hashCode.abs();
            currentSpeakerColor = palette[hash % palette.length];
          }
        }
        text = cleanLine.substring(colonIndex + 1).trim();
      } else if (i == 0) {
        isNewSpeaker = true;
      }

      segments.add(
        _TranscriptSegment(
          speaker: currentSpeaker,
          text: text,
          isNewSpeaker: isNewSpeaker,
          speakerColor: currentSpeakerColor,
          timestamp: segTimestamp,
          timeString: segTimeString,
        ),
      );
    }

    return segments;
  }
}

class _TranscriptSegment {
  final String speaker;
  final String text;
  final bool isNewSpeaker;
  final Color speakerColor;
  final Duration? timestamp;
  final String? timeString;

  const _TranscriptSegment({
    required this.speaker,
    required this.text,
    required this.isNewSpeaker,
    required this.speakerColor,
    this.timestamp,
    this.timeString,
  });
}

