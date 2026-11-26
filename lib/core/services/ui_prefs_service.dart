import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's look and the server list's view in SharedPreferences, outside the profiles: they are the device's, not a
/// profile's. The language key `app_locale` is also read by native code for notification texts.
class UiPrefsService {
  const UiPrefsService();

  static const _locale = 'app_locale';
  static const _themeMode = 'theme_mode';
  static const _accent = 'accent_color';
  static const _hideGroups = 'cfg_hide_groups';
  static const _sortByPing = 'cfg_sort_by_ping';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// A language code; null — follow the system.
  Future<String?> locale() async => (await _prefs).getString(_locale);

  Future<void> setLocale(String? code) async {
    final prefs = await _prefs;
    if (code == null || code.isEmpty) {
      await prefs.remove(_locale);
    } else {
      await prefs.setString(_locale, code);
    }
  }

  /// `ThemeMode.name` as stored.
  Future<String?> themeMode() async => (await _prefs).getString(_themeMode);

  Future<void> setThemeMode(String name) async => (await _prefs).setString(_themeMode, name);

  /// An ARGB color.
  Future<int?> accent() async => (await _prefs).getInt(_accent);

  Future<void> setAccent(int argb) async => (await _prefs).setInt(_accent, argb);

  Future<({bool hideGroups, bool sortByPing})> configsView() async {
    final prefs = await _prefs;
    return (hideGroups: prefs.getBool(_hideGroups) ?? false, sortByPing: prefs.getBool(_sortByPing) ?? false);
  }

  /// Writes only the flags given.
  Future<void> setConfigsView({bool? hideGroups, bool? sortByPing}) async {
    final prefs = await _prefs;
    if (hideGroups != null) await prefs.setBool(_hideGroups, hideGroups);
    if (sortByPing != null) await prefs.setBool(_sortByPing, sortByPing);
  }
}

final uiPrefsServiceProvider = Provider<UiPrefsService>((ref) => const UiPrefsService());
