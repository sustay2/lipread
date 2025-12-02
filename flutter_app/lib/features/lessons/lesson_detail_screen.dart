import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';
import '../../models/content_models.dart';
import '../../services/content_api_service.dart';
import '../../services/home_metrics_service.dart';
import '../../services/router.dart';
import '../activities/quiz_activity_page.dart';

class _LessonBundle {
  final Course? course;
  final Module? module;
  final Lesson lesson;
  final List<ActivitySummary> activities;

  _LessonBundle({
    required this.course,
    required this.module,
    required this.lesson,
    required this.activities,
  });
}

class LessonDetailScreen extends StatefulWidget {
  final String lessonId; // encoded: courseId|moduleId|lessonId

  const LessonDetailScreen({
    super.key,
    required this.lessonId,
  });

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  final ContentApiService _contentApi = ContentApiService();

  Future<_LessonBundle>? _bundleFuture;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  Future<_LessonBundle> _loadBundle() async {
    final parts = widget.lessonId.split('|');
    if (parts.length != 3) {
      throw Exception('Invalid lesson reference');
    }
    final courseId = parts[0];
    final moduleId = parts[1];
    final lessonId = parts[2];

    final lesson = await _contentApi.fetchLessonById(courseId, moduleId, lessonId);
    if (lesson == null) {
      throw Exception('Lesson not found');
    }

    final course = await _contentApi.fetchCourseById(courseId);
    final module = await _contentApi.fetchModuleById(courseId, moduleId);
    final activities = await _contentApi.fetchActivities(courseId, moduleId, lessonId);

    return _LessonBundle(
      course: course,
      module: module,
      lesson: lesson,
      activities: activities,
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.lessonId.split('|');
    if (parts.length != 3) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lesson'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text('Invalid lesson reference'),
        ),
      );
    }

    final courseId = parts[0];
    final moduleId = parts[1];
    final realLessonId = parts[2];

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final hasUser = uid != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lesson details'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: FutureBuilder<_LessonBundle>(
        future: _bundleFuture,
        builder: (context, bundleSnap) {
          if (bundleSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load lesson.\n${bundleSnap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            );
          }

          if (bundleSnap.connectionState == ConnectionState.waiting ||
              !bundleSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final bundle = bundleSnap.data!;
          final lesson = bundle.lesson;
          final lessonTitle = lesson.title ?? 'Lesson';
          final objectives = lesson.objectives;
          final estMin = lesson.estimatedMin;
          final courseTitle = bundle.course?.title ?? courseId;
          final moduleTitle = bundle.module?.title ?? moduleId;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecor(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lessonTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Course: $courseTitle',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Module: $moduleTitle',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            estMin > 0 ? '$estMin minutes' : 'Self-paced',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (objectives.isNotEmpty) ...[
                        const Text(
                          'Objectives',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: objectives
                              .map((o) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('• ',
                                            style: TextStyle(
                                                color: AppColors.textSecondary)),
                                        Expanded(
                                          child: Text(
                                            o,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Activities',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (hasUser)
                      TextButton.icon(
                        onPressed: () => HomeMetricsService.onActivityCompleted(uid!),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Sync progress'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (bundle.activities.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: _cardDecor(),
                    child: const Text(
                      'No activities yet. Check back soon!',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  Column(
                    children: bundle.activities
                        .map(
                          (a) => _ActivityTile(
                            courseId: courseId,
                            moduleId: moduleId,
                            lessonId: realLessonId,
                            activity: a,
                            onTap: _openActivity,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openActivity(
    BuildContext context, {
    required String courseId,
    required String moduleId,
    required String lessonId,
    required String activityId,
    required String type,
  }) {
    final activityRef = '$courseId|$moduleId|$lessonId|$activityId';

    switch (type) {
      case 'video_drill':
        Navigator.pushNamed(
          context,
          Routes.videoDrill,
          arguments: activityRef,
        );
        break;

      case 'viseme_match':
        Navigator.pushNamed(
          context,
          Routes.visemeMatch,
          arguments: activityRef,
        );
        break;

      case 'mirror_practice':
        Navigator.pushNamed(
          context,
          Routes.mirrorPractice,
          arguments: activityRef,
        );
        break;

      case 'quiz':
        Navigator.pushNamed(
          context,
          Routes.quizActivity,
          arguments: QuizActivityArgs(
            courseId: courseId,
            moduleId: moduleId,
            lessonId: lessonId,
            activityId: activityId,
          ),
        );
        break;

      case 'dictation':
        Navigator.pushNamed(
          context,
          Routes.dictationActivity,
          arguments: activityRef,
        );
        break;

      case 'practice_lip':
        Navigator.pushNamed(
          context,
          Routes.practiceActivity,
          arguments: activityRef,
        );
        break;

      default:
        Navigator.pushNamed(
          context,
          Routes.transcribe,
          arguments: activityRef,
        );
    }
  }
}

class _ActivityTile extends StatelessWidget {
  final String courseId;
  final String moduleId;
  final String lessonId;
  final ActivitySummary activity;
  final void Function(
    BuildContext context, {
    required String courseId,
    required String moduleId,
    required String lessonId,
    required String activityId,
    required String type,
  }) onTap;

  const _ActivityTile({
    required this.courseId,
    required this.moduleId,
    required this.lessonId,
    required this.activity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle(activity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onTap(
          context,
          courseId: courseId,
          moduleId: moduleId,
          lessonId: lessonId,
          activityId: activity.id,
          type: activity.type,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecor(),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconFor(activity.type),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title ?? 'Activity',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'quiz':
        return Icons.quiz_outlined;
      case 'dictation':
        return Icons.library_music_outlined;
      case 'practice_lip':
        return Icons.mic_none_rounded;
      case 'video_drill':
        return Icons.play_circle_outline;
      default:
        return Icons.extension_outlined;
    }
  }

  String _subtitle(ActivitySummary a) {
    switch (a.type) {
      case 'quiz':
        return 'Quiz · ${a.itemCount} questions';
      case 'dictation':
        return 'Dictation · ${a.itemCount} prompts';
      case 'practice_lip':
        return 'Practice · ${a.itemCount} items';
      default:
        return a.config['description'] as String? ?? 'Activity';
    }
  }
}

BoxDecoration _cardDecor({double radius = 16}) {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: AppColors.softShadow,
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
