import 'package:flutter/material.dart';

class AppTheme {
  static const _primary = Color(0xFF4A90E2);
  static const _primaryVariant = Color(0xFF357ABD);
  static const _error = Color(0xFFE57373);
  static const _success = Color(0xFF4CAF50);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _primary,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFDEE9FB),
    onPrimaryContainer: Color(0xFF0F2D57),
    secondary: _primaryVariant,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE3EEF9),
    onSecondaryContainer: Color(0xFF0B2A4A),
    surface: Colors.white,
    onSurface: Color(0xFF1C1C28),
    surfaceTint: Colors.white,
    surfaceVariant: Color(0xFFE5EBF3),
    onSurfaceVariant: Color(0xFF4C5565),
    background: Color(0xFFF6F8FC),
    onBackground: Color(0xFF1C1C28),
    error: _error,
    onError: Colors.white,
    errorContainer: Color(0xFFFDD9D7),
    onErrorContainer: Color(0xFF5F1210),
    tertiary: _success,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD4F5DC),
    onTertiaryContainer: Color(0xFF0F3F1D),
    outline: Color(0xFFD2D8E3),
    outlineVariant: Color(0xFFEDF1F7),
    shadow: Color(0x19000000),
    scrim: Colors.black,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _primary,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF1F4B7B),
    onPrimaryContainer: Color(0xFFCEE2FF),
    secondary: _primaryVariant,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF1C3D61),
    onSecondaryContainer: Color(0xFFD4E6FF),
    surface: Color(0xFF151B24),
    onSurface: Color(0xFFE3E8EF),
    surfaceTint: Color(0xFF1E2632),
    surfaceVariant: Color(0xFF1E2632),
    onSurfaceVariant: Color(0xFFAFB6C2),
    background: Color(0xFF0F141C),
    onBackground: Color(0xFFE3E8EF),
    error: _error,
    onError: Colors.white,
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFFDDAD6),
    tertiary: _success,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFF1F4D2C),
    onTertiaryContainer: Color(0xFFCFEBD6),
    outline: Color(0xFF3D4757),
    outlineVariant: Color(0xFF2B3442),
    shadow: Color(0x66000000),
    scrim: Colors.black,
  );

  static ThemeData get lightTheme => _baseTheme(_lightScheme);
  static ThemeData get darkTheme => _baseTheme(_darkScheme);

  static ThemeData _baseTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;

    final textTheme = (isDark ? Typography.whiteCupertino : Typography.blackCupertino)
        .apply(fontFamily: 'Poppins', displayColor: scheme.onSurface, bodyColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.background,
      fontFamily: 'Poppins',
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: true,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardTheme(
        color: scheme.surface,
        surfaceTintColor: scheme.surface,
        elevation: isDark ? 1 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceVariant : scheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(0.8)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: isDark ? 1 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withOpacity(0.35)
              : scheme.onSurfaceVariant.withOpacity(0.3),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? scheme.surfaceVariant : scheme.onSurface,
        contentTextStyle: TextStyle(color: isDark ? scheme.onSurface : Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer.withOpacity(isDark ? 0.3 : 0.6),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: isDark ? 1 : 2,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
    );
  }
}
