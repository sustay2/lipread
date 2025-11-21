import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/activities/quiz_activity_page.dart';

import '../../common/theme/app_colors.dart';
import '../../services/home_metrics_service.dart';
import '../../services/router.dart';

class LessonDetailScreen extends StatelessWidget {
  final String lessonId; // encoded: courseId|moduleId|lessonId

  const LessonDetailScreen({
    super.key,
    required this.lessonId,
  });

  @override
  Widget build(BuildContext context) {
    final parts = lessonId.split('|');
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

    final courseRef =
    FirebaseFirestore.instance.collection('courses').doc(courseId);
    final moduleRef = courseRef.collection('modules').doc(moduleId);
    final lessonRef =
    moduleRef.collection('lessons').doc(realLessonId);

    final activitiesQuery = lessonRef
        .collection('activities')
        .orderBy('order', descending: false);

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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: lessonRef.snapshots(),
        builder: (context, lessonSnap) {
          if (lessonSnap.hasError) {
            return const Center(
              child: Text(
                'Failed to load lesson.',
                style: TextStyle(color: AppColors.error),
              ),
            );
          }

          if (!lessonSnap.hasData ||
              !lessonSnap.data!.exists ||
              lessonSnap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final data = lessonSnap.data!.data()!;
          final lessonTitle =
              (data['title'] as String?) ?? 'Lesson';
          final objectives =
              (data['objectives'] as List?)?.cast<String>() ??
                  const <String>[];
          final estMin =
          (data['estimatedMin'] as num?)?.toInt();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: activitiesQuery.snapshots(),
            builder: (context, actSnap) {
              final acts = actSnap.data?.docs ?? [];

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: courseRef.snapshots(),
                builder: (context, courseSnap) {
                  String courseTitle = courseId;
                  if (courseSnap.hasData &&
                      courseSnap.data!.data() != null) {
                    courseTitle =
                        (courseSnap.data!.data()!['title']
                        as String?) ??
                            courseId;
                  }

                  return StreamBuilder<
                      DocumentSnapshot<Map<String, dynamic>>>(
                    stream: moduleRef.snapshots(),
                    builder: (context, moduleSnap) {
                      String moduleTitle = moduleId;
                      if (moduleSnap.hasData &&
                          moduleSnap.data!.data() != null) {
                        moduleTitle =
                            (moduleSnap.data!.data()!['title']
                            as String?) ??
                                moduleId;
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                            16, 8, 16, 24),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            // Header card
                            Container(
                              padding:
                              const EdgeInsets.all(16),
                              decoration: _cardDecor(),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lessonTitle,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight:
                                      FontWeight.w800,
                                      color: AppColors
                                          .textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Course pill (line 1)
                                  Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration:
                                    BoxDecoration(
                                      color: AppColors
                                          .background,
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                        999,
                                      ),
                                    ),
                                    child: Text(
                                      'Course: $courseTitle',
                                      style:
                                      const TextStyle(
                                        fontSize: 10,
                                        color: AppColors
                                            .textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  // Module pill (line 2)
                                  Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration:
                                    BoxDecoration(
                                      color: AppColors
                                          .background,
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                        999,
                                      ),
                                    ),
                                    child: Text(
                                      'Module: $moduleTitle',
                                      style:
                                      const TextStyle(
                                        fontSize: 10,
                                        color: AppColors
                                            .textSecondary,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  // Estimated time
                                  if (estMin != null)
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons
                                              .schedule_rounded,
                                          size: 14,
                                          color: AppColors
                                              .textSecondary,
                                        ),
                                        const SizedBox(
                                            width: 4),
                                        Text(
                                          '$estMin min',
                                          style:
                                          const TextStyle(
                                            fontSize: 11,
                                            color: AppColors
                                                .textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),

                                  if (objectives.isNotEmpty)
                                    const SizedBox(
                                        height: 12),
                                  if (objectives.isNotEmpty)
                                    Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        const Text(
                                          'Objectives',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight:
                                            FontWeight
                                                .w600,
                                            color: AppColors
                                                .textPrimary,
                                          ),
                                        ),
                                        const SizedBox(
                                            height: 4),
                                        ...objectives.map(
                                              (o) => Row(
                                            crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                            children: [
                                              const Text(
                                                '• ',
                                                style:
                                                TextStyle(
                                                  color: AppColors
                                                      .textSecondary,
                                                ),
                                              ),
                                              Expanded(
                                                child:
                                                Text(
                                                  o,
                                                  style:
                                                  const TextStyle(
                                                    fontSize:
                                                    12,
                                                    color: AppColors
                                                        .textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                  const SizedBox(height: 16),

                                  // Action buttons (fixed UX)
                                  Row(
                                    children: [
                                      Expanded(
                                        child:
                                        FilledButton
                                            .icon(
                                          onPressed:
                                          !hasUser
                                              ? null
                                              : () async {
                                            // Mark as watched / started
                                            await HomeMetricsService
                                                .onLessonWatched(
                                              uid!,
                                            );
                                            await HomeMetricsService
                                                .updateEnrollmentProgress(
                                              uid:
                                              uid,
                                              courseId:
                                              courseId,
                                              lastLessonId:
                                              lessonId,
                                              progress:
                                              10,
                                            );

                                            // Open first activity if any
                                            if (acts
                                                .isNotEmpty) {
                                              final a =
                                                  acts.first;
                                              _openActivity(
                                                context,
                                                courseId:
                                                courseId,
                                                moduleId:
                                                moduleId,
                                                lessonId:
                                                realLessonId,
                                                activityId:
                                                a.id,
                                                type: (a.data()['type'] as String?) ??
                                                    '',
                                              );
                                            }
                                          },
                                          icon:
                                          const Icon(
                                            Icons
                                                .play_arrow_rounded,
                                          ),
                                          label:
                                          const Text(
                                            'Start lesson',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                          width: 8),
                                      Expanded(
                                        child:
                                        OutlinedButton(
                                          onPressed:
                                          !hasUser
                                              ? null
                                              : () async {
                                            await HomeMetricsService
                                                .updateEnrollmentProgress(
                                              uid:
                                              uid!,
                                              courseId:
                                              courseId,
                                              lastLessonId:
                                              lessonId,
                                              progress:
                                              5,
                                            );
                                            ScaffoldMessenger.of(
                                                context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content:
                                                Text(
                                                  'Lesson saved to your progress.',
                                                ),
                                              ),
                                            );
                                          },
                                          style:
                                          OutlinedButton
                                              .styleFrom(
                                            padding:
                                            const EdgeInsets
                                              .symmetric(
                                                vertical:
                                                14,
                                              ),
                                          ),
                                          child:
                                          const Text(
                                            'Save for later',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Activities header
                            Row(
                              children: [
                                const Text(
                                  'Activities',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight:
                                    FontWeight
                                        .w700,
                                    color: AppColors
                                        .textPrimary,
                                  ),
                                ),
                                const SizedBox(
                                    width: 6),
                                if (acts.isNotEmpty)
                                  Container(
                                    padding:
                                    const EdgeInsets
                                        .symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration:
                                    BoxDecoration(
                                      color: AppColors
                                          .background,
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                          999),
                                    ),
                                    child: Text(
                                      '${acts.length} steps',
                                      style:
                                      const TextStyle(
                                        fontSize: 10,
                                        color: AppColors
                                            .textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Activities list
                            if (acts.isEmpty)
                              Container(
                                padding:
                                const EdgeInsets
                                    .all(16),
                                decoration:
                                _cardDecor(),
                                child: const Text(
                                  'No activities configured yet for this lesson.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors
                                        .textSecondary,
                                  ),
                                ),
                              )
                            else
                              Column(
                                children:
                                acts.map((a) {
                                  final ad =
                                  a.data();
                                  final type =
                                      (ad['type']
                                      as String?) ??
                                          'activity';
                                  final order =
                                      (ad['order']
                                      as num?)
                                          ?.toInt() ??
                                          0;
                                  final label =
                                      (ad['label']
                                      as String?) ??
                                          _labelForType(
                                              type);
                                  final duration =
                                  (ad['estimatedMin']
                                  as num?)
                                      ?.toInt();

                                  return Padding(
                                    padding:
                                    const EdgeInsets
                                        .only(
                                      bottom: 10,
                                    ),
                                    child:
                                    InkWell(
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                          16),
                                      onTap: !hasUser
                                          ? null
                                          : () {
                                        _openActivity(
                                          context,
                                          courseId:
                                          courseId,
                                          moduleId:
                                          moduleId,
                                          lessonId:
                                          realLessonId,
                                          activityId:
                                          a.id,
                                          type:
                                          type,
                                        );
                                      },
                                      child:
                                      Container(
                                        padding:
                                        const EdgeInsets
                                            .all(
                                            14),
                                        decoration:
                                        _cardDecor(),
                                        child: Row(
                                          children: [
                                            Container(
                                              width:
                                              40,
                                              height:
                                              40,
                                              decoration:
                                              BoxDecoration(
                                                color: AppColors
                                                    .background,
                                                borderRadius:
                                                BorderRadius.circular(12),
                                                border:
                                                Border.all(
                                                  color: AppColors
                                                      .border,
                                                ),
                                              ),
                                              child:
                                              Icon(
                                                _iconForType(
                                                    type),
                                                color: AppColors
                                                    .primaryVariant,
                                              ),
                                            ),
                                            const SizedBox(
                                                width:
                                                12),
                                            Expanded(
                                              child:
                                              Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Step $order · $label',
                                                    style:
                                                    const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  if (duration !=
                                                      null)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 2),
                                                      child: Text(
                                                        '$duration min',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: AppColors.textSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons
                                                  .chevron_right_rounded,
                                              color:
                                              AppColors.muted,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _labelForType(String type) {
    switch (type) {
      case 'video_drill':
        return 'Watch & repeat';
      case 'viseme_match':
        return 'Viseme match';
      case 'mirror_practice':
        return 'Mirror practice';
      case 'quiz':
        return 'Quick quiz';
      default:
        return 'Practice';
    }
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'video_drill':
        return Icons.play_circle_fill_rounded;
      case 'viseme_match':
        return Icons.grid_on_rounded;
      case 'mirror_practice':
        return Icons.flip_rounded;
      case 'quiz':
        return Icons.quiz_rounded;
      default:
        return Icons.task_alt_rounded;
    }
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

      default:
      // Fallback: send to transcribe with full context
        Navigator.pushNamed(
          context,
          Routes.transcribe,
          arguments: activityRef,
        );
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