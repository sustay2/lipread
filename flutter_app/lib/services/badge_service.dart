import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../common/theme/app_colors.dart';

class BadgeService {
  static final _db = FirebaseFirestore.instance;

  /// Run after XP updates, streak updates, lesson completions, etc.
  static Future<void> checkAll(String uid) async {
    try {
      final defsSnap = await _db.collection('badge_definitions').get();
      if (defsSnap.docs.isEmpty) return;

      final userBadgesRef =
      _db.collection('users').doc(uid).collection('badges');
      final ownedSnap = await userBadgesRef.get();

      final owned = ownedSnap.docs.map((d) => d.id).toSet();

      for (final def in defsSnap.docs) {
        final data = def.data();
        final id = def.id;
        if (owned.contains(id)) continue;

        final condition = data['condition'] as Map<String, dynamic>? ?? {};
        final condType = condition['type'];

        final ok = await _checkCondition(uid, condType, condition);
        if (!ok) continue;

        // Mark badge as earned
        await userBadgesRef.doc(id).set({
          'badgeId': id,
          'earnedAt': FieldValue.serverTimestamp(),
        });

        // Optional XP reward
        final reward = (data['xpReward'] as num?)?.toInt() ?? 0;
        if (reward > 0) {
          await _db.collection('users').doc(uid).update({
            'stats.xp': FieldValue.increment(reward),
          });
        }
      }
    } catch (e, st) {
      // Silent fail, but logged for debug
      // ignore: avoid_print
      print('BadgeService.checkAll failed: $e');
      // ignore: avoid_print
      print(st);
    }
  }

  // --------- CONDITION CHECKS ---------

  static Future<bool> _checkCondition(
      String uid,
      String? type,
      Map<String, dynamic> cond,
      ) async {
    if (type == null) return false;

    switch (type) {
      case 'xp':
        return _hasXp(uid, cond['threshold']);
      case 'level':
        return _hasLevel(uid, cond['threshold']);
      case 'lessons_completed':
        return _hasCompletedLessons(uid, cond['threshold']);
      case 'activities_completed':
        return _hasCompletedActivities(uid, cond['threshold']);
      case 'streak':
        return _hasStreak(uid, cond['threshold']);
      default:
        return false;
    }
  }

  static Future<bool> _hasXp(String uid, dynamic thresholdRaw) async {
    final threshold = (thresholdRaw as num?)?.toInt() ?? 0;
    final snap = await _db.collection('users').doc(uid).get();
    final xp = (snap.data()?['stats']?['xp'] as num?)?.toInt() ?? 0;
    return xp >= threshold;
  }

  static Future<bool> _hasLevel(String uid, dynamic thresholdRaw) async {
    final threshold = (thresholdRaw as num?)?.toInt() ?? 0;
    final snap = await _db.collection('users').doc(uid).get();
    final lvl = (snap.data()?['stats']?['level'] as num?)?.toInt() ?? 0;
    return lvl >= threshold;
  }

  static Future<bool> _hasCompletedLessons(
      String uid, dynamic thresholdRaw) async {
    final threshold = (thresholdRaw as num?)?.toInt() ?? 0;
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('enrollments')
        .get();

    int count = 0;
    for (final d in snap.docs) {
      final p = (d.data()['progress'] as num?)?.toDouble() ?? 0;
      if (p >= 100) count++;
    }
    return count >= threshold;
  }

  static Future<bool> _hasCompletedActivities(
      String uid, dynamic thresholdRaw) async {
    final threshold = (thresholdRaw as num?)?.toInt() ?? 0;
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .get();
    return snap.docs.length >= threshold;
  }

  static Future<bool> _hasStreak(String uid, dynamic thresholdRaw) async {
    final threshold = (thresholdRaw as num?)?.toInt() ?? 0;
    final snap = await _db.collection('users').doc(uid).get();
    final streak = (snap.data()?['streakCurrent'] as num?)?.toInt() ?? 0;
    return streak >= threshold;
  }

  // --------- POPUP UI (USED BY BadgeListener) ---------

  /// Show an animated badge popup for a given badgeId.
  /// Called from BadgeListener when a new /users/{uid}/badges/{badgeId} is created.
  static Future<void> showBadgePopup(
      BuildContext context,
      String badgeId,
      ) async {
    try {
      final defSnap =
      await _db.collection('badge_definitions').doc(badgeId).get();
      if (!defSnap.exists) return;

      final data = defSnap.data() ?? {};
      final title = (data['title'] as String?) ?? 'New badge';
      final description =
          (data['description'] as String?) ?? 'You unlocked a new badge.';
      final iconEmoji = (data['icon'] as String?) ?? '🏅';
      final xpReward = (data['xpReward'] as num?)?.toInt() ?? 0;
      final colorHex = (data['color'] as String?) ?? '#FFAA00';

      final color = _parseColor(colorHex, fallback: AppColors.primary);

      if (!context.mounted) return;

      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Badge',
        pageBuilder: (ctx, _, __) {
          return const SizedBox.shrink();
        },
        transitionDuration: const Duration(milliseconds: 260),
        transitionBuilder: (ctx, anim, secondary, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutBack,
          );

          return Stack(
            children: [
              // dim background
              Opacity(
                opacity: anim.value * 0.35,
                child: Container(
                    color: Theme.of(ctx).colorScheme.scrim),
              ),
              // badge card
              Center(
                child: ScaleTransition(
                  scale: curved,
                  child: _BadgePopupCard(
                    title: title,
                    description: description,
                    iconEmoji: iconEmoji,
                    xpReward: xpReward,
                    color: color,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      // ignore popup failures – don't crash gameplay
      // ignore: avoid_print
      print('showBadgePopup error: $e');
    }
  }

  static Color _parseColor(String hex, {required Color fallback}) {
    var v = hex.trim();
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 6) v = 'FF$v';
    try {
      final value = int.parse(v, radix: 16);
      return Color(value);
    } catch (_) {
      return fallback;
    }
  }
}

class _BadgePopupCard extends StatelessWidget {
  final String title;
  final String description;
  final String iconEmoji;
  final int xpReward;
  final Color color;

  const _BadgePopupCard({
    required this.title,
    required this.description,
    required this.iconEmoji,
    required this.xpReward,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.scrim.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    color.withOpacity(0.2),
                    color.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                iconEmoji,
                style: const TextStyle(fontSize: 34),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'New badge unlocked!',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (xpReward > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+$xpReward XP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Awesome!',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}