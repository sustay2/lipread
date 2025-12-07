import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../common/theme/app_colors.dart';
import '../../services/router.dart';
import '../../common/utils/media_utils.dart';
import '../../services/xp_service.dart';
import '../../services/daily_task_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _uid;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _enrollmentsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _publishedCoursesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _streakStream;
  Stream<List<DailyTask>>? _tasksStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid;

    if (_uid != null) {
      final userDoc =
      FirebaseFirestore.instance.collection('users').doc(_uid);

      _userDocStream = userDoc.snapshots();

      _enrollmentsStream = userDoc
          .collection('enrollments')
          .orderBy('updatedAt', descending: true)
          .snapshots();

      _streakStream = userDoc
          .collection('streaks')
          .orderBy('lastDayAt', descending: true)
          .limit(1)
          .snapshots();

      _tasksStream = DailyTaskService.watchTasksForUser(_uid!);

      // Ensure streak for today is in sync with latest completion.
      DailyTaskService.ensureStreakConsistency(_uid!);
    }

    _publishedCoursesStream =
        FirebaseFirestore.instance.collection('courses').snapshots();
  }

  // ---- Navigation helpers ----
  void _goLessons() => Navigator.pushNamed(context, Routes.lessons);
  void _goProfile() => Navigator.pushNamed(context, Routes.profile);

  void _goLessonDetail(String lessonId) {
    Navigator.pushNamed(
      context,
      Routes.lessonDetail,
      arguments: LessonDetailArgs(lessonId),
    );
  }

  void _goTranscribe([String? lessonId]) {
    Navigator.pushNamed(
      context,
      Routes.transcribe,
      arguments: lessonId,
    );
  }

  void _goTasks() => Navigator.pushNamed(context, Routes.tasks);

  // ---- Build ----
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.softShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Lip Learning',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (_uid != null) {
              await DailyTaskService.ensureStreakConsistency(_uid!);
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GreetingCard(
                  userStream: _userDocStream,
                  onProfile: _goProfile,
                ),
                const SizedBox(height: 16),
                _ContinueCard(
                  enrollmentsStream: _enrollmentsStream,
                  onResumeLesson: _goLessonDetail,
                  onBrowse: _goLessons,
                ),
                const SizedBox(height: 16),
                _StatsRow(
                  userStream: _userDocStream,
                  streakStream: _streakStream,
                ),
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Recommended for you',
                  onSeeAll: _goLessons,
                ),
                const SizedBox(height: 8),
                _RecommendedCourses(
                  enrollmentsStream: _enrollmentsStream,
                  coursesStream: _publishedCoursesStream,
                  onOpenCourse: (courseId) {
                    _goLessons();
                  },
                ),
                const SizedBox(height: 16),

                // Daily Tasks + See all inline
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daily Tasks',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: _goTasks,
                      child: const Text(
                        'See all',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DailyTasksList(
                  tasksStream: _tasksStream,
                  onQuickAction: (action) {
                    if (action == 'complete_dictation') _goTranscribe();
                    if (action == 'complete_quiz') _goLessons();
                    if (action == 'finish_practice') _goLessons();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//
// Greeting
//
class _GreetingCard extends StatelessWidget {
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;
  final VoidCallback onProfile;

  const _GreetingCard({
    required this.userStream,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.waving_hand_rounded,
                color: Theme.of(context).colorScheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userStream,
              builder: (context, snap) {
                String name = 'there';

                if (snap.hasData && snap.data!.data() != null) {
                  final d = snap.data!.data()!;
                  final rawName = d['displayName'] as String?;
                  if (rawName != null && rawName.trim().isNotEmpty) {
                    name = rawName.trim().split(' ').first;
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $name 👋',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ready to continue your practice?',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onProfile,
            icon: const Icon(
              Icons.person_outline,
              size: 18,
              color: AppColors.primaryVariant,
            ),
            label: const Text(
              'Profile',
              style: TextStyle(
                color: AppColors.primaryVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//
// Continue Learning (from enrollments)
//
class _ContinueCard extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>>? enrollmentsStream;
  final void Function(String lessonId) onResumeLesson;
  final VoidCallback onBrowse;

  const _ContinueCard({
    required this.enrollmentsStream,
    required this.onResumeLesson,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: enrollmentsStream,
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return _emptyState(theme);

          // Sort by updatedAt / startedAt desc
          docs.sort((a, b) {
            final aTs = a.data()['updatedAt'] ?? a.data()['startedAt'];
            final bTs = b.data()['updatedAt'] ?? b.data()['startedAt'];
            if (aTs is Timestamp && bTs is Timestamp) {
              return bTs.compareTo(aTs);
            }
            return 0;
          });

          final data = docs.first.data();
          final lastLessonId = (data['lastLessonId'] as String?) ?? '';
          final courseId = (data['courseId'] as String?) ?? docs.first.id;
          final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;

          return _ContinueCourseRow(
            courseId: courseId,
            lastLessonId: lastLessonId,
            progress: progress,
            onResumeLesson: onResumeLesson,
            onBrowse: onBrowse,
          );
        },
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.school_outlined,
              color: AppColors.primaryVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'No recent lesson. Start a course to begin your journey!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: onBrowse,
          child: const Text('Browse'),
        ),
      ],
    );
  }
}

/// Separate widget so we can lookup course title cleanly.
class _ContinueCourseRow extends StatelessWidget {
  final String courseId;
  final String lastLessonId;
  final double progress;
  final void Function(String lessonId) onResumeLesson;
  final VoidCallback onBrowse;

  const _ContinueCourseRow({
    required this.courseId,
    required this.lastLessonId,
    required this.progress,
    required this.onResumeLesson,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
      FirebaseFirestore.instance.collection('courses').doc(courseId).get(),
      builder: (context, courseSnap) {
        String courseTitle = courseId;
        if (courseSnap.hasData && courseSnap.data!.data() != null) {
          courseTitle =
              (courseSnap.data!.data()!['title'] as String?) ?? courseId;
        }

        final title = lastLessonId.isNotEmpty
            ? 'Pick up where you left off'
            : 'Continue your course';

        void handleTap() {
          if (lastLessonId.isNotEmpty) {
            onResumeLesson(lastLessonId);
          } else {
            onBrowse();
          }
        }

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: handleTap,
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Course: $courseTitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: (progress.clamp(0.0, 100.0)) / 100.0,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        );
      },
    );
  }
}

//
// Streak & XP
//
class _StatsRow extends StatelessWidget {
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? streakStream;

  const _StatsRow({
    required this.userStream,
    required this.streakStream,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StreakChip(
            streakStream: streakStream,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _XPChip(userStream: userStream),
        ),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>>? streakStream;

  const _StreakChip({
    required this.streakStream,
  });

  @override
  Widget build(BuildContext context) {
    if (streakStream == null) {
      return const _StatChip(
        icon: Icons.local_fire_department_rounded,
        label: 'Streak',
        value: '0 days',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: streakStream,
      builder: (context, streakSnap) {
        int streak = 0;

        if (streakSnap.hasData && streakSnap.data!.docs.isNotEmpty) {
          final data = streakSnap.data!.docs.first.data();
          streak = (data['count'] as num?)?.toInt() ?? 0;

          final ts = data['lastDayAt'] as Timestamp?;
          final lastDay = ts?.toDate().toUtc();
          if (lastDay != null) {
            final today = DateTime.now().toUtc();
            final todayDate = DateTime.utc(today.year, today.month, today.day);
            final lastDate =
                DateTime.utc(lastDay.year, lastDay.month, lastDay.day);
            final diff = todayDate.difference(lastDate).inDays;
            if (diff > 1) streak = 0;
          }
        }

        final label = streak == 1 ? '1 day' : '$streak days';

        return _StatChip(
          icon: Icons.local_fire_department_rounded,
          label: 'Streak',
          value: label,
        );
      },
    );
  }
}

class _XPChip extends StatelessWidget {
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;

  const _XPChip({required this.userStream});

  @override
  Widget build(BuildContext context) {
    if (userStream == null) {
      return const _StatChip(
        icon: Icons.star_border_rounded,
        label: 'XP',
        value: '0',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, snap) {
        int xp = 0;
        int level = 1;
        int cur = 0;
        int need = 0;

        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          Map<String, dynamic>? stats;

          if (data['stats'] is Map<String, dynamic>) {
            stats = data['stats'] as Map<String, dynamic>;
          }

          xp = (stats?['xp'] as num?)?.toInt() ??
              (data['xp'] as num?)?.toInt() ??
              0;

          level = (stats?['level'] as num?)?.toInt() ?? level;
          cur = (stats?['levelCur'] as num?)?.toInt() ?? cur;
          need = (stats?['levelNeed'] as num?)?.toInt() ?? need;
        }

        // Normalise using shared XP formula
        if (level <= 0) level = 1;
        if (need <= 0) {
          need = XpService.xpNeededForLevel(level);
        }
        if (cur < 0) cur = 0;
        if (cur > need) cur = need;
        if (xp < 0) xp = 0;

        final progress = need > 0 ? (cur / need).clamp(0.0, 1.0) : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: _cardDecor(),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.star_border_rounded,
                    color: AppColors.primaryVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level $level',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: progress,
                        backgroundColor: AppColors.background,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$cur / $need XP this level · $xp XP total',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: AppColors.textSecondary,
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
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: _cardDecor(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.primaryVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.muted,
            size: 18,
          ),
        ],
      ),
    );
  }
}

//
// Section header
//
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;

  const _SectionHeader({
    required this.title,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onSeeAll,
          child: const Text(
            'See all',
            style: TextStyle(
              color: AppColors.primaryVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

//
// Recommended courses
//
class _RecommendedCourses extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>>? enrollmentsStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? coursesStream;
  final void Function(String courseId) onOpenCourse;

  const _RecommendedCourses({
    required this.enrollmentsStream,
    required this.coursesStream,
    required this.onOpenCourse,
  });

  bool _isPublished(Map<String, dynamic> d) {
    final p = d['published'];
    final ip = d['isPublished'];
    if (p is bool) return p;
    if (ip is bool) return ip;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (coursesStream == null) return const _CourseSkeletonList();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: coursesStream,
      builder: (context, coursesSnap) {
        if (coursesSnap.hasError) {
          return const _EmptyCourses(message: 'Unable to load courses.');
        }

        if (!coursesSnap.hasData &&
            coursesSnap.connectionState == ConnectionState.waiting) {
          return const _CourseSkeletonList();
        }

        final rawCourses = coursesSnap.data?.docs ?? [];
        var filtered =
        rawCourses.where((doc) => _isPublished(doc.data())).toList();

        filtered.sort((a, b) {
          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          if (aTs is Timestamp && bTs is Timestamp) {
            return bTs.compareTo(aTs);
          }
          return 0;
        });

        if (filtered.isEmpty) return const _EmptyCourses();

        if (enrollmentsStream != null) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: enrollmentsStream,
            builder: (context, enrollSnap) {
              final enrolledIds = <String>{};
              if (enrollSnap.hasData) {
                for (final e in enrollSnap.data!.docs) {
                  enrolledIds.add(e.id);
                }
              }

              final recommended =
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              for (final c in filtered) {
                if (enrolledIds.contains(c.id)) recommended.add(c);
              }
              for (final c in filtered) {
                if (!enrolledIds.contains(c.id)) recommended.add(c);
              }

              if (recommended.isEmpty) return const _EmptyCourses();

              return _RecommendedCoursesList(
                courses: recommended,
                onOpenCourse: onOpenCourse,
              );
            },
          );
        }

        return _RecommendedCoursesList(
          courses: filtered,
          onOpenCourse: onOpenCourse,
        );
      },
    );
  }
}

class _RecommendedCoursesList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> courses;
  final void Function(String courseId) onOpenCourse;

  const _RecommendedCoursesList({
    required this.courses,
    required this.onOpenCourse,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4),
        itemCount: courses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final doc = courses[i];
          final d = doc.data();
          final title = (d['title'] as String?) ?? 'Untitled course';
          final level = (d['level'] as String?) ?? 'Beginner';

          return _CourseCard(
            courseId: doc.id,
            title: title,
            level: level,
            data: d,
            onTap: () => onOpenCourse(doc.id),
          );
        },
      ),
    );
  }
}

class _CourseSkeletonList extends StatelessWidget {
  const _CourseSkeletonList();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => _skeletonCard(),
      ),
    );
  }

  Widget _skeletonCard() {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: _cardDecor(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // fixed height + full width frame to match thumbnails
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF7),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 16, width: 160, decoration: _shimmerBox()),
          const SizedBox(height: 6),
          Container(height: 14, width: 80, decoration: _shimmerBox()),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final String courseId;
  final String title;
  final String level;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _CourseCard({
    required this.courseId,
    required this.title,
    required this.level,
    required this.data,
    required this.onTap,
  });

  Future<_ResolvedMedia?> _resolveMedia() async {
    // 1) Direct string field
    final direct = (data['thumbnailUrl'] as String?) ?? (data['thumbUrl'] as String?) ?? (data['coverImageUrl'] as String?);
    if (direct != null && direct.isNotEmpty) {
      final url = normalizeMediaUrl(direct);
      return _ResolvedMedia(url: url, isVideo: _looksVideo(url));
    }

    // 2) Map with `url` (+ optional contentType/kind)
    if (data['thumbnail'] is Map<String, dynamic>) {
      final m = (data['thumbnail'] as Map<String, dynamic>);
      final url = normalizeMediaUrl(m['url'] as String?);
      final ct = (m['contentType'] as String?)?.toLowerCase();
      final kind = (m['kind'] as String?)?.toLowerCase();
      if (url != null && url.isNotEmpty) {
        final isVid = (ct?.startsWith('video/') ?? false) ||
            kind == 'video' ||
            _looksVideo(url);
        return _ResolvedMedia(url: url, isVideo: isVid);
      }
    }

    // 3) Media doc reference
    final mediaId = (data['mediaId'] as String?) ?? (data['coverImageId'] as String?);
    if (mediaId != null && mediaId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('media')
            .doc(mediaId)
            .get();
        if (snap.exists) {
          final m = snap.data() ?? {};
          final url = normalizeMediaUrl(m['url'] as String?);
          final ct = (m['contentType'] as String?)?.toLowerCase();
          final kind = (m['kind'] as String?)?.toLowerCase();
          if (url != null && url.isNotEmpty) {
            final isVid = (ct?.startsWith('video/') ?? false) ||
                kind == 'video' ||
                _looksVideo(url);
            return _ResolvedMedia(url: url, isVideo: isVid);
          }
        }
      } catch (_) {/* ignore */}
    }

    return null;
  }

  static bool _looksVideo(String? url) {
    if (url == null) return false;
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv') ||
        lower.contains('/videos/');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: _cardDecor(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<_ResolvedMedia?>(
              future: _resolveMedia(),
              builder: (context, snap) {
                final media = snap.data;

                if (snap.connectionState == ConnectionState.waiting &&
                    media == null) {
                  return Container(
                    height: 90,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                  );
                }

                if (media == null ||
                    media.url == null ||
                    media.url!.isEmpty) {
                  return const _ThumbPlaceholder();
                }

                if (media.isVideo) {
                  return _CourseVideoThumb(url: media.url!);
                } else {
                  return _CourseImageThumb(url: media.url!);
                }
              },
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.layers_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(level,
                    style:
                    const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Image thumbnails: fixed height (90), full width, centered letterbox
class _CourseImageThumb extends StatelessWidget {
  final String url;
  const _CourseImageThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FittedBox(
          fit: BoxFit.contain, // keep AR; blank padding if needed
          alignment: Alignment.center,
          child: Image.network(url),
        ),
      ),
    );
  }
}

/// Video thumbnails: fixed height (90), full width, centered letterbox,
/// tap to play/pause, play icon hides while playing, and a progress bar.
class _CourseVideoThumb extends StatefulWidget {
  final String url;
  const _CourseVideoThumb({required this.url});

  @override
  State<_CourseVideoThumb> createState() => _CourseVideoThumbState();
}

class _CourseVideoThumbState extends State<_CourseVideoThumb> {
  VideoPlayerController? _ctrl;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _ctrl = c;

      await c.initialize();
      if (!mounted) return;

      await c.setLooping(false);
      setState(() {}); // show first frame
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;

    final v = c.value;

    // If ended, restart
    if (v.position >=
            (v.duration ?? Duration.zero) -
                const Duration(milliseconds: 50)) {
      await c.seekTo(Duration.zero);
    }

    if (v.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  Widget _frame(Widget child) {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_err) {
      return _frame(
        const Center(
          child: Text(
            'Video failed to load',
            style: TextStyle(fontSize: 11, color: AppColors.error),
          ),
        ),
      );
    }

    final c = _ctrl;
    if (c == null || !c.value.isInitialized) {
      return _frame(
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Use ValueListenableBuilder so play icon + progress update without manual setState calls
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, v, _) {
        final ar =
        (v.aspectRatio.isFinite && v.aspectRatio > 0) ? v.aspectRatio : 16 / 9;

        // Determine overlay icon visibility
        final bool ended = (v.duration != null) &&
            (v.position >=
                (v.duration ?? Duration.zero) -
                    const Duration(milliseconds: 50));
        final bool showPlay =
            !(v.isPlaying && !v.isBuffering) || ended;

        // Progress 0..1
        double progress = 0;
        if (v.duration.inMilliseconds > 0) {
          progress = (v.position.inMilliseconds /
              v.duration.inMilliseconds)
              .clamp(0.0, 1.0);
        }

        return _frame(
          Stack(
            children: [
              // Tap area + letterboxed video centered
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain, // keep bars (letterbox)
                      alignment: Alignment.center,
                      child: SizedBox(
                        height: 90,
                        width: 90 * ar,
                        child: VideoPlayer(c),
                      ),
                    ),
                  ),
                ),
              ),

              // Play button (fade in/out)
              IgnorePointer(
                ignoring: true,
                child: AnimatedOpacity(
                  opacity: showPlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  child: Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 36,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),

              // Thin progress bar at bottom (always visible once initialized)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 2.5,
                  color: AppColors.background.withOpacity(0.65),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.isNaN ? 0.0 : progress,
                    child: Container(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: AppColors.muted,
          size: 36,
        ),
      ),
    );
  }
}

class _ResolvedMedia {
  final String? url;
  final bool isVideo;
  const _ResolvedMedia({required this.url, required this.isVideo});
}

class _EmptyCourses extends StatelessWidget {
  final String message;
  const _EmptyCourses({
    this.message = 'No courses yet. Check back soon!',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 150,
      alignment: Alignment.center,
      decoration: _cardDecor(),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

//
// Daily tasks (from /users/{uid}/tasks) — show only incomplete (client-side)
//
class _DailyTasksList extends StatelessWidget {
  final Stream<List<DailyTask>>? tasksStream;
  final void Function(String action) onQuickAction;

  const _DailyTasksList({
    required this.tasksStream,
    required this.onQuickAction,
  });

  @override
  Widget build(BuildContext context) {
    if (tasksStream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<DailyTask>>(
      stream: tasksStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox.shrink();
        }

        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return Column(
            children: List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: _cardDecor(),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: _shimmerBox(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 14,
                          decoration: _shimmerBox(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final tasks = snap.data ?? [];
        final pending = tasks.where((t) => !t.completed).toList();

        if (pending.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _cardDecor(),
            child: const Center(
              child: Text(
                'All tasks completed 🎉',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }

        return Column(
          children: pending.map((task) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onQuickAction(task.action),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: _cardDecor(),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.border,
                          ),
                        ),
                        child: Icon(
                          _taskIconForAction(task.action),
                          color: AppColors.primaryVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${task.points} XP',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static IconData _taskIconForAction(String action) {
    switch (action) {
      case 'complete_quiz':
        return Icons.quiz_rounded;
      case 'finish_practice':
        return Icons.fitness_center_rounded;
      case 'complete_dictation':
        return Icons.hearing_rounded;
      default:
        return Icons.flag_rounded;
    }
  }
}

//
// Shared helpers
//
BoxDecoration _cardDecor({double radius = 16}) {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: AppColors.softShadow,
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

BoxDecoration _shimmerBox() {
  return BoxDecoration(
    color: const Color(0xFFE9EEF7),
    borderRadius: BorderRadius.circular(10),
  );
}