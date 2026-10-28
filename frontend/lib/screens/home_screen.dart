import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'action_items_screen.dart';
import 'meetings_list_screen.dart';
import 'ask_ares_screen.dart';
import 'schedule_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/meetings_provider.dart';
import '../providers/notifications_provider.dart';
import '../services/recording_service.dart';
import '../widgets/note_dialog_sheet.dart';
import '../services/rating_prompt_service.dart';
import '../widgets/home_meeting_sheets.dart';
import '../utils/responsive.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  final Set<int> _activatedTabs = {0};

  void _switchTab(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _activatedTabs.add(index);
      _currentIndex = index;
    });
  }

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  List<String> _manualNotes = [];
  String _noteSearchQuery = '';
  final TextEditingController _noteSearchController = TextEditingController();

  List<dynamic>? _lastCalculatedMeetings;
  int _cachedSummaryCount = 0;
  int _cachedPendingTasksCount = 0;

  void _updateMeetingStats(List<dynamic>? meetings) {
    if (identical(_lastCalculatedMeetings, meetings)) return;
    _lastCalculatedMeetings = meetings;
    int sCount = 0;
    int pCount = 0;
    if (meetings != null) {
      for (var m in meetings) {
        if (m['summary'] != null && m['summary'].toString().trim().isNotEmpty) {
          sCount++;
        }
        final items = m['action_items'];
        if (items is List) {
          for (var item in items) {
            if (item is Map && item['is_completed'] == false) {
              pCount++;
            }
          }
        }
      }
    }
    _cachedSummaryCount = sCount;
    _cachedPendingTasksCount = pCount;
  }

  String get _notesKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    return 'manual_notes_$userId';
  }

  @override
  void initState() {
    super.initState();
    _loadNotes();

    // Ensure meetings are fetched fresh for the currently active user
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(meetingsProvider.notifier).fetchMeetings();
      }
    });

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _slideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0.15, 0)).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeInOut),
        );
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _manualNotes = prefs.getStringList(_notesKey) ?? [];
    });
  }

  Future<void> _addNote(String note) async {
    if (note.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _manualNotes.insert(0, note.trim());
    });
    await prefs.setStringList(_notesKey, _manualNotes);
  }

  Future<void> _updateNote(int index, String note) async {
    if (note.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _manualNotes[index] = note.trim();
    });
    await prefs.setStringList(_notesKey, _manualNotes);
  }

  Future<void> _deleteNote(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _manualNotes.removeAt(index);
    });
    await prefs.setStringList(_notesKey, _manualNotes);
  }

  @override
  void dispose() {
    _noteSearchController.dispose();
    _slideController.dispose();
    super.dispose();
  }
  Future<void> _showNewMeetingSetup({
    String title = 'Create Meeting Room',
    String subtitle = 'Give the room a title before generating the join code.',
    String buttonText = 'Create Room',
  }) async {
    await HomeMeetingSheets.showNewMeetingSetup(
      context,
      title: title,
      subtitle: subtitle,
      buttonText: buttonText,
      onMeetingCreated: (meetingTitle) async {
        final res = await Navigator.pushNamed(
          context,
          '/active_meeting',
          arguments: {'title': meetingTitle},
        );
        if (mounted) {
          ref.read(meetingsProvider.notifier).fetchMeetings();
          if (res is Map && res['completed'] == true) {
            RatingPromptService.checkAndPrompt(context);
          }
        }
      },
    );
  }

  Future<void> _showJoinMeetingSetup() async {
    await HomeMeetingSheets.showJoinMeetingSetup(
      context,
      onJoinSuccess: (cleanCode) async {
        await Navigator.pushNamed(
          context,
          '/active_meeting',
          arguments: {
            'title': 'Joined Meeting: ',
            'is_participant': true,
            'room_code': cleanCode,
          },
        );
        if (mounted) {
          ref.read(meetingsProvider.notifier).fetchMeetings();
        }
      },
    );
  }


  String _capitalizeName(String name) {
    if (name.isEmpty) return '';
    return name
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good Morning,';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon,';
    } else if (hour >= 17 && hour < 21) {
      return 'Good Evening,';
    } else {
      return 'Good Night,';
    }
  }

  Widget _buildHomeTab() {
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name'] ?? 'KITS User';

    // RIVERPOD STATE INJECTION (Memoized stats calculation)
    final meetingsState = ref.watch(meetingsProvider);
    final meetingsList = meetingsState.value;
    final meetingCount = meetingsList?.length ?? 0;
    _updateMeetingStats(meetingsList);
    final summaryCount = _cachedSummaryCount;
    final pendingTasksCount = _cachedPendingTasksCount;

    final hasUnread = ref.watch(notificationsProvider.notifier).hasUnread;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await ref.read(meetingsProvider.notifier).fetchMeetings();
          await _loadNotes();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: ResponsiveContentWrapper(
            maxWidth: Responsive.maxContentWidth,
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 16.0,
            ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:
                [
                      // 1. Premium App Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2563EB).withValues(
                                          alpha: 0.15,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                    image: const DecorationImage(
                                      image: AssetImage(
                                        'assets/icon/app_icon.jpg',
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Smart Meeting',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.textPrimary,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      Text(
                                        'AI-Powered Meeting Assistant',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.textSecondary.withValues(
                                            alpha: 0.8,
                                          ),
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _showNotificationsSheet();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                    border: Border.all(
                                      color: AppTheme.dividerColor,
                                    ),
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(
                                        Icons.notifications_none_rounded,
                                        color: AppTheme.textPrimary,
                                        size: 20,
                                      ),
                                      if (hasUnread)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: AppTheme.dangerColor,
                                              borderRadius:
                                                  const BorderRadius.all(
                                                    Radius.circular(999),
                                                  ),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _switchTab(4),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                    border: Border.all(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppTheme.primaryColor
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.person_rounded,
                                      size: 18,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // 2. Greeting Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              letterSpacing: 0.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _capitalizeName(userName),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Turn your meetings into action.',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(
                            height: 24,
                          ), // Professional spacing before the image
                          Container(
                            width: double.infinity,
                            height:
                                140, // Perfectly sized for the wide illustration
                            alignment: Alignment.center,
                            child: Opacity(
                              opacity: 0.95,
                              child: Image.asset(
                                'assets/images/hero_illustration.png',
                                fit: BoxFit.contain,
                                color: AppTheme.backgroundColor,
                                colorBlendMode: BlendMode.darken,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // 3. Hero Card: Record Meeting
                      GestureDetector(
                        onTap: () => _showNewMeetingSetup(
                          title: 'Record Meeting',
                          subtitle: 'Add context for the AI before recording.',
                          buttonText: 'Start Recording',
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16), 
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(20), 
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 16, 
                                offset: const Offset(0, 8), 
                              ),
                            ],
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                right: -40,
                                top: -40,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  RepaintBoundary(
                                    child: SlideTransition(
                                      position: _slideAnimation,
                                    child: Container(
                                      padding: const EdgeInsets.all(12), 
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(16), 
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.mic_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ), 
                                    ),
                                  ),
                                ),
                                  const SizedBox(width: 16), 
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Start Recording',
                                          style: TextStyle(
                                            fontSize: 18, 
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Record, transcribe & summarize', 
                                          style: TextStyle(
                                            fontSize: 12, 
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white70,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(8), 
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(999),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ), 
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 4. Quick Actions: Create Room, Join, Schedule (Adaptive)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Create Room
                          Expanded(
                            child: GestureDetector(
                              onTap: _showNewMeetingSetup,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: Responsive.value(context, mobile: 64.0, narrow: 54.0),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF7A00).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFFFF7A00).withValues(alpha: 0.3)),
                                    ),
                                    child: Icon(Icons.add_box_rounded, color: const Color(0xFFFF7A00), size: Responsive.value(context, mobile: 28.0, narrow: 22.0)),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 34,
                                    child: Text(
                                      'Create Room', 
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: Responsive.value(context, mobile: 13.0, narrow: 11.0), color: AppTheme.textPrimary, height: 1.2),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: Responsive.value(context, mobile: 16.0, narrow: 8.0)),
                          // Have Code ?
                          Expanded(
                            child: GestureDetector(
                              onTap: _showJoinMeetingSetup,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: Responsive.value(context, mobile: 64.0, narrow: 54.0),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Icon(Icons.group_add_rounded, color: AppTheme.primaryColor, size: Responsive.value(context, mobile: 28.0, narrow: 22.0)),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 34,
                                    child: Text(
                                      'Have Code ?', 
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: Responsive.value(context, mobile: 13.0, narrow: 11.0), color: AppTheme.textPrimary, height: 1.2),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: Responsive.value(context, mobile: 16.0, narrow: 8.0)),
                          // Schedule
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _switchTab(2), // Navigate to Schedule tab
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: Responsive.value(context, mobile: 64.0, narrow: 54.0),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Icon(Icons.calendar_month_rounded, color: AppTheme.accentColor, size: Responsive.value(context, mobile: 28.0, narrow: 22.0)),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 34,
                                    child: Text(
                                      'Schedule', 
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: Responsive.value(context, mobile: 13.0, narrow: 11.0), color: AppTheme.textPrimary, height: 1.2),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // 4. Premium Grid Layout (Adaptive across Narrow Fold, Phone & Tablet)
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: Responsive.gridColumns(
                          context,
                          narrow: 2,
                          mobile: 2,
                          foldable: 4,
                          desktop: 4,
                        ),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: Responsive.value(
                          context,
                          mobile: 16.0,
                          narrow: 10.0,
                        ),
                        childAspectRatio: Responsive.gridChildAspectRatio(
                          context,
                          narrow: 0.74,
                          mobile: 0.82,
                          foldable: 1.05,
                          desktop: 1.15,
                        ),
                        children: [
                          buildGridCard(
                            title: 'My Meetings',
                            subtitle: 'View and manage your recorded meetings',
                            chipText: '$meetingCount recorded',
                            onTap: () => _switchTab(1),
                            iconWidget: const Icon(
                              Icons.calendar_month_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            iconGradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF007DFE), Color(0xFF0056DF)],
                            ),
                            wave1Color: const Color(0xFFE2EFFF),
                            wave2Color: const Color(0xFFBFDBFE),
                            chipBgColor: const Color(0xFFE0EFFF),
                            chipTextColor: const Color(0xFF1E60F0),
                          ),
                          buildGridCard(
                            title: 'Summaries',
                            subtitle: 'Get AI-powered summaries and key insights',
                            chipText: '$summaryCount generated',
                            onTap: () => _switchTab(1),
                            iconWidget: const Icon(
                              Icons.description_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            iconGradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF00C853), Color(0xFF009624)],
                            ),
                            wave1Color: const Color(0xFFE6F8EF),
                            wave2Color: const Color(0xFFA7F3D0),
                            chipBgColor: const Color(0xFFDCFCE7),
                            chipTextColor: const Color(0xFF059669),
                          ),
                          buildGridCard(
                            title: 'Action Items',
                            subtitle: 'Track your tasks and never miss anything',
                            chipText: '$pendingTasksCount pending',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ActionItemsScreen(),
                              ),
                            ),
                            iconWidget: Center(
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_rounded,
                                    color: Color(0xFFFF6F00),
                                    size: 15,
                                  ),
                                ),
                              ),
                            ),
                            iconGradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFA000), Color(0xFFFF6F00)],
                            ),
                            wave1Color: const Color(0xFFFFF1DF),
                            wave2Color: const Color(0xFFFED7AA),
                            chipBgColor: const Color(0xFFFEF3C7),
                            chipTextColor: const Color(0xFFD97706),
                          ),
                          buildGridCard(
                            title: 'Notes',
                            subtitle: 'Capture important points and ideas',
                            chipText: '${_manualNotes.length} notes',
                            onTap: () => _switchTab(3),
                            iconWidget: const Icon(
                              Icons.note_alt_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            iconGradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                            ),
                            wave1Color: const Color(0xFFF3E8FF),
                            wave2Color: const Color(0xFFDDD6FE),
                            chipBgColor: const Color(0xFFEDE9FE),
                            chipTextColor: const Color(0xFF7C3AED),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
          ),
        ),
      ),
    ),
  );
  }

  void _confirmDeleteNote(int index) {
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
          'Are you sure you want to permanently delete this note? This action cannot be undone.',
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
            onPressed: () {
              Navigator.pop(ctx);
              _deleteNote(index);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Note deleted'),
                  duration: Duration(seconds: 2),
                ),
              );
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

  Future<void> _showAddNoteDialog({int? index}) async {
    HapticFeedback.lightImpact();
    final String currentText = (index != null && index >= 0 && index < _manualNotes.length)
        ? _manualNotes[index]
        : '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => NoteDialogSheet(
        initialText: currentText,
        isEditing: index != null,
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      if (index != null && index >= 0 && index < _manualNotes.length) {
        await _updateNote(index, result);
      } else {
        await _addNote(result);
      }
    }
  }

  Widget _buildLibraryTab() {
    final filteredNotesWithIndex = <MapEntry<int, String>>[];
    for (int i = 0; i < _manualNotes.length; i++) {
      final note = _manualNotes[i];
      if (_noteSearchQuery.isEmpty ||
          note.toLowerCase().contains(_noteSearchQuery)) {
        filteredNotesWithIndex.add(MapEntry(i, note));
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Notes',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              _manualNotes.isEmpty
                  ? 'Quick thoughts & meeting notes'
                  : '${_manualNotes.length} ${_manualNotes.length == 1 ? 'note' : 'notes'} saved',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: ResponsiveContentWrapper(
        maxWidth: Responsive.maxContentWidth,
        child: _manualNotes.isEmpty
            ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                          width: 2,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.note_alt_outlined,
                          size: 48,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No Notes Yet',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Capture meeting takeaways, ideas, action items, or quick reminders in one place.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showAddNoteDialog();
                      },
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Create First Note',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
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
                    child: TextField(
                      controller: _noteSearchController,
                      onChanged: (val) {
                        setState(() {
                          _noteSearchQuery = val.trim().toLowerCase();
                        });
                      },
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        hintText: 'Search notes by keyword...',
                        hintStyle: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                        isDense: true,
                        suffixIcon: _noteSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                ),
                                color: AppTheme.textSecondary,
                                onPressed: () {
                                  _noteSearchController.clear();
                                  setState(() => _noteSearchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),

                // Counter / Status Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        _noteSearchQuery.isEmpty
                            ? 'ALL NOTES (${_manualNotes.length})'
                            : 'FOUND ${filteredNotesWithIndex.length} MATCH${filteredNotesWithIndex.length == 1 ? '' : 'ES'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppTheme.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                      const Spacer(),
                      if (_noteSearchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _noteSearchController.clear();
                            setState(() => _noteSearchQuery = '');
                          },
                          child: const Text(
                            'Clear filter',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        )
                      else
                        TextButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showAddNoteDialog();
                          },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text(
                            'Add Note',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ),

                // Note List or Filter Empty State
                Expanded(
                  child: filteredNotesWithIndex.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 60,
                                  color: AppTheme.textSecondary.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No matching notes',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No notes match "$_noteSearchQuery"',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                OutlinedButton(
                                  onPressed: () {
                                    _noteSearchController.clear();
                                    setState(() => _noteSearchQuery = '');
                                  },
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Reset Search'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            Responsive.horizontalPadding(context),
                            4,
                            Responsive.horizontalPadding(context),
                            24,
                          ),
                          itemCount: filteredNotesWithIndex.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = filteredNotesWithIndex[index];
                            final originalIndex = entry.key;
                            final note = entry.value;

                            final lines = note
                                .split('\n')
                                .map((l) => l.trim())
                                .where((l) => l.isNotEmpty)
                                .toList();
                            final title = lines.isNotEmpty
                                ? lines.first
                                : 'Untitled Note';
                            final body = lines.length > 1
                                ? lines.skip(1).join('\n')
                                : '';
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
                                  onTap: () =>
                                      _showAddNoteDialog(index: originalIndex),
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusCard),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Top tag & actions row
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF8B5CF6,
                                                ).withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(
                                                    Icons.sticky_note_2_rounded,
                                                    color: Color(0xFF8B5CF6),
                                                    size: 13,
                                                  ),
                                                  SizedBox(width: 5),
                                                  Text(
                                                    'Note',
                                                    style: TextStyle(
                                                      color: Color(0xFF8B5CF6),
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            // Copy button
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              tooltip: 'Copy Note',
                                              icon: Icon(
                                                Icons.copy_rounded,
                                                size: 17,
                                                color: AppTheme.textSecondary
                                                    .withValues(alpha: 0.7),
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
                                                    duration: Duration(
                                                      seconds: 2,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 14),
                                            // Edit button
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              tooltip: 'Edit Note',
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: AppTheme.textSecondary
                                                    .withValues(alpha: 0.7),
                                              ),
                                              onPressed: () =>
                                                  _showAddNoteDialog(
                                                index: originalIndex,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            // Delete button
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              tooltip: 'Delete Note',
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                                color: AppTheme.dangerColor
                                                    .withValues(alpha: 0.8),
                                              ),
                                              onPressed: () =>
                                                  _confirmDeleteNote(
                                                originalIndex,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        // Title
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
                                        // Body (if available)
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
                                        // Bottom metadata row
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.short_text_rounded,
                                              size: 15,
                                              color: AppTheme.textSecondary
                                                  .withValues(alpha: 0.6),
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
            ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name'] ?? 'User';
    final userEmail = user?.email ?? 'user@email.com';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: ResponsiveContentWrapper(
        maxWidth: Responsive.maxContentWidth,
        child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 32,
              bottom: 40,
            ),
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: const CircleAvatar(
                    radius: 46,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 46,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userEmail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
              ),
              children: [
                buildProfileMenuItem(
                  Icons.person_outline,
                  'My Profile',
                  'View and edit your profile',
                  AppTheme.primaryColor,
                  () => Navigator.pushNamed(context, '/my_profile'),
                ),
                buildProfileMenuItem(
                  Icons.settings_outlined,
                  'Settings',
                  'App preferences & security',
                  Colors.green,
                  () => Navigator.pushNamed(context, '/settings'),
                ),
                buildProfileMenuItem(
                  Icons.help_outline,
                  'Help & Support',
                  'Get help or contact us',
                  Colors.deepPurple,
                  () => Navigator.pushNamed(context, '/help'),
                ),
                const SizedBox(height: 8),
                buildProfileMenuItem(
                  Icons.logout_rounded,
                  'Logout',
                  'Sign out from your account',
                  AppTheme.dangerColor,
                  () {
                    showDialog(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          backgroundColor: AppTheme.surfaceColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: const Text(
                            'Logout',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          content: const Text(
                            'Are you sure you want to log out of your account?',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
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
                                Navigator.pop(dialogContext);
                                ref.read(meetingsProvider.notifier).clear();
                                ref.read(notificationsProvider.notifier).clearAll();
                                ref.invalidate(meetingsProvider);
                                ref.invalidate(notificationsProvider);
                                await Supabase.instance.client.auth.signOut();
                                if (mounted) {
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/login',
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.dangerColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Logout',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  isLogout: true,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget buildProfileMenuItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap, {
    bool isLogout = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isLogout
            ? AppTheme.dangerColor.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isLogout
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isLogout ? AppTheme.dangerColor : AppTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    if (!_activatedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0:
        return _buildHomeTab();
      case 1:
        return const MeetingsListScreen();
      case 2:
        return const ScheduleScreen();
      case 3:
        return _buildLibraryTab();
      case 4:
        return _buildProfileTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildActiveRecordingBar() {
    return AnimatedBuilder(
      animation: MeetingRecordingService(),
      builder: (context, _) {
        final service = MeetingRecordingService();
        if (!service.isRecording && !service.hasSession) {
          return const SizedBox.shrink();
        }

        final duration = service.recordDuration;
        final minutes = (duration / 60).floor().toString().padLeft(2, '0');
        final seconds = (duration % 60).toString().padLeft(2, '0');

        return ResponsiveContentWrapper(
          maxWidth: Responsive.maxContentWidth,
          child: GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/active_meeting', arguments: {
                'title': service.meetingTitle,
                'room_code': service.roomCode,
                'is_participant': service.isParticipant,
              });
            },
            child: Container(
              margin: EdgeInsets.fromLTRB(
                Responsive.value(context, mobile: 16.0, narrow: 10.0),
                4,
                Responsive.value(context, mobile: 16.0, narrow: 10.0),
                10,
              ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: service.isRecording
                    ? Colors.redAccent.withValues(alpha: 0.6)
                    : Colors.amber.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (service.isRecording ? Colors.redAccent : Colors.amber)
                      .withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: service.isRecording ? Colors.redAccent : Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        service.meetingTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        service.isRecording
                            ? 'Recording in background • $minutes:$seconds'
                            : 'Meeting paused • $minutes:$seconds',
                        style: TextStyle(
                          color: service.isRecording
                              ? Colors.redAccent.shade100
                              : Colors.amber.shade100,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppTheme.primaryColor,
                        size: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _activatedTabs.add(_currentIndex);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildTab(0),
                _buildTab(1),
                _buildTab(2),
                _buildTab(3),
                _buildTab(4),
              ],
            ),
          ),
          _buildActiveRecordingBar(),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? SizedBox(
              width: 48,
              height: 48,
              child: FloatingActionButton(
                heroTag: 'ask_ares_home_fab',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AskAresScreen(),
                    ),
                  );
                },
                backgroundColor: AppTheme.primaryColor,
                elevation: 4,
                shape: const CircleBorder(),
                tooltip: 'Smart Meeting Bot',
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _switchTab,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: Responsive.value(context, mobile: 14.0, narrow: 11.0),
        unselectedFontSize: Responsive.value(context, mobile: 12.0, narrow: 10.0),
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textSecondary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_none_outlined),
            activeIcon: Icon(Icons.mic),
            label: 'Meetings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.note_alt_outlined),
            activeIcon: Icon(Icons.note_alt),
            label: 'Notes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget buildGridCard({
    required String title,
    required String subtitle,
    required String chipText,
    required VoidCallback onTap,
    required LinearGradient iconGradient,
    required Widget iconWidget,
    required Color wave1Color,
    required Color wave2Color,
    required Color chipBgColor,
    required Color chipTextColor,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDarkMode ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDarkMode
                  ? Colors.black.withValues(alpha: 0.3)
                  : const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Dual organic wave background in bottom-right corner (RepaintBoundary cached)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CardWavePainter(
                    wave1Color: isDarkMode
                        ? wave1Color.withValues(alpha: 0.15)
                        : wave1Color,
                    wave2Color: isDarkMode
                        ? wave2Color.withValues(alpha: 0.22)
                        : wave2Color,
                  ),
                ),
              ),
            ),
            // Card Content (Responsive padding, icons & typography)
            Padding(
              padding: EdgeInsets.all(Responsive.value(context, mobile: 16.0, narrow: 10.0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Squircle icon + Chevron
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: Responsive.value(context, mobile: 44.0, narrow: 36.0),
                        height: Responsive.value(context, mobile: 44.0, narrow: 36.0),
                        decoration: BoxDecoration(
                          gradient: iconGradient,
                          borderRadius: BorderRadius.circular(Responsive.value(context, mobile: 14.0, narrow: 11.0)),
                        ),
                        child: Center(child: iconWidget),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: isDarkMode
                            ? Colors.white38
                            : const Color(0xFF94A3B8),
                        size: Responsive.value(context, mobile: 15.0, narrow: 12.0),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Title
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Responsive.value(context, mobile: 16.0, narrow: 13.5),
                      fontWeight: FontWeight.w700,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Subtitle
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: Responsive.value(context, mobile: 11.5, narrow: 10.0),
                      fontWeight: FontWeight.w400,
                      color: isDarkMode
                          ? Colors.white60
                          : const Color(0xFF64748B),
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: Responsive.value(context, mobile: 10.0, narrow: 6.0)),
                  // Bottom Badge / Pill
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.value(context, mobile: 10.0, narrow: 8.0),
                      vertical: Responsive.value(context, mobile: 4.5, narrow: 3.5),
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? chipTextColor.withValues(alpha: 0.15)
                          : chipBgColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      chipText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Responsive.value(context, mobile: 11.0, narrow: 9.5),
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? chipTextColor.withValues(alpha: 0.95)
                            : chipTextColor,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationsSheet() {
    ref.read(notificationsProvider.notifier).markAllAsRead();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final notifs = ref.watch(notificationsProvider);
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.dividerColor,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(notificationsProvider.notifier).clearAll(),
                        child: const Text(
                          'Clear All',
                          style: TextStyle(color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: notifs.isEmpty
                        ? const Center(
                            child: Text(
                              'No new notifications',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: notifs.length,
                            itemBuilder: (context, index) {
                              final n = notifs[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.02,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: const BorderRadius.all(
                                          Radius.circular(999),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.notifications_active_rounded,
                                        color: AppTheme.primaryColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            n.body,
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CardWavePainter extends CustomPainter {
  final Color wave1Color;
  final Color wave2Color;

  const _CardWavePainter({
    required this.wave1Color,
    required this.wave2Color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer smooth wave (layer 1)
    final paint1 = Paint()
      ..color = wave1Color
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(w * 0.38, h);
    path1.cubicTo(
      w * 0.62, h * 0.88,
      w * 0.72, h * 0.50,
      w, h * 0.36,
    );
    path1.lineTo(w, h);
    path1.close();
    canvas.drawPath(path1, paint1);

    // Inner smooth wave (layer 2 - corner accent)
    final paint2 = Paint()
      ..color = wave2Color
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(w * 0.62, h);
    path2.cubicTo(
      w * 0.78, h * 0.90,
      w * 0.85, h * 0.72,
      w, h * 0.60,
    );
    path2.lineTo(w, h);
    path2.close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant _CardWavePainter oldDelegate) {
    return oldDelegate.wave1Color != wave1Color ||
        oldDelegate.wave2Color != wave2Color;
  }
}
