import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/theme/app_colors.dart';

// ── Theme mode ────────────────────────────────────────────────────

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    ThemeMode mode;
    if (v == 'light') {
      mode = ThemeMode.light;
    } else if (v == 'system') {
      mode = ThemeMode.system;
    } else {
      mode = ThemeMode.dark;
    }
    state = mode;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ── Accent color ──────────────────────────────────────────────────

class AccentNotifier extends Notifier<Color> {
  static const _key = 'accent_color';

  @override
  Color build() {
    _load();
    return AppColors.accentCyan;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) state = Color(v);
  }

  Future<void> set(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, color.toARGB32());
  }
}

final accentProvider =
    NotifierProvider<AccentNotifier, Color>(AccentNotifier.new);
