import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/lessons/lesson_list_screen.dart';
import '../../features/transcribe/transcribe_page.dart';
import '../../features/transcribe/transcribe_tab_state.dart';
import '../../features/subscription/subscription_page.dart';
import '../../features/profile/profile_page.dart';

class MainNavScaffold extends StatefulWidget {
  final StatefulNavigationShell? navigationShell;

  const MainNavScaffold({super.key, this.navigationShell});

  @override
  State<MainNavScaffold> createState() => _MainNavScaffoldState();
}

class _MainNavScaffoldState extends State<MainNavScaffold> {
  static const int _homeIdx = 0;
  static const int _lessonsIdx = 1;
  static const int _transcribeIdx = 2;
  static const int _subscriptionIdx = 3;
  static const int _profileIdx = 4;

  int _localIndex = _homeIdx;

  int get _index => widget.navigationShell?.currentIndex ?? _localIndex;

  void _onTap(int i) {
    if (widget.navigationShell != null) {
      // Using go_router's StatefulNavigationShell
      widget.navigationShell!.goBranch(
        i,
        initialLocation: i == widget.navigationShell!.currentIndex,
      );
    } else {
      // Simple local index for non-go_router usage
      setState(() => _localIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = _index;

    // Let transcribe-specific widgets (like RecordCard) know
    // whether the Transcribe tab is currently active.
    TranscribeTabState.isActive.value = (idx == _transcribeIdx);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FD),
      // IMPORTANT: do NOT keep TranscribePage alive when its tab is inactive.
      body: IndexedStack(
        index: idx,
        children: [
          const HomeScreen(),
          const LessonListScreen(),

          // Transcribe tab: only mount the page when active so that
          // its dispose() runs (releasing the camera) when user leaves the tab.
          if (idx == _transcribeIdx)
            const TranscribePage()
          else
            const SizedBox.shrink(),

          const SubscriptionPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade100.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: NavigationBar(
              backgroundColor: Colors.white,
              height: 64,
              elevation: 0,
              indicatorColor: const Color(0x334A90E2),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: idx,
              onDestinationSelected: _onTap,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'Lessons',
                ),
                NavigationDestination(
                  icon: Icon(Icons.mic_none_outlined),
                  selectedIcon: Icon(Icons.mic),
                  label: 'Transcribe',
                ),
                NavigationDestination(
                  icon: Icon(Icons.credit_card_outlined),
                  selectedIcon: Icon(Icons.credit_card),
                  label: 'Subscription',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}