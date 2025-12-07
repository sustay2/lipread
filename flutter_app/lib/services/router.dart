import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_app/services/auth_services.dart';
import 'package:flutter_app/services/badge_listener.dart';
import 'package:flutter_app/services/xp_service.dart';
import 'package:flutter_app/services/daily_task_service.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/home/home_screen.dart';
import '../features/lessons/lesson_list_screen.dart';
import '../features/lessons/lesson_detail_screen.dart';
import '../features/results/results_screen.dart';
import '../features/subscription/subscription_page.dart';
import '../features/transcribe/transcribe_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/account_page.dart';
import '../features/profile/billing_info_page.dart';
import 'package:flutter_app/common/widgets/main_scaffold.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/forgot_password_sent_screen.dart';
import '../features/tasks/task_list_screen.dart';
import '../features/activities/quiz_activity_page.dart';
import 'package:flutter_app/features/activities/activity_screens.dart';
import 'package:flutter_app/features/transcribe/transcription_history_page.dart';

final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();

// Stubs for role homes (replace with real pages)
class CreatorHomeScreen extends StatelessWidget { const CreatorHomeScreen({super.key}); @override Widget build(_) => const Scaffold(body: Center(child: Text('Creator Home'))); }
class InstructorHomeScreen extends StatelessWidget { const InstructorHomeScreen({super.key}); @override Widget build(_) => const Scaffold(body: Center(child: Text('Instructor Home'))); }
class AdminEntryScreen extends StatelessWidget { const AdminEntryScreen({super.key}); @override Widget build(_) => const Scaffold(body: Center(child: Text('Admin Panel'))); }

/// Centralized names to avoid typos
class Routes {
  static const splash        = '/';                  // Splash/decider
  static const login         = '/login';
  static const register      = '/register';
  static const verifyEmail   = '/verify-email';

  // Learner shell & tabs
  static const learnerShell  = '/app';               // wraps MainNavScaffold
  static const home          = '/app/home';
  static const tasks         = '/app/tasks';
  static const lessons       = '/app/lessons';
  static const lessonDetail  = '/app/lesson';        // use arguments
  static const transcribe    = '/app/transcribe';
  static const transcriptions = '/transcriptions';
  static const subscription  = '/app/subscription';
  static const results       = '/app/results';
  static const profile       = '/app/profile';
  static const profileAccount= '/app/profile/account';
  static const profileBilling= '/app/profile/billing';

  // Role homes
  static const creator       = '/creator';
  static const instructor    = '/instructor';
  static const admin         = '/admin';

  static const forgotPassword    = '/forgot-password';
  static const forgotPasswordSent= '/forgot-password/sent';

  // Activity-specific routes
  static const videoDrill      = '/app/activity/video-drill';
  static const visemeMatch     = '/app/activity/viseme-match';
  static const mirrorPractice  = '/app/activity/mirror-practice';
  static const quiz            = '/app/activity/quiz';
  static const quizActivity    = '/activity/quiz';
  static const dictationActivity = '/activity/dictation';
  static const practiceActivity  = '/activity/practice';

  // Add Stripe Callback Routes
  static const stripeSuccess = '/stripe/success';
  static const stripeCancel  = '/stripe/cancel';
}

/// Arguments for lesson detail
class LessonDetailArgs {
  final String id;
  LessonDetailArgs(this.id);
}

/// Top-level route generator
class AppNavigator {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.splash:
        return _material(const _SplashDecider());

      case Routes.login:
        return _material(const LoginScreen());

      case Routes.register:
        return _material(const RegisterScreen());

      case Routes.verifyEmail:
        return _material(const VerifyEmailScreen());

    // Learner shell (tab scaffold)
      case Routes.learnerShell:
        return _material(const _LearnerShell());

    // Tabs (they are pages hosted inside the shell; still allow direct links)
      case Routes.home:
        return _material(const HomeScreen());

      case Routes.tasks:
        return _material(const TaskListScreen());

      case Routes.lessons:
        return _material(const LessonListScreen());

      case Routes.lessonDetail:
        final args = settings.arguments as LessonDetailArgs;
        return _material(LessonDetailScreen(lessonId: args.id));

      case Routes.transcribe:
        final lessonId = (settings.arguments is String) ? settings.arguments as String : null;
        return _material(TranscribePage(lessonId: lessonId));

