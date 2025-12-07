import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';
import '../../services/daily_task_service.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    // If somehow opened while signed out
    if (_uid == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Please sign in to view your tasks.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final tasksQuery = DailyTaskService.watchTasksForUser(_uid!);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text('Tasks'),
      ),
      body: Column(
        children: [
          _XpSummary(uid: _uid!),
          Padding(
            padding:
            const EdgeInsets.only(top: 4, left: 16, right: 16, bottom: 4),
            child: Text(
              'Tasks are completed automatically as you learn.',
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<DailyTask>>( 
              stream: tasksQuery,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Failed to load tasks:\n${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final tasks = snap.data ?? [];
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text(
                      'No tasks for today.\nCome back later!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  );
                }

                // ---- Split into pending / completed ----
                final pending = tasks.where((t) => !t.completed).toList();
                final done = tasks.where((t) => t.completed).toList();

                final total = tasks.length;
                final completedCount = done.length;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    // Summary chip
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.flag_circle_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Completed $completedCount / $total tasks',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ------- Uncompleted section -------
                    _SectionLabel(title: 'To do', count: pending.length),
                    const SizedBox(height: 8),

                    if (pending.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Center(
                          child: Text(
                            'All tasks completed 🎉',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ..._tilesFromDocs(pending, completed: false),

                    // ------- Completed section (only if any) -------
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _SectionLabel(title: 'Completed', count: done.length),
                      const SizedBox(height: 8),
                      ..._tilesFromDocs(done, completed: true),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tilesFromDocs(
      List<DailyTask> docs, {
        required bool completed,
      }) {
    return List.generate(docs.length, (i) {
      final task = docs[i];
      final title = task.title;
      final points = task.points;
      final action = task.actionType;
      final freq = task.frequency;
      final progressLabel =
          task.actionCount > 1 ? ' (${task.progress}/${task.actionCount})' : '';

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Opacity(
          opacity: completed ? 0.45 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: completed ? AppColors.background : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: completed
                    ? AppColors.border.withOpacity(0.4)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: completed
                        ? AppColors.background
                        : AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    completed
                        ? Icons.check_circle_rounded
                        : _getActionIcon(action),
                    color: completed ? AppColors.success : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title + progressLabel,
                        style: TextStyle(
                          color: completed
                              ? AppColors.textSecondary.withOpacity(0.6)
                              : AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            freq.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _actionLabel(action),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '+$points XP',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'quiz':
        return Icons.quiz_rounded;
      case 'practice':
        return Icons.fitness_center_rounded;
      case 'dictation':
        return Icons.hearing_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'quiz':
        return 'Quiz';
      case 'practice':
        return 'Practice';
      case 'dictation':
        return 'Dictation';
      default:
        return action.isNotEmpty ? action : 'Task';
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final int count;
  const _SectionLabel({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '$count',
            style:
            const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _XpSummary extends StatelessWidget {
  final String uid;
  const _XpSummary({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
      FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        int xp = 0;
        int xpToday = 0;
        int level = 0;
        int levelCur = 0;
        int levelNeed = 100;

        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          final stats = (data['stats'] as Map<String, dynamic>?) ?? {};
          if (stats['xp'] is num) {
            xp = (stats['xp'] as num).toInt();
          }
          if (stats['xpToday'] is num) {
            xpToday = (stats['xpToday'] as num).toInt();
          }
          if (stats['level'] is num) {
            level = (stats['level'] as num).toInt();
          }
          if (stats['levelCur'] is num) {
            levelCur = (stats['levelCur'] as num).toInt();
          }
          if (stats['levelNeed'] is num) {
            levelNeed = (stats['levelNeed'] as num).toInt();
          }
        }

        final levelProgress = levelNeed > 0
            ? (levelCur / levelNeed).clamp(0.0, 1.0)
            : 0.0;

        const dailyGoal = 50;
        final dailyProgress =
        dailyGoal > 0 ? (xpToday / dailyGoal).clamp(0.0, 1.0) : 0.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Level row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.military_tech_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Level $level',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$levelCur / $levelNeed XP',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: levelProgress,
                    backgroundColor: AppColors.background,
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Today\'s progress',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: dailyProgress,
                    backgroundColor: AppColors.background,
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$xpToday XP today · $xp XP total',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}