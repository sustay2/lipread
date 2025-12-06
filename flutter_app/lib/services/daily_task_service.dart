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
    required this.action,
    this.completed = false,
    this.completedAt,
  });

  final String id;
  final String title;
  final int points;
  final String frequency;
  final String action;
  final bool completed;
  final DateTime? completedAt;
}

class DailyTaskService {
  static final _db = FirebaseFirestore.instance;

  static String _dayKey(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
  }

  /// Stream global tasks merged with the user's completion status for today.
  static Stream<List<DailyTask>> watchTasksForUser(String uid) {
    final tasksStream = _db.collection('user_tasks').snapshots();
    final completionsStream = _db
        .collection('users')
        .doc(uid)
        .collection('completed_tasks')
        .snapshots();

    return StreamZip([
      tasksStream,
      completionsStream,
    ]).asyncMap((events) async {
      final taskSnap = events[0] as QuerySnapshot<Map<String, dynamic>>;
      final completionSnap = events[1] as QuerySnapshot<Map<String, dynamic>>;

      final todayKey = _dayKey(DateTime.now());
      final completedMap = <String, Map<String, dynamic>>{};
      for (final doc in completionSnap.docs) {
        final data = doc.data();
        if (data['dayKey'] == todayKey) {
          completedMap[doc.id] = data;
        }
      }

      return taskSnap.docs.map((doc) {
        final data = doc.data();
        final completed = completedMap.containsKey(doc.id);
        final completedAt = completedMap[doc.id]?['completedAt'] is Timestamp
            ? (completedMap[doc.id]!['completedAt'] as Timestamp)
                .toDate()
                .toUtc()
            : null;

        return DailyTask(
          id: doc.id,
          title: (data['title'] as String?) ?? 'Task',
          points: (data['points'] as num?)?.toInt() ?? 0,
          frequency: (data['frequency'] as String?) ?? 'daily',
          action: (data['action'] as String?) ?? '',
          completed: completed,
          completedAt: completedAt,
        );
      }).toList();
    });
  }

  static Future<DailyTask?> _fetchTask(String taskId) async {
    final doc =
        await _db.collection('user_tasks').doc(taskId).get(const GetOptions());
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    return DailyTask(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Task',
      points: (data['points'] as num?)?.toInt() ?? 0,
      frequency: (data['frequency'] as String?) ?? 'daily',
      action: (data['action'] as String?) ?? '',
    );
  }

  /// Mark task completed for today (UTC) and award XP/streak updates.
  static Future<void> markTaskCompleted(String uid, String taskId,
      {DailyTask? task}) async {
    final dayKey = _dayKey(DateTime.now());
    final completionRef =
        _db.collection('users').doc(uid).collection('completed_tasks').doc(
              taskId,
            );

    await _db.runTransaction((tx) async {
      final existing = await tx.get(completionRef);
      if (existing.exists) {
        final data = existing.data();
        if (data != null && data['dayKey'] == dayKey) {
          return; // already marked today
        }
      }

      DailyTask? resolved = task;
      resolved ??= await _fetchTask(taskId);
      resolved ??= DailyTask(
        id: taskId,
        title: 'Daily task',
        points: 5,
        frequency: 'daily',
        action: 'complete',
      );

      tx.set(completionRef, {
        'taskId': taskId,
        'title': resolved.title,
        'points': resolved.points,
        'action': resolved.action,
        'dayKey': dayKey,
        'completedAt': FieldValue.serverTimestamp(),
      });
    });

    final resolvedTask = task ?? await _fetchTask(taskId);
    if (resolvedTask != null && resolvedTask.points > 0) {
      await XpService.awardXPForTaskCompletion(
        uid,
        points: resolvedTask.points,
        taskId: resolvedTask.id,
        taskTitle: resolvedTask.title,
      );
    }

    await _updateStreakForCompletion(uid);
  }

  /// Reset streak if the user missed a day.
  static Future<void> ensureStreakConsistency(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final snap = await userRef.get(const GetOptions());
    final data = snap.data() ?? {};
    Timestamp? lastTs;
    if (data['streakLastHit'] is Timestamp) {
      lastTs = data['streakLastHit'] as Timestamp;
    }
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    if (lastTs == null) {
      await userRef.set({
        'streakCurrent': 0,
      }, SetOptions(merge: true));
      return;
    }
    final last = lastTs.toDate().toUtc();
    final lastDay = DateTime.utc(last.year, last.month, last.day);
    final diff = today.difference(lastDay).inDays;
    if (diff > 1) {
      await userRef.set({
        'streakCurrent': 0,
      }, SetOptions(merge: true));
    }
  }

  static Future<void> _updateStreakForCompletion(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final streakRef = userRef
        .collection('streaks')
        .doc(_dayKey(DateTime.now()));

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      int streak = 0;
      DateTime? lastDay;
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        if (data['streakCurrent'] is num) {
          streak = (data['streakCurrent'] as num).toInt();
        }
        if (data['streakLastHit'] is Timestamp) {
          final ts = data['streakLastHit'] as Timestamp;
          final d = ts.toDate().toUtc();
          lastDay = DateTime.utc(d.year, d.month, d.day);
        }
      }

      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);

      if (lastDay == null) {
        streak = 1;
      } else {
        final diff = today.difference(lastDay).inDays;
        if (diff == 0) {
          // already counted today
          return;
        } else if (diff == 1) {
          streak += 1;
        } else {
          streak = 1;
        }
      }

      tx.set(
        userRef,
        {
          'streakCurrent': streak,
          'streakLastHit': Timestamp.fromDate(today),
        },
        SetOptions(merge: true),
      );
      tx.set(
        streakRef,
        {
          'streak': streak,
          'lastDayAt': Timestamp.fromDate(today),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
