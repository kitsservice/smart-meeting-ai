import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_queue.dart';
import '../services/room_service.dart';
import '../theme/app_theme.dart';

class ActiveMeetingScreen extends ConsumerStatefulWidget {
  const ActiveMeetingScreen({super.key});

  @override
  ConsumerState<ActiveMeetingScreen> createState() =>
      _ActiveMeetingScreenState();
}

class _ActiveMeetingScreenState extends ConsumerState<ActiveMeetingScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool isRecording = false;
  bool isProcessing = false;
  bool isParticipant = false;
  bool hasStarted = false;
  String? roomCode;

  RealtimeChannel? _roomChannel;
  List<Map<String, dynamic>> _participants = [];
  Timer? _presenceSyncTimer;

  // Floating participant join notification
  String? _floatingJoinedUser;
  Timer? _floatingBannerTimer;
  bool _showFloatingBanner = false;

  void _triggerFloatingJoinBanner(String name) {
    if (!mounted) return;
    _floatingBannerTimer?.cancel();
    setState(() {
      _floatingJoinedUser = name;
      _showFloatingBanner = true;
    });

    _floatingBannerTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) {
        setState(() {
          _showFloatingBanner = false;
        });
      }
    });
  }

  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier<int>(0);
  int get _recordDuration => _recordDurationNotifier.value;
  Timer? _timer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['is_participant'] == true) {
        final code = args['room_code'] as String?;
        setState(() {
          isParticipant = true;
          hasStarted = false; // MUST wait for host to start the meeting!
          roomCode = code;
          isRecording =
              false; // Do not start timer or animation until host starts
        });
        _animationController.stop();

        final user = Supabase.instance.client.auth.currentUser;
        final currentUserName = user?.userMetadata?['full_name'] ??
            (user?.email?.split('@')[0] ?? 'You');
        _triggerFloatingJoinBanner('$currentUserName (You)');

        if (code != null) {
          _initRealtimeRoom(code);
          _syncParticipantsWithDB(code);
          RoomService().checkRoomStatus(code).then((status) {
            if (status == 'completed' && mounted) {
              _showHostEndedDialog();
            }
          });
        }
      } else {
        // Generate a random room code for the host
        final newCode =
            (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
                .toString();
        final user = Supabase.instance.client.auth.currentUser;
        final hostName = user?.userMetadata?['full_name'] ??
            (user?.email?.split('@')[0] ?? 'Host');
        final hostId =
            user?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}';

        setState(() {
          roomCode = newCode;
          hasStarted = false; // Room created; wait for host to press Start
        });
        _animationController.stop();
        _initRealtimeRoom(newCode);
        RoomService().markRoomCreated(newCode, hostName: hostName, hostId: hostId);
        _syncParticipantsWithDB(newCode);
      }
    });
  }

  Future<void> _startMeetingSession() async {
    if (hasStarted || isParticipant) return;
    setState(() {
      hasStarted = true;
    });
    if (roomCode != null) {
      RoomService().markRoomActive(roomCode!);
    }
    _animationController.repeat();
    await _startRecording();

    // Broadcast to waiting participants that meeting has begun
    try {
      await _roomChannel?.sendBroadcastMessage(
        event: 'meeting_status',
        payload: {'status': 'started'},
      );
      final user = Supabase.instance.client.auth.currentUser;
      final currentUserId =
          user?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      final currentUserName =
          user?.userMetadata?['full_name'] ??
          (user?.email?.split('@')[0] ?? 'Host');
      await _roomChannel?.track({
        'user_id': currentUserId,
        'name': currentUserName,
        'is_host': true,
        'has_started': true,
        'joined_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error broadcasting meeting start: $e');
    }
  }

  Future<void> _startRecording() async {
    if (isParticipant) return; // Participants don't record
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/meeting_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: path,
        );

        setState(() => isRecording = true);
        _startTimer();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to start recording: $e');
    }
  }

  Future<void> _pauseOrResumeRecording() async {
    if (isParticipant) return; // Participants cannot pause/resume
    HapticFeedback.mediumImpact();
    if (isRecording) {
      await _audioRecorder.pause();
      setState(() => isRecording = false);
      _animationController.stop();
      _roomChannel?.sendBroadcastMessage(
        event: 'meeting_status',
        payload: {'status': 'paused'},
      );
    } else {
      await _audioRecorder.resume();
      setState(() => isRecording = true);
      _animationController.repeat();
      _roomChannel?.sendBroadcastMessage(
        event: 'meeting_status',
        payload: {'status': 'resumed'},
      );
    }
  }

  void _showHostEndedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        content: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Glowing Multi-layer Icon
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
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
            const Text(
              'Meeting Session Completed',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            const Text(
              'The host has concluded this meeting session. The room is now closed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // The Dedicated Room Code Card
            if (roomCode != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
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
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.meeting_room_rounded,
                                color: AppTheme.primaryColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'ROOM CODE',
                              style: TextStyle(
                                color: Colors.white60,
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
                            color:
                                const Color(0xFFEF4444).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 3,
                                backgroundColor: Color(0xFFEF4444),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'EXPIRED',
                                style: TextStyle(
                                  color: Color(0xFFFF8080),
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
                    const SizedBox(height: 12),

                    // Big Room Code Number
                    Text(
                      roomCode!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.do_not_disturb_alt_rounded,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'Expired code cannot be reused',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white60,
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
            const SizedBox(height: 24),

            // Return Button
            Container(
              width: double.infinity,
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
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Return to Home',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (isRecording) {
        _recordDurationNotifier.value++;
      }
    });
  }

  void _updateParticipants(List<Map<String, dynamic>> incoming) {
    final user = Supabase.instance.client.auth.currentUser;
    final currentUserId =
        user?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    final currentUserName =
        user?.userMetadata?['full_name'] ??
        (user?.email?.split('@')[0] ?? (isParticipant ? 'Member' : 'Host'));

    final Map<String, Map<String, dynamic>> map = {};

    // 1. Preserve existing participants
    for (final p in _participants) {
      final uid = (p['user_id'] ?? '').toString();
      if (uid.isNotEmpty) {
        map[uid] = Map<String, dynamic>.from(p);
      }
    }

    // 2. Merge incoming participants
    for (final p in incoming) {
      final uid = (p['user_id'] ?? '').toString();
      if (uid.isNotEmpty) {
        final existing = map[uid] ?? {};
        map[uid] = {
          ...existing,
          ...p,
        };
      }
    }

    // 3. Always ensure current user is present and tagged as self
    final existingSelf = map[currentUserId] ?? {};
    map[currentUserId] = {
      ...existingSelf,
      'user_id': currentUserId,
      'name': currentUserName,
      'is_host': !isParticipant,
      'is_self': true,
      'has_started': hasStarted,
    };

    final list = map.values.toList();
    list.sort((a, b) {
      if (a['is_host'] == true && b['is_host'] != true) return -1;
      if (b['is_host'] == true && a['is_host'] != true) return 1;
      if (a['is_self'] == true && b['is_self'] != true) return -1;
      if (b['is_self'] == true && a['is_self'] != true) return 1;
      return (a['name'] ?? '')
          .toString()
          .compareTo((b['name'] ?? '').toString());
    });

    if (mounted) {
      setState(() {
        _participants = list;
      });
    }
  }

  Future<void> _syncParticipantsWithDB(String code) async {
    try {
      final dbMembers = await RoomService().getRoomParticipants(code);
      if (dbMembers.isNotEmpty && mounted) {
        _updateParticipants(dbMembers);
      }
    } catch (e) {
      debugPrint('Error syncing participants from DB: $e');
    }
  }

  void _initRealtimeRoom(String code) {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final currentUserId =
          user?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      final currentUserName =
          user?.userMetadata?['full_name'] ??
          (user?.email?.split('@')[0] ?? (isParticipant ? 'Member' : 'Host'));

      // Populate current user immediately
      _updateParticipants([]);

      _roomChannel = Supabase.instance.client.channel(
        'meeting_room_$code',
        opts: const RealtimeChannelConfig(self: true),
      );

      _roomChannel!
          .onBroadcast(
            event: 'meeting_status',
            callback: (payload) {
              final status = payload['status'];
              if (status == 'started') {
                if (mounted && isParticipant) {
                  setState(() {
                    hasStarted = true;
                    isRecording = true;
                  });
                  _animationController.repeat();
                  _startTimer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text('The host has started the meeting!'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } else if (status == 'paused') {
                if (mounted && isParticipant) {
                  setState(() => isRecording = false);
                  _animationController.stop();
                }
              } else if (status == 'resumed') {
                if (mounted && isParticipant) {
                  setState(() => isRecording = true);
                  _animationController.repeat();
                }
              } else if (status == 'ended') {
                if (mounted && isParticipant) {
                  setState(() {
                    hasStarted = false;
                    isRecording = false;
                  });
                  _timer?.cancel();
                  _animationController.stop();
                  if (roomCode != null) {
                    RoomService().markRoomCompleted(roomCode!);
                  }
                  _showHostEndedDialog();
                }
              }
            },
          )
          .onBroadcast(
            event: 'participant_joined',
            callback: (payload) {
              final joinedName = payload['name'] ?? 'A member';
              final joinedId = payload['user_id'];
              if (joinedId != currentUserId) {
                _updateParticipants([Map<String, dynamic>.from(payload)]);
                if (mounted) {
                  _triggerFloatingJoinBanner(joinedName);
                }
              }
            },
          )
          .onPresenceSync((_) {
            final presenceState = _roomChannel!.presenceState();
            List<Map<String, dynamic>> activeList = [];
            bool hostHasStarted = false;
            for (var state in presenceState) {
              for (var p in state.presences) {
                final payload = Map<String, dynamic>.from(p.payload);
                activeList.add(payload);
                if (payload['is_host'] == true &&
                    payload['has_started'] == true) {
                  hostHasStarted = true;
                }
              }
            }
            _updateParticipants(activeList);
            if (mounted && isParticipant && !hasStarted && hostHasStarted) {
              setState(() {
                hasStarted = true;
                isRecording = true;
              });
              _animationController.repeat();
              _startTimer();
            }
          })
          .onPresenceJoin((payload) {
            for (var p in payload.newPresences) {
              final joinedName = p.payload['name'] ?? 'A member';
              final joinedId = p.payload['user_id'];
              if (joinedId != currentUserId && mounted) {
                _updateParticipants([Map<String, dynamic>.from(p.payload)]);
                _triggerFloatingJoinBanner(joinedName);
              }
            }
          })
          .onPresenceLeave((payload) {
            for (var p in payload.leftPresences) {
              final leftName = p.payload['name'] ?? 'A member';
              final leftId = p.payload['user_id'];
              if (leftId != currentUserId && mounted) {
                setState(() {
                  final idx = _participants
                      .indexWhere((item) => item['user_id'] == leftId);
                  if (idx != -1) {
                    _participants[idx]['is_active'] = false;
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.person_remove_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$leftName left the meeting',
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.grey.shade800,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            }
          })
          .subscribe((status, [error]) async {
            if (status == RealtimeSubscribeStatus.subscribed) {
              await _roomChannel?.track({
                'user_id': currentUserId,
                'name': currentUserName,
                'is_host': !isParticipant,
                'has_started': hasStarted,
                'joined_at': DateTime.now().toIso8601String(),
              });
              await _roomChannel?.sendBroadcastMessage(
                event: 'participant_joined',
                payload: {
                  'user_id': currentUserId,
                  'name': currentUserName,
                  'is_host': !isParticipant,
                  'joined_at': DateTime.now().toIso8601String(),
                },
              );
              RoomService().recordParticipantJoin(
                code,
                currentUserId,
                currentUserName,
                isHost: !isParticipant,
              );
              _presenceSyncTimer?.cancel();
              _presenceSyncTimer =
                  Timer.periodic(const Duration(seconds: 20), (_) {
                if (mounted && roomCode != null) {
                  _syncParticipantsWithDB(roomCode!);
                }
              });
            }
          });
    } catch (e) {
      debugPrint('Realtime presence error: $e');
    }
  }

  void _showParticipantsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.people_alt_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Meeting Members (${_participants.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 3,
                            backgroundColor: Color(0xFF10B981),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon:
                          const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _participants.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = _participants[index];
                    final name = p['name'] ?? 'Participant';
                    final isHost = p['is_host'] == true;
                    final isSelf = p['is_self'] == true;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelf
                              ? AppTheme.primaryColor.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isHost
                                ? AppTheme.primaryColor.withValues(alpha: 0.25)
                                : AppTheme.accentColor.withValues(alpha: 0.25),
                            child: Text(
                              name.toString().isNotEmpty
                                  ? name.toString()[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: isHost
                                    ? AppTheme.primaryColor
                                    : AppTheme.accentColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name.toString(),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ),
                                    if (isSelf) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'You',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 2.5,
                                      backgroundColor: Color(0xFF10B981),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Active in room',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isHost
                                  ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                                  : const Color(0xFF06B6D4).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isHost
                                    ? const Color(0xFF6366F1).withValues(alpha: 0.4)
                                    : const Color(0xFF06B6D4).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              isHost ? 'Host' : 'Member',
                              style: TextStyle(
                                color: isHost
                                    ? const Color(0xFFA5B4FC)
                                    : const Color(0xFF67E8F9),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_participants.length == 1 && roomCode != null)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4364F7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF4364F7).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.group_add_rounded,
                        color: Color(0xFF93C5FD),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Share code $roomCode with others so they can join this session.',
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
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
    },
  );
  }

  @override
  void dispose() {
    _floatingBannerTimer?.cancel();
    _presenceSyncTimer?.cancel();
    _roomChannel?.unsubscribe();
    _animationController.dispose();
    _timer?.cancel();
    _audioRecorder.dispose();
    _recordDurationNotifier.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> endMeeting() async {
    if (isParticipant) {
      // For participants, simply exit the room
      if (mounted) Navigator.pop(context);
      return;
    }

    if (!hasStarted) {
      if (roomCode != null) {
        RoomService().markRoomCompleted(roomCode!, summaryInfo: 'Closed before start');
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    // Stop recording immediately to ensure file is saved correctly
    String? savedPath;
    if (isRecording) {
      savedPath = await _audioRecorder.stop();
      if (!mounted) return;
      setState(() => isRecording = false);
      _animationController.stop();
    }

    if (!mounted) return;

    final bool? shouldSave = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(sheetContext).padding.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Icon(
                    Icons.stop_circle_rounded,
                    color: AppTheme.dangerColor,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'End Meeting',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Are you sure you want to end this meeting? Do you want to save the transcript or discard it?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(
                              color: AppTheme.dangerColor,
                              width: 1.5,
                            ),
                            backgroundColor: AppTheme.dangerColor.withValues(
                              alpha: 0.1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Discard',
                            style: TextStyle(
                              color: AppTheme.dangerColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: AppTheme.primaryColor.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          icon: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: const Text(
                            'Generate',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldSave == null || !mounted) return;

    setState(() => isProcessing = true);

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final meetingTitle =
        args?['title'] ??
        "Meeting ${DateTime.now().toLocal().toString().split(' ')[0]}";

    if (shouldSave == true && savedPath != null) {
      String meetingDescription =
          "Recorded for ${_formatDuration(_recordDuration)}";
      if (roomCode != null) {
        final dbMembers = await RoomService().getRoomParticipants(roomCode!);
        if (dbMembers.isNotEmpty) {
          _updateParticipants(dbMembers);
        }
        final membersJson = jsonEncode(_participants);
        meetingDescription =
            "[ROOM_CODE:$roomCode] [STATUS:completed] [MEMBERS:$membersJson] $meetingDescription";
        await RoomService().markRoomCompleted(
          roomCode!,
          summaryInfo: 'Recorded for ${_formatDuration(_recordDuration)}',
          participants: _participants,
        );
      }
      if (!mounted) return;

      // Mark matching scheduled meeting as completed in SharedPreferences
      await _markScheduledMeetingCompleted(meetingTitle);

      // Save and queue for transcription
      await OfflineQueueService().queueMeeting(
        meetingTitle,
        meetingDescription,
        savedPath,
      );

      // SHOW SUCCESS NOTIFICATION
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Meeting successfully recorded and saved!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.accentColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      if (roomCode != null) {
        RoomService().markRoomCompleted(
          roomCode!,
          summaryInfo: 'Discarded by host',
          participants: _participants,
        );
      }
    }
    // Broadcast meeting ended to all participants
    try {
      await _roomChannel?.sendBroadcastMessage(
        event: 'meeting_status',
        payload: {'status': 'ended'},
      );
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context, {'completed': true, 'title': meetingTitle});
    }
  }

  Future<void> _markScheduledMeetingCompleted(String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final eventsJson = prefs.getString('scheduled_events');
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        bool modified = false;
        final cleanTitle = title.trim().toLowerCase();
        for (var item in decoded) {
          if (item is Map<String, dynamic>) {
            final itemTitle =
                (item['title'] as String? ?? '').trim().toLowerCase();
            if (itemTitle == cleanTitle && item['isMeeting'] != false) {
              item['isCompleted'] = true;
              modified = true;
            }
          }
        }
        if (modified) {
          await prefs.setString('scheduled_events', jsonEncode(decoded));
        }
      }
    } catch (e) {
      debugPrint('Error marking scheduled meeting as completed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read the passed arguments for the header
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final displayTitle = args?['title'] ?? 'Live Meeting';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await endMeeting();
      },
      child: Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: endMeeting,
          ),
          title: Text(
            displayTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        body: Stack(
          children: [
            // Ambient Background Gradient
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(seconds: 1),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: isRecording ? 1.5 : 1.0,
                    colors: [
                      AppTheme.primaryColor.withValues(
                        alpha: isRecording ? 0.2 : 0.05,
                      ),
                      AppTheme.darkSurface,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  if (roomCode != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isParticipant ? 'Connected to Room: $roomCode' : 'Room Code: $roomCode',
                                style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 2,
                                ),
                              ),
                              if (!isParticipant) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () async {
                                    HapticFeedback.lightImpact();
                                    try {
                                      await Clipboard.setData(ClipboardData(text: roomCode ?? ''));
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Room code copied to clipboard!')),
                                        );
                                      }
                                      await SharePlus.instance.share(
                                        ShareParams(
                                          text:
                                              'Join my Smart Meeting session! Enter code: $roomCode',
                                        ),
                                      );
                                    } catch (e) {
                                      debugPrint('Share error: $e');
                                    }
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.ios_share_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (roomCode != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _showParticipantsSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.8),
                                    blurRadius: 6,
                                    spreadRadius: 1.5,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_participants.length} ${_participants.length == 1 ? 'Person' : 'People'} in Meeting',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                            if (_participants.length > 1) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 20,
                                width: (_participants.length.clamp(1, 3) * 14.0) +
                                    6,
                                child: Stack(
                                  children: [
                                    for (int i = 0;
                                        i < _participants.length.clamp(1, 3);
                                        i++)
                                      Positioned(
                                        left: i * 14.0,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _participants[i]
                                                        ['is_host'] ==
                                                    true
                                                ? AppTheme.primaryColor
                                                : const Color(0xFF06B6D4),
                                            border: Border.all(
                                              color: const Color(0xFF0F172A),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              (_participants[i]['name'] ?? '?')
                                                      .toString()
                                                      .isNotEmpty
                                                  ? (_participants[i]['name'] ??
                                                          '?')
                                                      .toString()[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 20,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // Status Indicator Pill
                  Container(
                    margin: const EdgeInsets.only(top: 14, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: !hasStarted
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                          : (isRecording
                              ? AppTheme.dangerColor.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: !hasStarted
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                            : (isRecording
                                ? AppTheme.dangerColor.withValues(alpha: 0.4)
                                : Colors.orange.withValues(alpha: 0.4)),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: !hasStarted
                                ? const Color(0xFFF59E0B)
                                : (isRecording
                                    ? AppTheme.dangerColor
                                    : Colors.orange),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          !hasStarted
                              ? (isParticipant
                                  ? 'Waiting Room • Host has not started'
                                  : 'Room Ready • Tap Start to Begin')
                              : (isRecording
                                  ? (isParticipant
                                      ? 'Live Session • In Progress'
                                      : 'Live Recording • In Progress')
                                  : (isParticipant
                                      ? 'Session Paused by Host'
                                      : 'Recording Paused')),
                          style: TextStyle(
                            color: !hasStarted
                                ? const Color(0xFFF59E0B)
                                : (isRecording
                                    ? const Color(0xFFFF6B6B)
                                    : Colors.orange),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  // Sleek Timer
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: !hasStarted
                                ? Colors.grey
                                : (isRecording
                                    ? AppTheme.dangerColor
                                    : Colors.grey),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(999),
                            ),
                            boxShadow: (hasStarted && isRecording)
                                ? [
                                    BoxShadow(
                                      color: AppTheme.dangerColor.withValues(
                                        alpha: 0.6,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ValueListenableBuilder<int>(
                          valueListenable: _recordDurationNotifier,
                          builder: (context, duration, _) {
                            return Text(
                              _formatDuration(duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w200,
                                letterSpacing: 2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Center(
                      child: isProcessing
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: AppTheme.primaryColor,
                                ),
                                SizedBox(height: 24),
                                Text(
                                  'Processing Transcript...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            )
                          : (!hasStarted
                              ? (isParticipant
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFFF59E0B)
                                                .withValues(alpha: 0.12),
                                            border: Border.all(
                                              color: const Color(0xFFF59E0B)
                                                  .withValues(alpha: 0.4),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFF59E0B)
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 36,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.hourglass_top_rounded,
                                              color: Color(0xFFF59E0B),
                                              size: 56,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 28),
                                        const Text(
                                          'Waiting for Host...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 40.0,
                                          ),
                                          child: Text(
                                            'Connected to Room $roomCode.\nPlease wait for the host to start the meeting.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.65,
                                              ),
                                              fontSize: 14,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: _startMeetingSession,
                                          child: Container(
                                            width: 130,
                                            height: 130,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient:
                                                  AppTheme.primaryGradient,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.primaryColor
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: 32,
                                                  spreadRadius: 6,
                                                ),
                                              ],
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: Colors.white,
                                                size: 68,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'Start Meeting',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 40.0,
                                          ),
                                          child: Text(
                                            'Room is created! Share code $roomCode with members, then tap Start when ready.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.6,
                                              ),
                                              fontSize: 14,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ))
                              : RepaintBoundary(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Premium Pulse Rings
                                      AnimatedBuilder(
                                        animation: _animationController,
                                        builder: (context, _) {
                                          return Stack(
                                            alignment: Alignment.center,
                                            children: List.generate(3, (index) {
                                              final delay = index * 0.33;
                                              final double value =
                                                  (_animationController.value +
                                                          delay) %
                                                      1.0;
                                              final size = 120 + (value * 200);
                                              return Container(
                                                width: size,
                                                height: size,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      const BorderRadius.all(
                                                    Radius.circular(999),
                                                  ),
                                                  color: AppTheme.primaryColor
                                                      .withValues(
                                                    alpha: isRecording
                                                        ? (1.0 - value) * 0.15
                                                        : 0,
                                                  ),
                                                  border: Border.all(
                                                    color: AppTheme.primaryColor
                                                        .withValues(
                                                      alpha: isRecording
                                                          ? (1.0 - value) * 0.3
                                                          : 0,
                                                    ),
                                                    width: 1,
                                                  ),
                                                ),
                                              );
                                            }),
                                          );
                                        },
                                      ),
                                      // Central Mic Button (Glassmorphism)
                                      Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              const BorderRadius.all(
                                                Radius.circular(999),
                                              ),
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryColor
                                                  .withValues(alpha: 0.2),
                                              blurRadius: 40,
                                              spreadRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          isRecording
                                              ? Icons.mic_rounded
                                              : Icons.mic_off_rounded,
                                          color: Colors.white,
                                          size: 48,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                    ),
                  ),

                  // Bottom Controls
                  if (!hasStarted)
                    Container(
                      margin: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: 48,
                      ),
                      width: double.infinity,
                      height: 56,
                      child: isParticipant
                          ? OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.exit_to_app_rounded,
                                color: Colors.white70,
                                size: 24,
                              ),
                              label: const Text(
                                'Leave Waiting Room',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.05),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryColor
                                        .withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _startMeetingSession,
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                label: const Text(
                                  'Start Meeting',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                    )
                  else
                    // Floating Control Bar
                    Container(
                      margin: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: 48,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (!isParticipant)
                            _buildControlButton(
                              isRecording
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              isRecording ? 'Pause' : 'Resume',
                              Colors.white.withValues(alpha: 0.1),
                              Colors.white,
                              _pauseOrResumeRecording,
                            )
                          else
                            _buildControlButton(
                              Icons.people_alt_rounded,
                              'Members',
                              Colors.white.withValues(alpha: 0.1),
                              Colors.white,
                              _showParticipantsSheet,
                            ),
                          // End Button gets premium danger styling
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: endMeeting,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: AppTheme.dangerColor.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                    border: Border.all(
                                      color: AppTheme.dangerColor,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.dangerColor.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 16,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isParticipant
                                        ? Icons.logout_rounded
                                        : Icons.stop_rounded,
                                    color: AppTheme.dangerColor,
                                    size: 34,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isParticipant ? 'Leave Room' : 'End Meeting',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          _buildControlButton(
                            Icons.edit_note_rounded,
                            'Add Note',
                            Colors.white.withValues(alpha: 0.1),
                            Colors.white,
                            _showAddNoteDialog,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Dynamic Floating Participant Join Banner
            _buildFloatingJoinBanner(),
          ],
        ),
      ), // Closes Scaffold
    ); // Closes WillPopScope
  }

  Widget _buildFloatingJoinBanner() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      top: _showFloatingBanner ? 16 : -110,
      left: 16,
      right: 16,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _showFloatingBanner ? 1.0 : 0.0,
        child: GestureDetector(
          onTap: () {
            _floatingBannerTimer?.cancel();
            setState(() => _showFloatingBanner = false);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppTheme.accentColor.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentColor.withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Glowing Avatar with Green Presence Dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.accentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          (_floatingJoinedUser != null &&
                                  _floatingJoinedUser!.isNotEmpty)
                              ? _floatingJoinedUser![0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E293B),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Name and Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _floatingJoinedUser ?? 'A member',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.accentColor,
                            size: 15,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'joined the meeting via code • ${_participants.length} in room',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Waving Hand icon indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.waving_hand_rounded,
                    color: AppTheme.accentColor,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton(
    IconData icon,
    String label,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _showAddNoteDialog() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        String tempNote = '';
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Text(
                      'Add Meeting Note',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type important points here...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                      maxLines: 3,
                      onChanged: (val) => tempNote = val,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white70, fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(sheetContext, tempNote.trim()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Save Note',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result != null && result.trim().isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final List<String> notes = prefs.getStringList('manual_notes') ?? [];
      notes.insert(0, result.trim());
      await prefs.setStringList('manual_notes', notes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved! It will appear in your Notes tab.'),
            backgroundColor: AppTheme.accentColor,
          ),
        );
      }
    }
  }
}
