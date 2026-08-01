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
    chartGradientTop: Color(0xFF77A6FF),
    chartGradientBottom: Color(0xFFDCE8FF),
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
    chartGradientTop: Color(0xFF8CB8FF),
    chartGradientBottom: Color(0xFF1A2B52),
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

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: lightColors.primary,
        secondary: lightColors.secondary,
        surface: lightColors.surface,
        error: lightColors.error,
        onPrimary: lightColors.textOnPrimary,
        onSecondary: lightColors.textOnPrimary,
        onSurface: lightColors.textPrimary,
        onError: lightColors.textOnPrimary,
      ),
      scaffoldBackgroundColor: lightColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: lightColors.background,
        foregroundColor: lightColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: lightColors.shadow,
        surfaceTintColor: lightColors.background,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: lightColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: ThemeData.light().cardTheme.copyWith(
        color: lightColors.cardBackground,
        elevation: 0,
        shadowColor: lightColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: lightColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightColors.primary,
          foregroundColor: lightColors.textOnPrimary,
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
          backgroundColor: lightColors.primary,
          foregroundColor: lightColors.textOnPrimary,
          disabledBackgroundColor: lightColors.surfaceVariant.blend(
            lightColors.primary,
            0.12,
          ),
          disabledForegroundColor: lightColors.textTertiary,
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
          foregroundColor: lightColors.textPrimary,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: lightColors.border),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightColors.primary,
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
          foregroundColor: lightColors.textPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightColors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: lightColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: lightColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: lightColors.inputFocusBorder,
            width: 1.7,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: lightColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: lightColors.textTertiary,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: lightColors.navBackground,
        selectedItemColor: lightColors.navSelected,
        unselectedItemColor: lightColors.navUnselected,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: lightColors.primary,
        foregroundColor: lightColors.textOnPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: ThemeData.light().dialogTheme.copyWith(
        backgroundColor: lightColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: lightColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: lightColors.textSecondary,
        ),
      ),
      dividerTheme: DividerThemeData(color: lightColors.divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: lightColors.surface,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: lightColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: lightColors.border),
        ),
      ),
      textTheme: _buildTextTheme(lightColors),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: darkColors.primary,
        secondary: darkColors.secondary,
        surface: darkColors.surface,
        error: darkColors.error,
        onPrimary: darkColors.textOnPrimary,
        onSecondary: darkColors.textOnPrimary,
        onSurface: darkColors.textPrimary,
        onError: darkColors.textOnPrimary,
      ),
      scaffoldBackgroundColor: darkColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: darkColors.background,
        foregroundColor: darkColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: darkColors.shadow,
        surfaceTintColor: darkColors.background,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: darkColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: ThemeData.dark().cardTheme.copyWith(
        color: darkColors.cardBackground,
        elevation: 0,
        shadowColor: darkColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: darkColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkColors.primary,
          foregroundColor: darkColors.textOnPrimary,
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
          backgroundColor: darkColors.primary,
          foregroundColor: darkColors.textOnPrimary,
          disabledBackgroundColor: darkColors.surfaceVariant.blend(
            darkColors.primary,
            0.12,
          ),
          disabledForegroundColor: darkColors.textTertiary,
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
          foregroundColor: darkColors.textPrimary,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: darkColors.border),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkColors.primary,
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
          foregroundColor: darkColors.textPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkColors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: darkColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: darkColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: darkColors.inputFocusBorder,
            width: 1.7,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: darkColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: darkColors.textTertiary,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkColors.navBackground,
        selectedItemColor: darkColors.navSelected,
        unselectedItemColor: darkColors.navUnselected,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: darkColors.primary,
        foregroundColor: darkColors.textOnPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: ThemeData.dark().dialogTheme.copyWith(
        backgroundColor: darkColors.surface,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: darkColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: darkColors.textSecondary,
        ),
      ),
      dividerTheme: DividerThemeData(color: darkColors.divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkColors.surface,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: darkColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: darkColors.border),
        ),
      ),
      textTheme: _buildTextTheme(darkColors),
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
  final Color chartGradientTop;
  final Color chartGradientBottom;

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
    required this.chartGradientTop,
    required this.chartGradientBottom,
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

// Compatibility for Flutter SDKs that do not expose Color.withValues.
extension ColorWithValuesCompatibility on Color {
  Color withValues({double? alpha, double? red, double? green, double? blue}) {
    int normalizeToChannel(double component) =>
        (component.clamp(0.0, 1.0) * 255).round();

    // ignore: deprecated_member_use
    final int currentValue = value;
    final int currentAlpha = (currentValue >> 24) & 0xFF;
    final int currentRed = (currentValue >> 16) & 0xFF;
    final int currentGreen = (currentValue >> 8) & 0xFF;
    final int currentBlue = currentValue & 0xFF;

    return Color.fromARGB(
      alpha != null ? normalizeToChannel(alpha) : currentAlpha,
      red != null ? normalizeToChannel(red) : currentRed,
      green != null ? normalizeToChannel(green) : currentGreen,
      blue != null ? normalizeToChannel(blue) : currentBlue,
    );
  }
}
