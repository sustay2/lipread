import 'package:cloud_firestore/cloud_firestore.dart';

class XpService {
  static final _users = FirebaseFirestore.instance.collection('users');

  /// Formula: XP required to reach the next level
  /// Tweak this as you like.
  static int xpNeededForLevel(int level) {
    if (level <= 1) return 50;         // Level 1 → needs 50 XP
    return 50 + (level - 1) * 25;      // Level 2=75, 3=100, 4=125, etc.
  }

  /// Awards XP and handles leveling logic.
  static Future<void> awardXp(String uid, int delta) async {
    final ref = _users.doc(uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      Map<String, dynamic> stats =
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
}