import 'dart:math';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

class AppColors {
  // ── Dark palette ──────────────────────────────────────────────
  static const bgDark = Color(0xFF05080A);
  static const bgElevDark = Color(0xFF0B0F12);
  static const bgSunkenDark = Color(0xFF080B0D);
  static const lineDark = Color(0xFF1A2024);
  static const lineSoftDark = Color(0xFF12171A);
  static const textDark = Color(0xFFE8ECEE);
  static const textDimDark = Color(0xFF8A969D);
  static const textMutedDark = Color(0xFF768188); // ≥4.5:1 on every dark background (WCAG AA)

  // ── Light palette ─────────────────────────────────────────────
  static const bgLight = Color(0xFFF2F4F5);
  static const bgElevLight = Color(0xFFFFFFFF);
  static const bgSunkenLight = Color(0xFFE8EBED);
  static const lineLight = Color(0xFFCDD1D5);
  static const lineSoftLight = Color(0xFFDADEE2);
  static const textLight = Color(0xFF0A0D10);
  static const textDimLight = Color(0xFF3E4A52);
  static const textMutedLight = Color(0xFF5E6874);

  static const danger = Color(0xFFFF5A5F);

  /// [danger] for light backgrounds: ≥4.5:1 on each of them (WCAG AA).
  static const dangerLight = Color(0xFFC62828);

  // ── Accent presets ────────────────────────────────────────────
  static const accentCyan = Color(0xFF6AD8E6);
  static const accentIce = Color(0xFF9BE8F0);
  static const accentAzure = Color(0xFF4AA8FF);
  static const accentMint = Color(0xFF7AE6C4);
  static const accentLime = Color(0xFFC7F06B);
  static const accentOrange = Color(0xFFFFB74D);
  static const accentPink = Color(0xFFFF7FFF);
  static const accentPurple = Color(0xFFB47FFF);
  static const accentGold = Color(0xFFD9A65B);
  static const accentMono = Color(0xFFE8ECEE);
  static const accentSoftRed = Color(0xFFFF7F7F);

  static const List<Color> accentPresets = [
    accentCyan,
    accentIce,
    accentAzure,
    accentMint,
    accentLime,
    accentOrange,
    accentPink,
    accentPurple,
    accentGold,
    accentSoftRed,
    accentMono,
  ];

  // ── Legacy aliases (used by un-migrated screens) ───────────────
  static const bg = bgDark;
  static const surface = bgElevDark;
  static const surfaceElevated = Color(0xFF1E2530);
  static const surfaceHighlight = Color(0xFF252D3A);
  static const primary = Color(0xFF4F9FFF);
  static const primaryDim = Color(0xFF2A5C99);
  static const connected = Color(0xFF3DD68C);
  static const connectedDim = Color(0xFF1A6B44);
  static const disconnected = Color(0xFF8892A4);
  static const connecting = Color(0xFFFFB74D);
  static const error = Color(0xFFFF5252);
  static const textPrimary = textDark;
  static const textSecondary = textDimDark;
  static const textDisabled = Color(0xFF4A5568);
  static const border = Color(0xFF252D3A);
  static const borderAccent = Color(0xFF2A5C99);
  static const logDebug = Color(0xFF8892A4);
  static const logInfo = Color(0xFF4F9FFF);
  static const logWarning = Color(0xFFFFB74D);
  static const logError = Color(0xFFFF5252);
  static const chartUpload = Color(0xFF4F9FFF);
  static const chartDownload = Color(0xFF3DD68C);
  static const protoVless = Color(0xFF4F9FFF);
  static const protoVmess = Color(0xFFB47FFF);
  static const protoTrojan = Color(0xFFFF7F7F);
  static const protoShadowsocks = Color(0xFFFFB74D);
  static const protoHysteria2 = Color(0xFF3DD6C8);
}

// ── Design token extension ────────────────────────────────────────

@immutable
class TeapodTokens extends ThemeExtension<TeapodTokens> {
  final Color bg;
  final Color bgElev;
  final Color bgSunken;
  final Color line;
  final Color lineSoft;
  final Color text;
  final Color textDim;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color accentFade;
  final Color danger;

