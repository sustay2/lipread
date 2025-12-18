import 'package:cloud_firestore/cloud_firestore.dart';
import "package:flutter/foundation.dart";

class XpService {
  static final _users = FirebaseFirestore.instance.collection('users');

  static DocumentReference<Map<String, dynamic>> _streakRef(
    String uid,
    DateTime date,
  ) {
    return _users.doc(uid).collection('streaks').doc(_yearWeekKey(date));
  }

  static String _yearWeekKey(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final firstMonday =
        DateTime.utc(d.year, 1, 1).subtract(Duration(days: DateTime.utc(d.year, 1, 1).weekday - 1));
    final diffWeeks = monday.difference(firstMonday).inDays ~/ 7;
    final week = diffWeeks + 1;
    return '${d.year}-${week.toString().padLeft(2, '0')}';
  }

  static int xpNeededForLevel(int level) {
    if (level <= 1) return 50;
    return 50 + (level - 1) * 25;
  }

  // award XP
  static Future<void> awardXp(
    String uid,
    int delta, {
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    final ref = _users.doc(uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final existingStats = Map<String, dynamic>.from(data['stats'] ?? {});

      // --- BEGIN PROTECTED MERGE ---
      Map<String, dynamic> _protectStats(Map<String, dynamic> next) {
        final safe = Map<String, dynamic>.from(existingStats);

        next.forEach((key, value) {
          if (!existingStats.containsKey(key)) {
            // NEW field → allowed
            safe[key] = value;
            return;
          }

          final oldVal = existingStats[key];

          // If type changed → prevent overwrite
          if (oldVal != null &&
              value != null &&
              oldVal.runtimeType != value.runtimeType) {
            debugPrint(
              '🔥 XPService prevented type mismatch overwrite on stats.$key '
              '(${oldVal.runtimeType} → ${value.runtimeType})',
            );
            return;
          }

          // If field is null in new but existed before → prevent deletion
          if (oldVal != null && value == null) {
            debugPrint(
              '🔥 XPService prevented null overwrite on stats.$key (value preserved)',
            );
            return;
          }

          // Allowed update → overwrite
          safe[key] = value;
        });

        return safe;
      }
      // --- END PROTECTED MERGE ---

      // --- Load XP fields ---
      int xp = (existingStats['xp'] as num?)?.toInt() ?? 0;
      int level = (existingStats['level'] as num?)?.toInt() ?? 1;
      int levelCur = (existingStats['levelCur'] as num?)?.toInt() ?? 0;
      int levelNeed =
          (existingStats['levelNeed'] as num?)?.toInt() ?? xpNeededForLevel(level);

      // Apply XP
      xp += delta;
      levelCur += delta;

      // Level-up logic
      while (levelCur >= levelNeed) {
        level++;
        levelCur -= levelNeed;
        levelNeed = xpNeededForLevel(level);
      }

      // Proposed update (before protection)
      final proposedStats = {
        ...existingStats, // ensures future new stats remain safe
        'xp': xp,
        'level': level,
        'levelCur': levelCur,
        'levelNeed': levelNeed,
      };

      // Pass through overwrite protector
      final mergedStats = _protectStats(proposedStats);

      // Final write
      tx.set(ref, {'stats': mergedStats}, SetOptions(merge: true));
    });

    await _writeXpHistory(
      uid,
      delta,
      reason: reason,
      metadata: metadata,
    );
  }

  static Future<int> ensureStreakForToday(String uid) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final streakRef = _streakRef(uid, today);

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(streakRef);

      if (!snap.exists || snap.data() == null) {
        tx.set(
          streakRef,
          {
            'count': 1,
            'lastDayAt': Timestamp.fromDate(today),
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(
          _users.doc(uid),
          {
            'streakCurrent': 1,
            'streakLastHit': Timestamp.fromDate(today),
          },
          SetOptions(merge: true),
        );

        return 1;
      }

      final data = snap.data()!;
      final count = (data['count'] as num?)?.toInt() ?? 0;
      final ts = data['lastDayAt'] as Timestamp?;
      final lastDay = ts?.toDate().toUtc();
      final normalizedLast = lastDay == null
          ? null
          : DateTime.utc(lastDay.year, lastDay.month, lastDay.day);

      tx.set(
        _users.doc(uid),
        {
          'streakCurrent': count,
          'streakLastHit': Timestamp.fromDate(normalizedLast ?? today),
        },
        SetOptions(merge: true),
      );

      return count;
    });
  }

  static Future<int> updateStreakAfterActivity(String uid) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final userRef = _users.doc(uid);
    final todayRef = _streakRef(uid, today);

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);

      int streak = (userSnap.data()?['streakCurrent'] as num?)?.toInt() ?? 0;
      DateTime? lastDay;

      if (userSnap.data()?['streakLastHit'] is Timestamp) {
        final ts = userSnap.data()!['streakLastHit'] as Timestamp;
        final d = ts.toDate().toUtc();
        lastDay = DateTime.utc(d.year, d.month, d.day);
      }

      if (lastDay == null) {
        streak = 1;
      } else {
        final diff = today.difference(lastDay).inDays;
        if (diff == 0) return streak;
        if (diff == 1) streak += 1;
        else streak = 1;
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
        todayRef,
        {
          'count': streak,
          'lastDayAt': Timestamp.fromDate(today),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return streak;
    });
  }

  static Future<void> ensureStatsInitialized(String uid) async {
    final ref = _users.doc(uid);
    await ref.set({
      'stats': {
        'xp': 0,
        'level': 1,
        'levelCur': 0,
        'levelNeed': xpNeededForLevel(1),
      }
    }, SetOptions(merge: true));
  }

  static Future<void> awardXPForTaskCompletion(
    String uid, {
    required int points,
    required String taskId,
    required String taskTitle,
  }) async {
    await awardXp(
      uid,
      points,
      reason: 'task_completion',
      metadata: {
        'taskId': taskId,
        'taskTitle': taskTitle,
      },
    );
  }

  static Future<void> _writeXpHistory(
    String uid,
    int delta, {
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final historyRef = _users.doc(uid).collection('xp_history').doc();
      await historyRef.set({
        'delta': delta,
        'reason': reason ?? 'manual',
        'metadata': metadata ?? {},
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}