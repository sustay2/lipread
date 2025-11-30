import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';
import '../../services/router.dart';
import '../../common/utils/media_utils.dart';
import '../../services/xp_service.dart';
import 'all_badges_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'You are not signed in.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final userId = uid;

    final userDocStream =
    FirebaseFirestore.instance.collection('users').doc(userId).snapshots();

    final badgesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('badges')
        .orderBy('earnedAt', descending: true)
        .snapshots();

    final streaksStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('streaks')
        .orderBy('lastDayAt', descending: true)
        .limit(1)
        .snapshots();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text('Profile'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};

          final displayName =
              (data['displayName'] as String?) ?? user?.email ?? 'Learner';
          final email = (data['email'] as String?) ?? (user?.email ?? '');
          final rawPhoto = (data['photoURL'] as String?) ?? user?.photoURL;

          // ---- XP / LEVEL (now using XpService) ----
          Map<String, dynamic>? stats;
          if (data['stats'] is Map<String, dynamic>) {
            stats = data['stats'] as Map<String, dynamic>;
          }

          // match home_screen.dart _XPChip style
          int xp = (stats?['xp'] as num?)?.toInt() ??
              (data['xp'] as num?)?.toInt() ??
              0;

          int level = (stats?['level'] as num?)?.toInt() ?? 0;
          int levelCur = (stats?['levelCur'] as num?)?.toInt() ?? 0;
          int levelNeed = (stats?['levelNeed'] as num?)?.toInt() ?? 0;

          final streak = (data['streakCurrent'] as num?)?.toInt() ?? 0;

          // sane defaults + XP formula from XpService
          if (level <= 0) level = 1;
          if (levelNeed <= 0) {
            levelNeed = XpService.xpNeededForLevel(level);
          }
          if (levelCur < 0) levelCur = 0;
          if (levelCur > levelNeed) levelCur = levelNeed;
          if (xp < 0) xp = 0;

          final double levelProgress =
          levelNeed > 0 ? (levelCur / levelNeed).clamp(0.0, 1.0) : 0.0;
          final int xpToNext =
          (levelNeed - levelCur) <= 0 ? 0 : (levelNeed - levelCur);

          // ---- Preferences ----
          final settings = (data['settings'] as Map<String, dynamic>?) ?? {};
          final locale = (data['locale'] as String?) ?? 'en';
          final themePref = (settings['theme'] as String?) ?? 'system';

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecor(),
                  child: Row(
                    children: [
                      _Avatar(photoUrl: rawPhoto, name: displayName),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                side: const BorderSide(
                                  color: AppColors.primary,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                Routes.profileAccount,
                              ),
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              label: const Text(
                                'Account settings',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // LEVEL CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecor(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              children: [
                                const Icon(
                                  Icons.military_tech_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Level $level',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$levelCur / $levelNeed XP',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: levelProgress,
                          minHeight: 6,
                          backgroundColor: AppColors.background,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$xpToNext XP to next level',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // STREAK + XP
                Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: streaksStream,
                        builder: (context, streakSnap) {
                          int latestStreak = streak;

                          if (streakSnap.hasData &&
                              streakSnap.data!.docs.isNotEmpty) {
                            final data = streakSnap.data!.docs.first.data();
                            latestStreak =
                                (data['count'] as num?)?.toInt() ?? latestStreak;
                          }

                          final label =
                              latestStreak == 1 ? '1 day' : '$latestStreak days';

                          return _StatCard(
                            icon: Icons.local_fire_department_rounded,
                            label: 'Streak',
                            value: label,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.star_border_rounded,
                        label: 'Total XP',
                        value: xp.toString(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // BADGES SECTION
                Row(
                  children: [
                    Text(
                      'Badges',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AllBadgesPage(uid: userId),
                          ),
                        );
                      },
                      child: const Text(
                        'View all',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: badgesStream,
                  builder: (context, badgeSnap) {
                    if (badgeSnap.hasError) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecor(),
                        child: Text(
                          'Failed to load badges:\n${badgeSnap.error}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      );
                    }

                    if (!badgeSnap.hasData) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecor(),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final earnedDocs = badgeSnap.data!.docs;
                    final earnedCount = earnedDocs.length;

                    if (earnedDocs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecor(),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.emoji_events_outlined,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No badges earned yet.\nComplete lessons and activities to unlock your first badge!',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final toShow = earnedDocs.take(6).toList();

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecor(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$earnedCount badge${earnedCount == 1 ? '' : 's'} earned',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 160,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(right: 4),
                              itemCount: toShow.length,
                              separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                return _EarnedBadgePreview(
                                  earned: toShow[index],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // ACTIONS
                Text(
                  'Actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: _cardDecor(),
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: Icons.person_outline,
                        label: 'Edit account details',
                        onTap: () => Navigator.pushNamed(
                          context,
                          Routes.profileAccount,
                        ),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.4,
                        color: AppColors.border,
                      ),
                      _ActionTile(
                        icon: Icons.logout_rounded,
                        label: 'Sign out',
                        danger: true,
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Sign out'),
                              content: const Text(
                                  'Are you sure you want to sign out?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Sign out'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;

                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) {
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              Routes.login,
                                  (r) => false,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Small widget that takes an earned-badge doc and looks up the
/// definition from `badge_definitions/{badgeDefinitionId}`.
class _EarnedBadgePreview extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> earned;

  const _EarnedBadgePreview({required this.earned});

  @override
  Widget build(BuildContext context) {
    final data = earned.data();

    final defId = (data['badgeDefinitionId'] as String?) ??
        (data['badgeId'] as String?) ??
        earned.id;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('badge_definitions')
          .doc(defId)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return Container(
            width: 120,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          final fallbackName =
              (data['name'] as String?) ?? defId ?? 'Badge';
          final fallbackDesc =
              (data['description'] as String?) ?? 'Badge earned';
          final earnedXp = (data['xp'] as num?)?.toInt() ?? 0;
          return _MiniBadgeChip(
            iconRaw: '',
            fallbackEmoji: '🏆',
            label: fallbackName,
            description: fallbackDesc,
            xp: earnedXp,
          );
        }

        final def = snap.data!.data() ?? {};
        final title =
            (def['title'] as String?) ?? (def['name'] as String?) ?? defId;
        final desc = (def['description'] as String?) ?? '';
        final iconPath = (def['icon'] as String?) ?? '';
        final xpReward =
            (def['xpReward'] as num?)?.toInt() ??
                (def['xp'] as num?)?.toInt() ??
                0;

        return _MiniBadgeChip(
          iconRaw: iconPath,
          fallbackEmoji: '🏆',
          label: title,
          description: desc,
          xp: xpReward,
        );
      },
    );
  }
}

/// Compact chip used only on the profile page to preview earned badges.
class _MiniBadgeChip extends StatelessWidget {
  final String iconRaw;       // could be media path or empty
  final String fallbackEmoji; // used if iconRaw is not media
  final String label;
  final String description;
  final int xp;

  const _MiniBadgeChip({
    required this.iconRaw,
    required this.fallbackEmoji,
    required this.label,
    required this.description,
    required this.xp,
  });

  bool _looksLikeMedia(String s) {
    return s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.contains('/') ||
        s.contains('.');
  }

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;

    if (iconRaw.isNotEmpty && _looksLikeMedia(iconRaw)) {
      final isAbsolute =
          iconRaw.startsWith('http://') || iconRaw.startsWith('https://');
      final full = publicMediaUrl(
        isAbsolute ? iconRaw : null,
        path: isAbsolute ? null : iconRaw,
      );

      if (full != null && full.isNotEmpty) {
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Image.network(
            full,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
          ),
        );
      } else {
        iconWidget = Text(
          fallbackEmoji,
          style: const TextStyle(fontSize: 24),
        );
      }
    } else {
      iconWidget = Text(
        fallbackEmoji,
        style: const TextStyle(fontSize: 24),
      );
    }

    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: iconWidget,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          if (xp > 0)
            Text(
              '+$xp XP',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// Avatar that also supports backend-stored media paths using publicMediaUrl.
class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _Avatar({required this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = (name.isNotEmpty ? name[0] : '?').toUpperCase();

    String? resolved;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      final isAbs =
          photoUrl!.startsWith('http://') || photoUrl!.startsWith('https://');
      resolved = publicMediaUrl(
        isAbs ? photoUrl : null,
        path: isAbs ? null : photoUrl,
      );
    }

    if (resolved != null && resolved.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundImage: NetworkImage(resolved),
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: AppColors.primary.withOpacity(0.12),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: _cardDecor(radius: 18),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.primaryVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PrefRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: danger ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
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