import 'package:flutter/material.dart';
import '../../common/theme/app_colors.dart';

/// Simple data model you can pass into the popup.
class BadgeUnlockedData {
  final String id;
  final String name;
  final String description;
  final String icon;

  const BadgeUnlockedData({
    required this.id,
    required this.name,
    required this.description,
    this.icon = '🏅',
  });
}

/// Call this from any screen after detect a NEW badge was earned.
///
/// Example:
///   await showBadgeUnlockedDialog(
///     context,
///     BadgeUnlockedData(
///       id: badgeId,
///       name: 'First Steps',
///       description: 'You completed your first activity!',
///       icon: '👣',
///     ),
///   );
Future<Future<Object?>> showBadgeUnlockedDialog(
    BuildContext context,
    BadgeUnlockedData badge,
    ) async {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Badge unlocked',
    barrierColor: Theme.of(context).colorScheme.scrim.withOpacity(0.54),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) {
      return _BadgeUnlockedDialog(badge: badge);
    },
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: curved,
          child: child,
        ),
      );
    },
  );
}

class _BadgeUnlockedDialog extends StatefulWidget {
  final BadgeUnlockedData badge;

  const _BadgeUnlockedDialog({required this.badge});

  @override
  State<_BadgeUnlockedDialog> createState() => _BadgeUnlockedDialogState();
}

class _BadgeUnlockedDialogState extends State<_BadgeUnlockedDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _shineController;

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color:
                      Theme.of(context).colorScheme.scrim.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top sparkle row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'New badge unlocked!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: 12),

                // Badge icon with subtle glow
                AnimatedBuilder(
                  animation: _shineController,
                  builder: (context, child) {
                    final t = _shineController.value;
                    final scale = 1.0 + 0.05 * (1 - (t - 0.5).abs() * 2);
                    final glowOpacity = 0.35 + 0.25 * t;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.primary.withOpacity(glowOpacity),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.background,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                badge.icon,
                                style: const TextStyle(fontSize: 40),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 14),

                // Badge name
                Text(
                  badge.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),

                // Badge description
                Text(
                  badge.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 16),

                // Button row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.border.withOpacity(0.9),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Nice!',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}