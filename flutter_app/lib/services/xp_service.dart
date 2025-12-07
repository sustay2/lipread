import 'package:cloud_firestore/cloud_firestore.dart';

class XpService {
  static final _users = FirebaseFirestore.instance.collection('users');

  static DocumentReference<Map<String, dynamic>> _streakRef(
    String uid,
    DateTime date,
  ) {
    return _users.doc(uid).collection('streaks').doc(_yearWeekKey(date));
  }

  /// Convert a date to a `yyyy-ww` bucket (ISO week number, padded).
  static String _yearWeekKey(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final firstMonday =
        DateTime.utc(d.year, 1, 1).subtract(Duration(days: DateTime.utc(d.year, 1, 1).weekday - 1));
    final diffWeeks = monday.difference(firstMonday).inDays ~/ 7;
    final week = diffWeeks + 1;
    return '${d.year}-${week.toString().padLeft(2, '0')}';
  }

  /// Formula: XP required to reach the next level
  /// Tweak this as you like.
  static int xpNeededForLevel(int level) {
    if (level <= 1) return 50;         // Level 1 → needs 50 XP
    return 50 + (level - 1) * 25;      // Level 2=75, 3=100, 4=125, etc.
  }

  /// Awards XP and handles leveling logic.
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

      final Map<String, dynamic> stats =
          Map<String, dynamic>.from(data['stats'] ?? {});

      int xp = (stats['xp'] as num?)?.toInt() ?? 0;
      int level = (stats['level'] as num?)?.toInt() ?? 1;
      int levelCur = (stats['levelCur'] as num?)?.toInt() ?? 0;
      int levelNeed =
          (stats['levelNeed'] as num?)?.toInt() ?? xpNeededForLevel(level);

      // Apply XP
      xp += delta;
      levelCur += delta;

      // Level-up loop
      while (levelCur >= levelNeed) {
        level++;
        levelCur -= levelNeed;
        levelNeed = xpNeededForLevel(level);
      }

      stats['xp'] = xp;
      stats['level'] = level;
      stats['levelCur'] = levelCur;
      stats['levelNeed'] = levelNeed;

      tx.set(ref, {'stats': stats}, SetOptions(merge: true));
    });

    await _writeXpHistory(
      uid,
      delta,
      reason: reason,
      metadata: metadata,
    );
  }

  /// Ensure a streak document exists for the current week.
  /// Creates it with `count=1` and `lastDayAt=now` if missing.
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

  /// Update the streak after an activity completion.
  /// - If the last hit was yesterday → increment.
  /// - If gap > 1 day → reset to 1.
  /// - If already counted today → keep current.
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
        if (diff == 0) {
          return streak; // already counted today
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

  /// Ensures stats exist when user signs in for the first time
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

  /// Award XP specifically for completing a daily task, with history logging.
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
      final historyRef = _users
          .doc(uid)
          .collection('xp_history')
          .doc();
      await historyRef.set({
        'delta': delta,
        'reason': reason ?? 'manual',
        'metadata': metadata ?? {},
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // history write is best-effort
    }
  }
}