      case Routes.transcriptions:
        return MaterialPageRoute(
          builder: (_) => const TranscriptionHistoryPage(),
        );

      case Routes.subscription:
        return _material(const SubscriptionPage());

      case Routes.results:
        return _material(const ResultsScreen());

      case Routes.profile:
        return _material(const ProfilePage());

      case Routes.profileAccount:
        return _material(const AccountPage());

      case Routes.profileBilling:
        return _material(const BillingInfoPage());

    // Role homes
      case Routes.creator:
        return _material(const CreatorHomeScreen());
      case Routes.instructor:
        return _material(const InstructorHomeScreen());
      case Routes.admin:
        return _material(const AdminEntryScreen());

      case Routes.forgotPassword:
        return _material(const ForgotPasswordScreen());
      case Routes.forgotPasswordSent:
        return _material(const ForgotPasswordSentScreen());

      // Activity-specific routes
      case Routes.videoDrill:
        return _material(VideoDrillScreen(
          activityRef: settings.arguments as String,
        ));

      case Routes.visemeMatch:
        return _material(VisemeMatchScreen(
          activityRef: settings.arguments as String,
        ));

      case Routes.mirrorPractice:
        return _material(MirrorPracticeScreen(
          activityRef: settings.arguments as String,
        ));

      case Routes.quizActivity:
        final args = settings.arguments as QuizActivityArgs;
        return _material(QuizActivityPage(
          courseId: args.courseId,
          moduleId: args.moduleId,
          lessonId: args.lessonId,
          activityId: args.activityId,
        ));

      case Routes.dictationActivity:
        return _material(DictationActivityScreen(
          activityRef: settings.arguments as String,
        ));

      case Routes.practiceActivity:
        return _material(PracticeActivityScreen(
          activityRef: settings.arguments as String,
        ));

      // Handle Stripe Success
      case Routes.stripeSuccess:
        return _material(const BillingInfoPage());

      // Handle Stripe Cancel
      case Routes.stripeCancel:
        return _material(const SubscriptionPage());

      default:
        return _material(Scaffold(
          appBar: AppBar(title: const Text('Not found')),
          body: Center(child: Text('Unknown route: ${settings.name}')),
        ));
    }
  }

  static MaterialPageRoute _material(Widget child) =>
      MaterialPageRoute(builder: (_) => child);
}

/// Initial decider:
/// - if signed out -> Login
/// - if signed in but not verified -> Verify Email
/// - if verified -> route by role (learner -> learner shell, others -> role homes)
class _SplashDecider extends StatefulWidget {
  const _SplashDecider();
  @override
  State<_SplashDecider> createState() => _SplashDeciderState();
}

class _SplashDeciderState extends State<_SplashDecider> {
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      if (user == null) {
        _replace(Routes.login);
        return;
      }

      // Ensure latest auth user
      await AuthService.instance.reloadCurrentUser();

      // Email verification gate for password users
      if (!AuthService.instance.isEmailVerified &&
          user.providerData.any((p) => p.providerId == 'password')) {
        _replace(Routes.verifyEmail);
        return;
      }

      final uid = user.uid;

      // Ensure streak reflects last completion (once per day)
      await DailyTaskService.ensureStreakConsistency(uid);

      // Badge Pop-up
      BadgeListener.start(context, uid);

      // XP service
      XpService.ensureStatsInitialized(user.uid);

      // Role-based routing
      final role = await AuthService.instance.getEffectiveRole(uid);
      switch (role) {
        case 'admin':
          _replace(Routes.admin);
          break;
        case 'creator':
          _replace(Routes.creator);
          break;
        case 'instructor':
          _replace(Routes.instructor);
          break;
        default:
          _replace(Routes.learnerShell);
      }
    });
  }

  void _replace(String route) {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Learner shell that hosts your existing bottom navigation (`MainNavScaffold`)
/// Swap your current implementation in here if it already exists elsewhere.
class _LearnerShell extends StatelessWidget {
  const _LearnerShell();

  @override
  Widget build(BuildContext context) {
    // If your MainNavScaffold already indexes pages internally, just return it.
    // Otherwise, you can wire it to open the mapped tab routes above.
    return const MainNavScaffold();
  }
}
