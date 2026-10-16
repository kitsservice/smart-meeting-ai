import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'action_items_screen.dart';
import 'meetings_list_screen.dart';
import 'schedule_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/meetings_provider.dart';
import '../providers/notifications_provider.dart';
import '../services/room_service.dart';
import '../widgets/note_dialog_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  List<String> _manualNotes = [];
  String _noteSearchQuery = '';
  final TextEditingController _noteSearchController = TextEditingController();

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
    HapticFeedback.lightImpact();
    String meetingTitle = '';

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 32,
                    ),
                    decoration: const BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: AppTheme.dividerColor,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Title TextField Card
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.dividerColor),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: TextField(
                            autofocus: true,
                            onChanged: (val) => meetingTitle = val,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.edit_note_rounded,
                                color: AppTheme.primaryColor,
                                size: 24,
                              ),
                              hintText: 'Enter meeting title (e.g., Team Sync)',
                              hintStyle: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 15,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Action Button
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppTheme.primaryColor.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              final trimmed = meetingTitle.trim().isEmpty
                                  ? 'Untitled Meeting'
                                  : meetingTitle.trim();
                              Navigator.pop(sheetContext, trimmed);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  buttonText == 'Start Recording'
                                      ? Icons.mic_rounded
                                      : Icons.meeting_room_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  buttonText,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      await Navigator.pushNamed(
        context,
        '/active_meeting',
        arguments: {
          'title': result,
        },
      );
      if (mounted) {
        ref.read(meetingsProvider.notifier).fetchMeetings();
      }
    }
  }

  Future<void> _showJoinMeetingSetup() async {
    HapticFeedback.lightImpact();
    String roomCode = '';
    bool isVerifying = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 32,
                    ),
                    decoration: const BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: AppTheme.dividerColor,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                        const Text(
                          'Join with a Code',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter the 6-digit room code to join an active meeting.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Room Code TextField Card
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.dividerColor),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: TextField(
                            autofocus: true,
                            onChanged: (val) => roomCode = val.trim(),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 26,
                              letterSpacing: 12,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: '000000',
                              counterText: '',
                              hintStyle: TextStyle(
                                color: AppTheme.dividerColor,
                                letterSpacing: 12,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Join Button
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: isVerifying
                                ? null
                                : () async {
                                    final cleanCode = roomCode.trim();
                                    if (cleanCode.length == 6) {
                                      setModalState(() => isVerifying = true);
                                      final status = await RoomService()
                                          .checkRoomStatus(cleanCode);
                                      if (!modalContext.mounted) return;
                                      setModalState(() => isVerifying = false);

                                      if (status == 'completed') {
                                        Navigator.pop(sheetContext); // Close modal
                                        if (mounted) {
                                          _showMeetingCompletedSheet(
                                              context, cleanCode);
                                        }
                                        return;
                                      }

                                      Navigator.pop(sheetContext); // Close modal
                                      final currentUser = Supabase
                                          .instance.client.auth.currentUser;
                                      final userId = currentUser?.id ??
                                          'user_${DateTime.now().millisecondsSinceEpoch}';
                                      final userName = currentUser
                                              ?.userMetadata?['full_name'] ??
                                          (currentUser?.email?.split('@')[0] ??
                                              'Participant');
                                      await RoomService().recordParticipantJoin(
                                        cleanCode,
                                        userId,
                                        userName,
                                        isHost: false,
                                      );
                                      if (!mounted) return;
                                      await Navigator.pushNamed(
                                        context,
                                        '/active_meeting',
                                        arguments: {
                                          'title': 'Joined Meeting: $cleanCode',
                                          'is_participant': true,
                                          'room_code': cleanCode,
                                        },
                                      );
                                      if (mounted) {
                                        ref
                                            .read(meetingsProvider.notifier)
                                            .fetchMeetings();
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Please enter a 6-digit code'),
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isVerifying
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.login_rounded,
                                          color: Colors.white, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Join with a Code',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMeetingCompletedSheet(BuildContext parentContext, String code) {
    final isDark = Theme.of(parentContext).brightness == Brightness.dark;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).padding.bottom + 24,
            left: 24,
            right: 24,
            top: 20,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Glowing Multi-layer Icon
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : const Color(0xFFFEF2F2),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                        : const Color(0xFFFECDD3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFF43F5E), Color(0xFFE11D48)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Icons.event_busy_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Meeting Session Completed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                'This meeting room has concluded and is no longer active.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // The Dedicated Room Code Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : const Color(0xFFE2E8F0),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.meeting_room_rounded,
                                color: AppTheme.primaryColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ROOM CODE',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        // Status Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFECACA),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDC2626),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'EXPIRED',
                                style: TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Big Room Code Number
                    Text(
                      code,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 14),

                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.do_not_disturb_alt_rounded,
                          size: 15,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Expired code cannot be reused',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Host Guidance Callout
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF4364F7).withValues(alpha: 0.1)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF4364F7).withValues(alpha: 0.25)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: isDark
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF2563EB),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please ask the meeting host to start a new session and provide a fresh 6-digit code.',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFF1E40AF),
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : const Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.white,
                        ),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF475569),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showJoinMeetingSetup();
                        },
                        icon: const Icon(
                          Icons.dialpad_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        label: const Text(
                          'Try Another Code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
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
                ],
              ),
            ],
          ),
        ),
      );
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

    // RIVERPOD STATE INJECTION
    final meetingsState = ref.watch(meetingsProvider);
    final meetingCount = meetingsState.value?.length ?? 0;

    int summaryCount = 0;
    int pendingTasksCount = 0;
    if (meetingsState.value != null) {
      for (var m in meetingsState.value!) {
        if (m['summary'] != null && m['summary'].toString().trim().isNotEmpty) {
          summaryCount++;
        }
        if (m['action_items'] != null && m['action_items'] is List) {
          for (var item in m['action_items']) {
            if (item is Map && item['is_completed'] == false) {
              pendingTasksCount++;
            }
          }
        }
      }
    }

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
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:
                [
                      // 1. Premium App Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
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
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Smart Meeting',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.textPrimary,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  Text(
                                    'AI-Powered Meeting Assistant',
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
                            ],
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _showNotificationsSheet();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
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
                                        size: 22,
                                      ),
                                      if (hasUnread)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: AppTheme.dangerColor,
                                              borderRadius:
                                                  const BorderRadius.all(
                                                    Radius.circular(999),
                                                  ),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _currentIndex = 4;
                                  });
                                },
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
                                    radius: 18,
                                    backgroundColor: AppTheme.primaryColor
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.person_rounded,
                                      size: 20,
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
                                  SlideTransition(
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

                      // 4. Quick Actions: Create Room, Join, Schedule
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
                                    height: 64,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF7A00).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFFFF7A00).withValues(alpha: 0.3)),
                                    ),
                                    child: const Icon(Icons.add_box_rounded, color: Color(0xFFFF7A00), size: 28),
                                  ),
                                  const SizedBox(height: 8),
                                  const SizedBox(
                                    height: 34,
                                    child: Text(
                                      'Create Room', 
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary, height: 1.2),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Have Code ?
                          Expanded(
                            child: GestureDetector(
                              onTap: _showJoinMeetingSetup,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 64,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                                    ),
                                    child: const Icon(Icons.group_add_rounded, color: AppTheme.primaryColor, size: 28),
                                  ),
                                  const SizedBox(height: 8),
                                  const SizedBox(
                                    height: 34,
                                    child: Text(
                                      'Have Code ?', 
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary, height: 1.2),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Schedule
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _currentIndex = 2), // Navigate to Schedule tab
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 64,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                                    ),
                                    child: const Icon(Icons.calendar_month_rounded, color: AppTheme.accentColor, size: 28),
                                  ),
                                  const SizedBox(height: 8),
                                  const SizedBox(
                                    height: 34,
                                    child: Text(
                                      'Schedule', 
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary, height: 1.2),
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

                      // 4. Premium Grid Layout
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio:
                            0.85, // adjusted for the new taller layout
                        children:
                            [
                                  buildGridCard(
                                    Icons.calendar_today_rounded,
                                    'My Meetings',
                                    'View and manage your recorded meetings',
                                    '$meetingCount recorded',
                                    AppTheme.primaryColor,
                                    () => setState(() => _currentIndex = 1),
                                  ),
                                  buildGridCard(
                                    Icons.text_snippet_rounded,
                                    'Summaries',
                                    'Get AI-powered summaries and key insights',
                                    '$summaryCount generated',
                                    AppTheme.accentColor,
                                    () => setState(() => _currentIndex = 1),
                                  ),
                                  buildGridCard(
                                    Icons.check_circle_outline_rounded,
                                    'Action Items',
                                    'Track your tasks and never miss anything',
                                    '$pendingTasksCount pending',
                                    const Color(0xFFF59E0B),
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ActionItemsScreen(),
                                      ),
                                    ),
                                  ),
                                  buildGridCard(
                                    Icons.edit_document,
                                    'Notes',
                                    'Capture important points and ideas',
                                    '${_manualNotes.length} notes',
                                    const Color(
                                      0xFF8B5CF6,
                                    ), // Purple color from the UI image
                                    () => setState(() => _currentIndex = 3),
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
      body: _manualNotes.isEmpty
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
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
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
    );
  }

  Widget _buildProfileTab() {
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name'] ?? 'User';
    final userEmail = user?.email ?? 'user@email.com';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
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
              padding: const EdgeInsets.symmetric(horizontal: 24),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const MeetingsListScreen(),
          const ScheduleScreen(),
          _buildLibraryTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
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

  Widget buildGridCard(
    IconData icon,
    String title,
    String subtitle,
    String chipText,
    Color color,
    VoidCallback onTap,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDarkMode ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.dividerColor.withValues(
              alpha: isDarkMode ? 0.1 : 0.4,
            ),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative background shapes to mimic the waves
            Positioned(
              right: -30,
              bottom: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  color: color.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              right: -10,
              bottom: -20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  color: color.withValues(alpha: 0.05),
                ),
              ),
            ),
            // Card Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: Colors.white, size: 24),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                        size: 14,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      chipText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
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