  const TeapodTokens({
    required this.bg,
    required this.bgElev,
    required this.bgSunken,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.textDim,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.accentFade,
    required this.danger,
  });

  factory TeapodTokens.dark(Color accent) => TeapodTokens(
    bg: AppColors.bgDark,
    bgElev: AppColors.bgElevDark,
    bgSunken: AppColors.bgSunkenDark,
    line: AppColors.lineDark,
    lineSoft: AppColors.lineSoftDark,
    text: AppColors.textDark,
    textDim: AppColors.textDimDark,
    textMuted: AppColors.textMutedDark,
    accent: accent,
    accentSoft: accent.withAlpha(0x22),
    accentFade: accent.withAlpha(0x0F),
    danger: AppColors.danger,
  );

  factory TeapodTokens.light(Color accent) {
    // Preset accents are tuned for dark backgrounds (high lightness, low contrast on white).
    // Darken them to maintain readability on light surfaces.
    final a = _darkenAccentForLight(accent);
    return TeapodTokens(
      bg: AppColors.bgLight,
      bgElev: AppColors.bgElevLight,
      bgSunken: AppColors.bgSunkenLight,
      line: AppColors.lineLight,
      lineSoft: AppColors.lineSoftLight,
      text: AppColors.textLight,
      textDim: AppColors.textDimLight,
      textMuted: AppColors.textMutedLight,
      accent: a,
      accentSoft: a.withAlpha(_lightSoftAlpha),
      accentFade: a.withAlpha(0x14),
      danger: AppColors.dangerLight,
    );
  }

  static const _lightSoftAlpha = 0x28;

  /// Darkens [c], hue and saturation kept, until text in it has the WCAG AA contrast (4.5:1) on every light
  /// background, also under the selection highlight (`accentSoft` laid over it); an accent already that dark is left
  /// as is.
  static Color _darkenAccentForLight(Color c) {
    double contrast(Color fg, Color bg) {
      final (a, b) = (fg.computeLuminance(), bg.computeLuminance());
      return (max(a, b) + 0.05) / (min(a, b) + 0.05);
    }

    // bgSunkenLight is the darkest light background; the highlight over it is darker still.
    bool readable(Color a) {
      final highlight = Color.alphaBlend(a.withAlpha(_lightSoftAlpha), AppColors.bgSunkenLight);
      return contrast(a, AppColors.bgSunkenLight) >= 4.5 && contrast(a, highlight) >= 4.5;
    }

    var hsl = HSLColor.fromColor(c);
    while (hsl.lightness > 0 && !readable(hsl.toColor())) {
      hsl = hsl.withLightness(max(0, hsl.lightness - 0.01));
    }
    return hsl.toColor();
  }

  @override
  TeapodTokens copyWith({
    Color? bg,
    Color? bgElev,
    Color? bgSunken,
    Color? line,
    Color? lineSoft,
    Color? text,
    Color? textDim,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? accentFade,
    Color? danger,
  }) => TeapodTokens(
    bg: bg ?? this.bg,
    bgElev: bgElev ?? this.bgElev,
    bgSunken: bgSunken ?? this.bgSunken,
    line: line ?? this.line,
    lineSoft: lineSoft ?? this.lineSoft,
    text: text ?? this.text,
    textDim: textDim ?? this.textDim,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    accentFade: accentFade ?? this.accentFade,
    danger: danger ?? this.danger,
  );

  @override
  TeapodTokens lerp(TeapodTokens? other, double t) {
    if (other == null) return this;
    return TeapodTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      bgElev: Color.lerp(bgElev, other.bgElev, t)!,
      bgSunken: Color.lerp(bgSunken, other.bgSunken, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineSoft: Color.lerp(lineSoft, other.lineSoft, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentFade: Color.lerp(accentFade, other.accentFade, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

// Convenience accessor
extension TeapodTokensContext on BuildContext {
  TeapodTokens get t => Theme.of(this).extension<TeapodTokens>()!;
}
