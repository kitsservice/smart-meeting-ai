import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

class MeetingDetailsScreen extends StatefulWidget {
  final int initialTabIndex;
  const MeetingDetailsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<MeetingDetailsScreen> createState() => _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends State<MeetingDetailsScreen> {
  Map<String, dynamic>? _fullMeeting;
  bool _isLoading = true;
  List<String> _meetingNotes = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fullMeeting == null) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is Map<String, dynamic>) {
        _fetchFullDetails(args['id'].toString());
      }
    }
  }

  Future<void> _fetchFullDetails(String id) async {
    final details = await ApiService().getMeeting(id);
    final prefs = await SharedPreferences.getInstance();
    final localNotes = prefs.getStringList('meeting_notes_$id') ?? [];

    if (mounted) {
      setState(() {
        _fullMeeting = details;
        _meetingNotes = localNotes;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveNote(String note) async {
    if (note.trim().isEmpty || _fullMeeting == null) return;
    final id = _fullMeeting!['id'].toString();
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _meetingNotes.insert(0, note.trim());
    });

    await prefs.setStringList('meeting_notes_$id', _meetingNotes);
  }

  Widget _buildTranscriptChat(String transcript) {
    if (transcript.isEmpty || transcript == 'NONE' || transcript == 'null') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  shape: BoxShape.rectangle,
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                ),
                child: Icon(Icons.speaker_notes_off_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.5)),
              ),
              const SizedBox(height: 16),
              const Text(
                'No transcription available yet.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    List<String> rawLines = transcript.split('\n');
    List<String> processedLines = [];
    
    for (String line in rawLines) {
      if (line.trim().isEmpty) continue;
      if (line.length > 120 && !line.substring(30).contains(':')) {
        List<String> sentences = line.split(RegExp(r'(?<=\.)\s+'));
        processedLines.addAll(sentences);
      } else {
        processedLines.add(line);
      }
    }

    processedLines = processedLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String currentSpeaker = "Unknown";
    Color currentSpeakerColor = AppTheme.primaryColor;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      itemCount: processedLines.length,
      itemBuilder: (context, index) {
        final line = processedLines[index];
        String text = line;
        
        bool isNewSpeaker = false;
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1 && colonIndex < 30) {
          final potentialSpeaker = line.substring(0, colonIndex).trim().replaceAll('[', '').replaceAll(']', '');
          if (potentialSpeaker != currentSpeaker) {
            currentSpeaker = potentialSpeaker;
            isNewSpeaker = true;
            
            if (currentSpeaker.contains('1') || currentSpeaker.toLowerCase() == 'you') {
              currentSpeakerColor = AppTheme.primaryColor;
            } else if (currentSpeaker.contains('2')) {
              currentSpeakerColor = AppTheme.accentColor;
            } else {
              currentSpeakerColor = Colors.teal;
            }
          }
          text = line.substring(colonIndex + 1).trim();
        } else if (index == 0) {
          currentSpeaker = "Speaker 1";
          isNewSpeaker = true;
        }

        String time = '00:';

        return Padding(
          padding: EdgeInsets.only(bottom: isNewSpeaker ? 4.0 : 16.0, top: isNewSpeaker && index != 0 ? 24.0 : 0.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: isNewSpeaker ? Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: currentSpeakerColor.withOpacity(0.12),
                    shape: BoxShape.rectangle,
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(color: currentSpeakerColor.withOpacity(0.2), width: 1),
                  ),
                  child: Center(
                    child: Text(
                      currentSpeaker.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: currentSpeakerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ) : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNewSpeaker)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0, top: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              currentSpeaker,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: currentSpeakerColor,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              time,
                              style: TextStyle(
                                color: AppTheme.textSecondary.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: EdgeInsets.only(
                        top: isNewSpeaker ? 2.0 : 0.0,
                        bottom: 0.0,
                        right: 12.0,
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
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
      },
    );
  }

  Widget _buildNotesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton.icon(
            onPressed: _showAddNoteDialog,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text(
              'Add New Note',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Expanded(
          child: _meetingNotes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit_document,
                          size: 48,
                          color: AppTheme.primaryColor.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                        'Capture important thoughts and\ntakeaways from this meeting.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 48), // push up slightly
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _meetingNotes.length,
                  itemBuilder: (context, index) {
                    final note = _meetingNotes[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.dividerColor,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.push_pin_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Meeting Note',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                borderRadius: BorderRadius.circular(50),
                                onTap: () async {
                                  final prefs = await SharedPreferences.getInstance();
                                  final id = _fullMeeting!['id'].toString();
                                  setState(() {
                                    _meetingNotes.removeAt(index);
                                  });
                                  await prefs.setStringList(
                                    'meeting_notes_$id',
                                    _meetingNotes,
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppTheme.dangerColor,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            note,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppTheme.textPrimary,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showAddNoteDialog() {
    String tempNote = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 32,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Note',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.dividerColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  autofocus: true,
                  maxLines: 5,
                  onChanged: (val) => tempNote = val,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Jot down an important point...',
                    hintStyle: TextStyle(
                      color: AppTheme.textSecondary.withOpacity(0.6),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (tempNote.trim().isNotEmpty) {
                      _saveNote(tempNote);
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save Note',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> initialMeeting =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    final meeting = _fullMeeting ?? initialMeeting;

    final meetingId = meeting['id'];
    final title = meeting['title'] ?? 'Meeting';
    final dateStr = (meeting['created_at'] ?? '').split('T').first;

    final summary =
        meeting['summary'] ??
        (initialMeeting['summary'] ?? 'Summary is being generated...');
    final transcript = _isLoading
        ? 'Loading transcript...'
        : (meeting['transcript'] ?? 'No transcript available.');

    List<dynamic> actionItems = [];
    if (meeting['action_items'] != null && meeting['action_items'] is List) {
      actionItems = meeting['action_items'];
    }

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTabIndex,
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
                Share.share(shareText, subject: 'Meeting Details: $title');
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
                    if (success && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  }
                },
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryColor,
            tabs: [
              Tab(text: 'AI Summary'),
              Tab(text: 'Transcript'),
              Tab(text: 'Notes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
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
                          color: AppTheme.primaryColor.withOpacity(0.1),
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
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.toString(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppTheme.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Transcription Tab
            ListView(
              children: [
                // Top Toggle
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: const Border(
                                bottom: BorderSide(
                                  color: AppTheme.primaryColor,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Live',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: const Center(
                              child: Text(
                                'Full Text',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Chat List
                _buildTranscriptChat(transcript),
              ],
            ),

            // Notes Tab
            _buildNotesTab(),
          ],
        ),
      ),
    );
  }
}
