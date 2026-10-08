import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/active_meeting_screen.dart';
import 'screens/meeting_details_screen.dart';
import 'screens/login_screen.dart';
import 'screens/meetings_list_screen.dart';
import 'screens/voice_setup_screen.dart';
import 'screens/my_profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/help_support_screen.dart';

import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await LocalNotificationService().init();

  await Supabase.initialize(
    url: 'https://dhrqllyezfwchvbeshpr.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRocnFsbHllemZ3Y2h2YmVzaHByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMjk0MzksImV4cCI6MjEwNTgwNTQzOX0.J12NtMuLAPSPfRl1xtQLr6N887KUIKwsCfeca6qHR5I',
  );

  runApp(const ProviderScope(child: SmartMeetingApp()));
}

class SmartMeetingApp extends StatelessWidget {
  const SmartMeetingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Meeting AI',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/active_meeting': (context) => const ActiveMeetingScreen(),
        '/meeting_details': (context) => const MeetingDetailsScreen(),
        '/meetings_list': (context) => const MeetingsListScreen(),
        '/voice_setup': (context) => const VoiceSetupScreen(),
        '/my_profile': (context) => const MyProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/help': (context) => const HelpSupportScreen(),
      },
    );
  }
}
