import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  // ── Type helpers ──────────────────────────────────────────────

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
    double? height,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size < 11 ? 11 : size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
    double? height,
  }) =>
      GoogleFonts.interTight(
        fontSize: size < 11 ? 11 : size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  // ── Theme builder ─────────────────────────────────────────────

  static ThemeData build(Brightness brightness, Color accent) {
    final isDark = brightness == Brightness.dark;
    final tokens =
        isDark ? TeapodTokens.dark(accent) : TeapodTokens.light(accent);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: tokens.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        surface: tokens.bgElev,
        primary: tokens.accent,
        secondary: tokens.accent,
        error: tokens.danger,
        onSurface: tokens.text,
        onPrimary: isDark ? AppColors.bgDark : Colors.white,
        onSecondary: isDark ? AppColors.bgDark : Colors.white,
        onError: Colors.white,
      ),
      extensions: [tokens],
      fontFamily: GoogleFonts.interTight().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bg,
        foregroundColor: tokens.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: sans(
            size: 18, weight: FontWeight.w600, color: tokens.text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.bg,
        indicatorColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: tokens.bgElev,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: tokens.line, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.line,
        thickness: 1,
        space: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.accent;
          return tokens.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.accent.withAlpha(0x55);
          }
          return tokens.line;
        }),
      ),
      textTheme: TextTheme(
        headlineLarge:  sans(size: 28, weight: FontWeight.w500, color: tokens.text, letterSpacing: -1),
        headlineMedium: sans(size: 22, weight: FontWeight.w600, color: tokens.text),
        titleLarge:     sans(size: 18, weight: FontWeight.w600, color: tokens.text),
        titleMedium:    sans(size: 16, weight: FontWeight.w500, color: tokens.text),
        bodyLarge:      sans(size: 16, color: tokens.text),
        bodyMedium:     sans(size: 14, color: tokens.textDim),
        bodySmall:      sans(size: 12, color: tokens.textMuted),
        labelSmall:     mono(size: 10, color: tokens.textMuted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.bgElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: tokens.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: tokens.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: tokens.accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: tokens.textDim),
        hintStyle:  TextStyle(color: tokens.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: isDark ? AppColors.bgDark : Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: mono(size: 11, letterSpacing: 1),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: tokens.text,
        subtitleTextStyle: sans(size: 13, color: tokens.textDim),
        iconColor: tokens.textDim,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.surfaceElevated : AppColors.bgElevLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: tokens.line),
        ),
      ),
    );
  }

  // Legacy getter kept for screens not yet on the new system
  static ThemeData get dark => build(Brightness.dark, AppColors.accentCyan);
}
