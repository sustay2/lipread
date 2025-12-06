import 'package:cloud_firestore/cloud_firestore.dart';

import '../common/utils/level_utils.dart';
import 'badge_service.dart';
import 'daily_task_service.dart';

class HomeMetricsService {
  static final _db = FirebaseFirestore.instance;

  // -------- Streak --------

  /// Ensure the user's daily streak is up-to-date for *today*.
  /// Call this once after login / app open.
  static Future<void> ensureDailyStreak(String uid) async {
    await DailyTaskService.ensureStreakConsistency(uid);

    // Streak-based badges (e.g., 3-day, 7-day, 30-day)
    await BadgeService.checkAll(uid);
  }

  // -------- XP + LEVEL (lifetime + today) --------

  /// Increment user XP and recompute level server-side (in Firestore).
  ///
  /// Keeps:
  /// - stats.xp        (lifetime XP)
  /// - stats.xpToday   (XP earned today)
  /// - stats.xpTodayDate (date bucket for xpToday)
  /// - stats.level, stats.levelCur, stats.levelNeed (from Leveling.progress)
  static Future<void> addXp(String uid, int delta) async {
    if (delta == 0) return;

    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);

      // If user doc missing, create a minimal one so stats can be stored.
      if (!snap.exists) {
        tx.set(
          userRef,
          {
            'createdAt': Timestamp.now(),
            'stats': {
              'xp': 0,
              'xpToday': 0,
              'xpTodayDate': Timestamp.now(),
              'level': 0,
              'levelCur': 0,
              'levelNeed': 100,
            },
          },
          SetOptions(merge: true),
        );
      }

      final data = (snap.data() ?? {});
      final stats = (data['stats'] as Map<String, dynamic>?) ?? {};

      int xp = (stats['xp'] is num) ? (stats['xp'] as num).toInt() : 0;
      int xpToday =
      (stats['xpToday'] is num) ? (stats['xpToday'] as num).toInt() : 0;
      DateTime? xpTodayDate;

