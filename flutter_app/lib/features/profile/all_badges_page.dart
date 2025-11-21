import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';
import '../../common/utils/media_utils.dart';

class AllBadgesPage extends StatelessWidget {
  final String uid;

  const AllBadgesPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('All badges'),
        centerTitle: true,
      ),
      body: FutureBuilder<_BadgesData>(
        // Load definitions + owned badges once
        future: _loadBadges(db, uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load badges:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!;
          final defs = data.defs;
          final ownedIds = data.ownedIds;

          if (defs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No badge definitions configured yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }

          final total = defs.length;
          final earnedCount = ownedIds.length;

          return RefreshIndicator(
            onRefresh: () async {
              // Simply rebuild by popping + pushing; cheap and easy
              if (context.mounted) {
                Navigator.of(context).pop();
                await Future.delayed(const Duration(milliseconds: 200));
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.softShadow,
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Badges',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$earnedCount of $total earned',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _BadgeProgressPill(
                          total: total,
                          earned: earnedCount,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Grid of badges
                  Text(
                    'All badges',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: defs.map((defDoc) {
                      final def = defDoc.data();
                      final id = defDoc.id;
                      final earned = ownedIds.contains(id);

                      final name =
                          (def['title'] as String?) ?? (def['name'] as String?) ?? 'Badge';
                      final desc = (def['description'] as String?) ??
                          (earned
                              ? 'Achievement unlocked'
                              : 'Unlock this achievement');

                      final iconField = def['icon'] as String?;
                      final iconUrl = _resolveBadgeIcon(iconField);

                      final xpReward =
                          (def['xpReward'] as num?)?.toInt() ?? 0;

                      return _BadgeCard(
                        iconUrl: iconUrl,
                        emojiFallback: '⭐',
                        title: name,
                        description: desc,
                        earned: earned,
                        xpReward: xpReward,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small helper container for the loaded data.
class _BadgesData {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> defs;
  final Set<String> ownedIds;

  _BadgesData({
    required this.defs,
    required this.ownedIds,
  });
}

Future<_BadgesData> _loadBadges(
    FirebaseFirestore db,
    String uid,
    ) async {
  // NOTE: no filters here – we really want ALL docs in /badge_definitions
  final defsSnap =
  await db.collection('badge_definitions').get(const GetOptions());
  final ownedSnap = await db
      .collection('users')
      .doc(uid)
      .collection('badges')
      .get(const GetOptions());

  final defs = defsSnap.docs;
  final ownedIds = {for (final d in ownedSnap.docs) d.id};

  return _BadgesData(defs: defs, ownedIds: ownedIds);
}

/// Resolve icon string using the shared media utils.
/// - If it's an http(s) URL, use as-is.
/// - Otherwise treat it as a media path and hand to `publicMediaUrl`.
String? _resolveBadgeIcon(String? iconField) {
  if (iconField == null || iconField.isEmpty) return null;

  if (iconField.startsWith('http://') || iconField.startsWith('https://')) {
    return iconField;
  }

  // This uses the same helper you use for lesson thumbnails, etc.
  return publicMediaUrl(null, path: iconField);
}

// =============================
// UI widgets
// =============================

class _BadgeProgressPill extends StatelessWidget {
  final int total;
  final int earned;

  const _BadgeProgressPill({
    required this.total,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? earned / total : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: AppColors.success,
          ),
          const SizedBox(width: 6),
          Text(
            '${(ratio * 100).round()}%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final String? iconUrl;
  final String emojiFallback;
  final String title;
  final String description;
  final bool earned;
  final int xpReward;

  const _BadgeCard({
    required this.iconUrl,
    required this.emojiFallback,
    required this.title,
    required this.description,
    required this.earned,
    required this.xpReward,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = earned ? AppColors.surface : AppColors.background;
    final borderColor =
    earned ? AppColors.border : AppColors.border.withOpacity(0.6);
    final titleColor =
    earned ? AppColors.textPrimary : AppColors.textSecondary;
    final opacity = earned ? 1.0 : 0.65;

    return Opacity(
      opacity: opacity,
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: bgColor,
          border: Border.all(color: borderColor),
          boxShadow: earned
              ? [
            BoxShadow(
              color: AppColors.softShadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ]
              : const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Center(
                  child: _BadgeIcon(
                    iconUrl: iconUrl,
                    emojiFallback: emojiFallback,
                  ),
                ),
                if (!earned)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  )
                else
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Earned',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
            if (xpReward > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+$xpReward XP',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final String? iconUrl;
  final String emojiFallback;

  const _BadgeIcon({
    required this.iconUrl,
    required this.emojiFallback,
  });

  @override
  Widget build(BuildContext context) {
    if (iconUrl == null) {
      return Text(
        emojiFallback,
        style: const TextStyle(fontSize: 26),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        iconUrl!,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          // Fallback if the image fails to load.
          return Text(
            emojiFallback,
            style: const TextStyle(fontSize: 26),
          );
        },
      ),
    );
  }
}