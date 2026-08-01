import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

TextStyle _fontStyle(
  double fontSize,
  FontWeight weight,
  Color color, {
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

class AppTheme {
  // Brighter, friendlier light palette with stronger accent contrast.
  static const lightColors = AppColors(
    primary: Color(0xFF2A6CF7),
    primaryLight: Color(0xFF5A8DFF),
    primaryDark: Color(0xFF1949B8),
    secondary: Color(0xFF0FA5A2),
    secondaryLight: Color(0xFF2ECFC0),
    secondaryDark: Color(0xFF0F7A78),
    background: Color(0xFFF3F7FF),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEBF1FF),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    // WCAG AA: 5.6:1 on background, 6.0:1 on white surfaces
    textTertiary: Color(0xFF556478),
    textOnPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFEF4444),
    info: Color(0xFF3B82F6),
    chartLine: Color(0xFF2A6CF7),
    chartBar: Color(0xFF0FA5A2),
    divider: Color(0xFFD9E2F3),
    border: Color(0xFFC7D6EE),
    shadow: Color(0x1F0F172A),
    cardBackground: Color(0xFFFFFFFF),
    navBackground: Color(0xFFFFFFFF),
    // WCAG AA at small font sizes: 5.6:1 on background
    navSelected: Color(0xFF1E5AD6),
    navUnselected: Color(0xFF556478),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFC7D6EE),
    inputFocusBorder: Color(0xFF2A6CF7),
  );

  // Dark palette with deep navy surfaces and vivid accents.
  static const darkColors = AppColors(
    primary: Color(0xFF6FA4FF),
    primaryLight: Color(0xFF96BEFF),
    primaryDark: Color(0xFF2A6CF7),
    secondary: Color(0xFF2ED9D1),
    secondaryLight: Color(0xFF74E8E0),
    secondaryDark: Color(0xFF1C9F9A),
    background: Color(0xFF070C17),
    surface: Color(0xFF111A2C),
    surfaceVariant: Color(0xFF18243D),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textTertiary: Color(0xFF94A3B8),
    textOnPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    error: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
    chartLine: Color(0xFF6FA4FF),
    chartBar: Color(0xFF2ED9D1),
    divider: Color(0xFF24344F),
    border: Color(0xFF314766),
    shadow: Color(0x66000000),
    cardBackground: Color(0xFF111A2C),
    navBackground: Color(0xFF0F1727),
    navSelected: Color(0xFF6FA4FF),
    navUnselected: Color(0xFF8FA2C0),
    inputBackground: Color(0xFF17243A),
    inputBorder: Color(0xFF314766),
    inputFocusBorder: Color(0xFF6FA4FF),
  );

  static ThemeData lightTheme() => _buildTheme(lightColors, Brightness.light);

  static ThemeData darkTheme() => _buildTheme(darkColors, Brightness.dark);

  static ThemeData _buildTheme(AppColors colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: colors.primary,
              secondary: colors.secondary,
              surface: colors.surface,
              error: colors.error,
              onPrimary: colors.textOnPrimary,
              onSecondary: colors.textOnPrimary,
              onSurface: colors.textPrimary,
              onError: colors.textOnPrimary,
            )
          : ColorScheme.light(
              primary: colors.primary,
              secondary: colors.secondary,
              surface: colors.surface,
              error: colors.error,
              onPrimary: colors.textOnPrimary,
              onSecondary: colors.textOnPrimary,
              onSurface: colors.textPrimary,
              onError: colors.textOnPrimary,
            ),
      scaffoldBackgroundColor: colors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: colors.shadow,
        surfaceTintColor: colors.background,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.cardBackground,
        elevation: 0,
        shadowColor: colors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.textOnPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.textOnPrimary,
          disabledBackgroundColor: colors.surfaceVariant.blend(
            colors.primary,
            0.12,
          ),
          disabledForegroundColor: colors.textTertiary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: colors.border),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.inputFocusBorder, width: 1.7),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: colors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: colors.textTertiary,
          fontSize: 14,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.textOnPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        elevation: isDark ? 10 : 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: colors.textSecondary,
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surface,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.border),
        ),
      ),
      textTheme: _buildTextTheme(colors),
    );
  }

  static TextTheme _buildTextTheme(AppColors colors) {
    return TextTheme(
      displayLarge: _fontStyle(57, FontWeight.w400, colors.textPrimary),
      displayMedium: _fontStyle(45, FontWeight.w400, colors.textPrimary),
      displaySmall: _fontStyle(36, FontWeight.w400, colors.textPrimary),
      headlineLarge: _fontStyle(
        32,
        FontWeight.w700,
        colors.textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: _fontStyle(
        28,
        FontWeight.w700,
        colors.textPrimary,
        letterSpacing: -0.5,
      ),
      headlineSmall: _fontStyle(
        24,
        FontWeight.w700,
        colors.textPrimary,
        letterSpacing: -0.3,
      ),
      titleLarge: _fontStyle(
        22,
        FontWeight.w700,
        colors.textPrimary,
        letterSpacing: -0.2,
      ),
      titleMedium: _fontStyle(16, FontWeight.w700, colors.textPrimary),
      titleSmall: _fontStyle(14, FontWeight.w700, colors.textPrimary),
      bodyLarge: _fontStyle(
        16,
        FontWeight.w500,
        colors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: _fontStyle(
        14,
        FontWeight.w500,
        colors.textSecondary,
        height: 1.5,
      ),
      bodySmall: _fontStyle(
        12,
        FontWeight.w500,
        colors.textTertiary,
        height: 1.4,
      ),
      labelLarge: _fontStyle(14, FontWeight.w700, colors.textPrimary),
      labelMedium: _fontStyle(12, FontWeight.w700, colors.textSecondary),
      labelSmall: _fontStyle(
        11,
        FontWeight.w700,
        colors.textTertiary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class AppColors {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  final Color secondary;
  final Color secondaryLight;
  final Color secondaryDark;

  final Color background;
  final Color surface;
  final Color surfaceVariant;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnPrimary;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  final Color chartLine;
  final Color chartBar;
  final Color divider;
  final Color border;
  final Color shadow;
  final Color cardBackground;

  final Color navBackground;
  final Color navSelected;
  final Color navUnselected;

  final Color inputBackground;
  final Color inputBorder;
  final Color inputFocusBorder;

  const AppColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryLight,
    required this.secondaryDark,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnPrimary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.chartLine,
    required this.chartBar,
    required this.divider,
    required this.border,
    required this.shadow,
    required this.cardBackground,
    required this.navBackground,
    required this.navSelected,
    required this.navUnselected,
    required this.inputBackground,
    required this.inputBorder,
    required this.inputFocusBorder,
  });
}

extension AppColorsExtension on BuildContext {
  AppColors get colors {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark
        ? AppTheme.darkColors
        : AppTheme.lightColors;
  }

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

extension SolidColorBlend on Color {
  Color blend(Color other, [double amount = 0.5]) {
    return Color.lerp(this, other, amount.clamp(0.0, 1.0))!;
  }
}
