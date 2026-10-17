import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/active_meeting_screen.dart';
import 'screens/meeting_details_screen.dart';
import 'screens/login_screen.dart';
import 'screens/meetings_list_screen.dart';
import 'screens/voice_setup_screen.dart';
import 'screens/my_profile_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/help_support_screen.dart';

import 'services/notification_service.dart';
import 'services/foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Foreground Service for background recording & transcription
  MeetingForegroundService().init();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  await LocalNotificationService().init();

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    publishableKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // Initialize Sentry for crash reporting
  final sentryDsn = dotenv.env['SENTRY_DSN'] ?? '';
  if (sentryDsn.isNotEmpty && sentryDsn.startsWith('http')) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 1.0;
      },
      appRunner: () => runApp(
        const ProviderScope(child: SmartMeetingApp()),
      ),
    );
  } else {
    runApp(
      const ProviderScope(child: SmartMeetingApp()),
    );
  }
}

class SmartMeetingApp extends StatelessWidget {
  const SmartMeetingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Meeting',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
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
