import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/lessons/lesson_list_screen.dart';
import '../../features/transcribe/transcribe_page.dart';
import '../../features/results/results_screen.dart';
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
  static const int _resultsIdx = 3;
  static const int _profileIdx = 4;

  int _localIndex = _homeIdx;
  int get _index => widget.navigationShell?.currentIndex ?? _localIndex;

  final _persistentPages = const [
    HomeScreen(),
    LessonListScreen(),
    TranscribePage(),
    ResultsScreen(),
    ProfilePage(),
  ];

  void _onTap(int i) {
    if (widget.navigationShell != null) {
      widget.navigationShell!.goBranch(
        i,
        initialLocation: i == widget.navigationShell!.currentIndex,
      );
    } else {
      setState(() => _localIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FD),
      body: IndexedStack(index: _index, children: _persistentPages),
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
              selectedIndex: _index,
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
                  icon: Icon(Icons.article_outlined),
                  selectedIcon: Icon(Icons.article),
                  label: 'Results',
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
