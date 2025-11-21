import 'dart:math' as math;

/// XP → Level conversion utilities.
///
/// Total XP to reach level L: 50L² + 50L
class Leveling {
  static int totalForLevel(int level) => (50 * level * level + 50 * level);

  static int levelFromXp(int xp) {
    final a = 50.0, b = 50.0, c = -xp.toDouble();
    final disc = b * b - 4 * a * c;
    final root = math.sqrt(disc);
    final l = ((-b + root) / (2 * a)).floor();
    return l.clamp(0, 9999);
  }

  /// Given total XP, returns current level + progress inside that level.
  static ({int level, int cur, int need}) progress(int xp) {
    final lvl = levelFromXp(xp);
    final base = totalForLevel(lvl);
    final next = totalForLevel(lvl + 1);
    return (level: lvl, cur: xp - base, need: next - base);
  }
}