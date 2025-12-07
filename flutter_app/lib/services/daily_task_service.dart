import 'dart:async';

import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'xp_service.dart';

class DailyTask {
  const DailyTask({
    required this.id,
    required this.title,
    required this.points,
    required this.frequency,
    required this.actionType,
    required this.actionCount,
    this.progress = 0,
    this.completed = false,
    this.completedAt,
  });

  final String id;
  final String title;
  final int points;
  final String frequency;
  final String actionType;
  final int actionCount;
  final int progress;
  final bool completed;
  final DateTime? completedAt;

  double get completionRatio =>
      actionCount > 0 ? (progress / actionCount).clamp(0.0, 1.0) : 0.0;
}

class DailyTaskService {
  static final _db = FirebaseFirestore.instance;

  static String _normalizeActionType(String key) {
    switch (key) {
      case 'complete_quiz':
        return 'quiz';
      case 'finish_practice':
        return 'practice';
      case 'complete_dictation':
        return 'dictation';
      default:
        return key;
    }
  }

  static String _dayKey(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
  }

  static String _weekKey(DateTime dt) {
    final utc = dt.toUtc();
    final weekday = utc.weekday == 0 ? 7 : utc.weekday;
    final thursday = utc.add(Duration(days: 4 - weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final weekNumber = 1 + ((thursday.difference(firstThursday).inDays) ~/ 7);
    return '${thursday.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }

  static String _periodKey(DateTime dt, String frequency) {
    if (frequency == 'weekly') {
      return _weekKey(dt);
    }
    return _dayKey(dt);
  }

  static DailyTask _taskFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc,
      Map<String, dynamic>? progressData, DateTime now) {
    final data = doc.data();
    final freq = (data['frequency'] as String?) ?? 'daily';
    final actionData = data['action'];
    String actionType;
    int actionCount;
    if (actionData is Map<String, dynamic>) {
      actionType = _normalizeActionType((actionData['type'] as String?) ?? '');
      actionCount = (actionData['count'] as num?)?.toInt() ?? 1;
    } else {
      actionType = _normalizeActionType((actionData?.toString() ?? ''));
      actionCount = 1;
    }
    final requiredCount = actionCount < 1 ? 1 : actionCount;
    final currentPeriod = _periodKey(now, freq);

    int progress = 0;
    bool completed = false;
    DateTime? completedAt;

    if (progressData != null && progressData['periodKey'] == currentPeriod) {
      progress = (progressData['progress'] as num?)?.toInt() ?? 0;
      completed = progressData['completed'] == true || progress >= requiredCount;
      if (progressData['completedAt'] is Timestamp) {
        completedAt = (progressData['completedAt'] as Timestamp).toDate().toUtc();
      }
    }

    return DailyTask(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Task',
      points: (data['points'] as num?)?.toInt() ?? 0,
      frequency: freq,
      actionType: actionType,
      actionCount: requiredCount,
      progress: progress,
      completed: completed,
      completedAt: completedAt,
    );
  }

  /// Stream global tasks merged with the user's progress for the active period
  /// (day or ISO week).
  static Stream<List<DailyTask>> watchTasksForUser(String uid) {
    final tasksStream = _db.collection('user_tasks').snapshots();
    final progressStream = _db
        .collection('users')
        .doc(uid)
        .collection('task_progress')
        .snapshots();

    return StreamZip([
      tasksStream,
      progressStream,
    ]).asyncMap((events) async {
      final taskSnap = events[0] as QuerySnapshot<Map<String, dynamic>>;
      final progressSnap = events[1] as QuerySnapshot<Map<String, dynamic>>;

      final progressById = <String, Map<String, dynamic>>{};
      final progressByAction = <String, Map<String, dynamic>>{};
      for (final doc in progressSnap.docs) {
        progressById[doc.id] = doc.data();
        final actionKey = (doc.data()['actionType'] as String?) ?? '';
        if (actionKey.isNotEmpty) {
          progressByAction[_normalizeActionType(actionKey)] = doc.data();
        }
      }

      final now = DateTime.now();
      return taskSnap.docs
          .map((doc) {
            final actionRaw = doc.data()['action'];
            String actionType;
            if (actionRaw is Map<String, dynamic>) {
              actionType =
                  _normalizeActionType((actionRaw['type'] as String?) ?? '');
            } else {
              actionType = _normalizeActionType((actionRaw?.toString() ?? ''));
            }

            final progressData =
                progressById[doc.id] ?? progressByAction[actionType];
            return _taskFromDoc(doc, progressData, now);
          })
          .toList();
    });
  }

  static Future<List<DailyTask>> _fetchTasksForAction(String actionType) async {
    final normalized = _normalizeActionType(actionType);
    final now = DateTime.now();

    QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('user_tasks')
        .where('action.type', isEqualTo: normalized)
        .get(const GetOptions());

    if (snap.docs.isEmpty) {
      snap = await _db
          .collection('user_tasks')
          .where('action', isEqualTo: normalized)
          .get(const GetOptions());
    }

    return snap.docs
        .map((doc) => _taskFromDoc(doc, null, now))
        .toList();
  }

  static Future<void> markTaskCompleted(String uid, String actionKey,
      {DailyTask? task}) async {
    final actionType = _normalizeActionType(actionKey);
    final tasks = task != null ? [task] : await _fetchTasksForAction(actionType);

    if (tasks.isEmpty && task == null) {
      await _updateStreakForCompletion(uid);
      return;
    }

    final now = DateTime.now();
    final userProgress = _db.collection('users').doc(uid).collection('task_progress');

    for (final resolved in tasks) {
      final requiredCount = resolved.actionCount <= 0 ? 1 : resolved.actionCount;
      final periodKey = _periodKey(now, resolved.frequency);
      final progressRef = userProgress.doc(resolved.id);
      bool awardXp = false;

      await _db.runTransaction((tx) async {
        final existing = await tx.get(progressRef);
        int progress = 0;
        bool alreadyCompleted = false;
        String existingPeriod = '';

        if (existing.exists) {
          final data = existing.data() as Map<String, dynamic>?;
          if (data != null) {
            existingPeriod = (data['periodKey'] as String?) ?? '';
            if (existingPeriod == periodKey) {
              progress = (data['progress'] as num?)?.toInt() ?? 0;
              alreadyCompleted = data['completed'] == true;
            }
          }
        }

        if (alreadyCompleted) {
          return;
        }

        if (existingPeriod != periodKey) {
          progress = 0;
        }

        progress += 1;
        final completed = progress >= requiredCount;

        final payload = {
          'periodKey': periodKey,
          'progress': progress,
          'completed': completed,
          'actionType': resolved.actionType,
          'frequency': resolved.frequency,
          'taskId': resolved.id,
          'taskTitle': resolved.title,
          'updatedAt': FieldValue.serverTimestamp(),
          'completedAt': completed ? FieldValue.serverTimestamp() : null,
        };

        if (completed) {
          awardXp = true;
        }

        tx.set(progressRef, payload, SetOptions(merge: true));
      });

      if (awardXp && resolved.points > 0) {
        await XpService.awardXPForTaskCompletion(
          uid,
          points: resolved.points,
          taskId: resolved.id,
          taskTitle: resolved.title,
        );
      }
    }

    await _updateStreakForCompletion(uid);
  }

  /// Ensure a streak record exists for the current week.
  static Future<void> ensureStreakConsistency(String uid) async {
    await XpService.ensureStreakForToday(uid);
  }

  static Future<void> _updateStreakForCompletion(String uid) async {
    await XpService.updateStreakAfterActivity(uid);
  }
}