      if (stats['xpTodayDate'] is Timestamp) {
        final ts = stats['xpTodayDate'] as Timestamp;
        final d = ts.toDate().toUtc();
        xpTodayDate = DateTime.utc(d.year, d.month, d.day);
      }

      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);

      // New day → reset daily XP bucket
      if (xpTodayDate == null || xpTodayDate.isBefore(today)) {
        xpToday = 0;
      }

      // Apply XP delta (clamped to sane positive range)
      xp = (xp + delta).clamp(0, 1 << 31);
      xpToday = (xpToday + delta).clamp(0, 1 << 31);

      // Compute level from total XP via Leveling helper
      final progress = Leveling.progress(xp);
      // Leveling.progress must provide: level, cur, need

      final newStats = {
        ...stats,
        'xp': xp,
        'xpToday': xpToday,
        'xpTodayDate': Timestamp.fromDate(today),
        'level': progress.level,
        'levelCur': progress.cur,
        'levelNeed': progress.need,
      };

      tx.set(
        userRef,
        {
          'stats': newStats,
        },
        SetOptions(merge: true),
      );
    });

    // XP / level based badges (e.g., 100 XP, level 5, etc.)
    await BadgeService.checkAll(uid);
  }

  // -------- Enrollments --------

  /// Upsert enrollment for a course + update last lesson & progress.
  ///
  /// NOTE:
  /// - Does NOT hard-reset `startedAt` each time; only sets it if missing.
  static Future<void> updateEnrollmentProgress({
    required String uid,
    required String courseId,
    required String lastLessonId,
    required double progress, // 0-100
  }) async {
    final enrollRef =
    _db.collection('users').doc(uid).collection('enrollments').doc(courseId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(enrollRef);
      final now = FieldValue.serverTimestamp();
      final capped = progress.clamp(0, 100);

      Map<String, dynamic> existing = {};
      if (snap.exists && snap.data() != null) {
        existing = snap.data()!;
      }

      final startedAt = existing['startedAt'] ?? now;

      tx.set(
        enrollRef,
        {
          'courseId': courseId,
          'lastLessonId': lastLessonId,
          'progress': capped,
          'updatedAt': now,
          'startedAt': startedAt,
          'status': capped >= 100 ? 'completed' : 'in_progress',
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Convenience: call when the user opens a lesson from the UI.
  /// - nudges enrollment
  /// - nudges streak
  /// - may be used to drive "watch 1 lesson" tasks.
  static Future<void> markLessonVisited({
    required String uid,
    required String courseId,
    required String lessonId,
  }) async {
    await Future.wait([
      ensureDailyStreak(uid),
      updateEnrollmentProgress(
        uid: uid,
        courseId: courseId,
        lastLessonId: lessonId,
        progress: 5, // small nudge; you can tune or compute properly later
      ),
      onLessonWatched(uid),
    ]);

    // Lesson/progress-based badges (e.g., first course completed, etc.)
    await BadgeService.checkAll(uid);
  }

  // -------- Daily Tasks from global /user_tasks templates --------
  //
  // /user_tasks/{templateId}:
  //   title, action, points, frequency ("daily"/"weekly"), ...
  //
  // Per-user instances:
  //   /users/{uid}/tasks/{templateId}
  //   copied fields + completed:false
  //

  static Future<void> ensureDailyTasks(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final userTasksRef = userRef.collection('tasks');

    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);

    bool shouldGenerate = false;

    // Decide if we need to regenerate tasks for today
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      DateTime? lastGen;

      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        if (data['tasksLastGenerated'] is Timestamp) {
          final ts = data['tasksLastGenerated'] as Timestamp;
          final d = ts.toDate().toUtc();
          lastGen = DateTime.utc(d.year, d.month, d.day);
        }
      }

      if (lastGen == null || today.isAfter(lastGen)) {
        shouldGenerate = true;
        tx.set(
          userRef,
          {'tasksLastGenerated': Timestamp.fromDate(today)},
          SetOptions(merge: true),
        );
      }
    });

    if (!shouldGenerate) return;

    // 1) Clear previous DAILY tasks for this user.
    final oldDaily =
    await userTasksRef.where('frequency', isEqualTo: 'daily').get();
    if (oldDaily.docs.isNotEmpty) {
      final delBatch = _db.batch();
      for (final d in oldDaily.docs) {
        delBatch.delete(d.reference);
      }
      await delBatch.commit();
    }

    // 2) Load daily templates from /user_tasks.
    final templatesSnap =
    await _db.collection('user_tasks').where('frequency', isEqualTo: 'daily').get();

    if (templatesSnap.docs.isEmpty) {
      // No templates defined; nothing to generate.
      return;
    }

    // 3) Create per-user tasks based on templates.
    final batch = _db.batch();
    int order = 1;
    for (final tpl in templatesSnap.docs) {
      final data = tpl.data();
      final title = (data['title'] as String?) ?? 'Task';
      final action = (data['action'] as String?) ?? 'lessons';
      final points = (data['points'] as num?)?.toInt() ?? 0;
      final frequency = (data['frequency'] as String?) ?? 'daily';

      final userTaskRef = userTasksRef.doc(tpl.id);

      batch.set(userTaskRef, {
        'templateId': tpl.id,
        'title': title,
        'action': action,
        'points': points,
        'frequency': frequency,
        'completed': false,
        'order': order++,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // -------- Attempt & Task Integration --------

  /// Internal helper:
  /// Mark task (by templateId) as completed once for this user and
  /// award XP defined on the task.
  static Future<void> _completeTaskOnce({
    required String uid,
    required String templateId,
  }) async {
    final ref =
    _db.collection('users').doc(uid).collection('tasks').doc(templateId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;

      final data = snap.data()!;
      final completed = data['completed'] as bool? ?? false;
      if (completed) return;

      final points = (data['points'] as num?)?.toInt() ?? 0;

      tx.update(ref, {
        'completed': true,
        'completedAt': FieldValue.serverTimestamp(),
      });

      // Award XP outside the transaction (non-blocking)
      if (points > 0) {
        Future.microtask(() => addXp(uid, points));
      }
    });
  }

  /// Call when a lesson is watched / started (e.g. from LessonDetail).
  static Future<void> onLessonWatched(String uid) async {
    // Template ID must match a doc in /user_tasks (e.g. "watch_lesson").
    await _completeTaskOnce(uid: uid, templateId: 'watch_lesson');
  }

  /// Call when a practice activity is completed.
  static Future<void> onActivityCompleted(String uid) async {
    await _completeTaskOnce(uid: uid, templateId: 'complete_activity');
  }

  /// Call when a transcribe attempt is submitted.
  static Future<void> onAttemptSubmitted(String uid) async {
    await _completeTaskOnce(uid: uid, templateId: 'submit_attempt');
    // Add any weekly/aggregate task logic here later if needed.
  }

  /// Full attempt recording helper.
  ///
  /// Use this from your activity/transcribe screens:
  /// - Persists attempt under both:
  ///   /activities/.../attempts/{attemptId}
  ///   /users/{uid}/attempts/{attemptId}
  /// - Awards XP (scaled by score if you like)
  /// - Hooks into streak & daily tasks.
  static Future<void> recordActivityAttempt({
    required String uid,
    required String courseId,
    required String moduleId,
    required String lessonId,
    required String activityId,
    required String activityType,
    required double score, // 0-100 or 0-1, your choice
    required bool passed,
    int baseXp = 10,
  }) async {
    final now = DateTime.now();
    final attemptId = _db.collection('_').doc().id;

    final activityRef = _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .doc(activityId);

    final actAttemptRef = activityRef.collection('attempts').doc(attemptId);

    final userAttemptRef =
    _db.collection('users').doc(uid).collection('attempts').doc(attemptId);

    final payload = {
      'uid': uid,
      'courseId': courseId,
      'moduleId': moduleId,
      'lessonId': lessonId,
      'activityId': activityId,
      'activityType': activityType,
      'score': score,
      'passed': passed,
      'startedAt': Timestamp.fromDate(now), // if you track separately, adjust
      'finishedAt': Timestamp.fromDate(now),
      'createdAt': Timestamp.fromDate(now),
    };

    final batch = _db.batch();
    batch.set(actAttemptRef, payload);
    batch.set(userAttemptRef, payload);
    await batch.commit();

    // Simple XP rule: baseXp, with small bonus for high scores.
    final bonus =
    (score >= 90) ? 5 : (score >= 75) ? 2 : 0; // tune as needed
    await addXp(uid, baseXp + bonus);

    // Update related metrics/tasks.
    await Future.wait([
      ensureDailyStreak(uid),
      onActivityCompleted(uid),
      onAttemptSubmitted(uid),
    ]);

    // Attempts / completion-based badges (e.g., N activities completed)
    await BadgeService.checkAll(uid);
  }
}