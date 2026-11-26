// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/ui_prefs_service.dart';
import '../ui/theme/app_colors.dart';

// ── Theme mode ────────────────────────────────────────────────────

class ThemeModeNotifier extends Notifier<ThemeMode> {
  var _chosen = false;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final v = await ref.read(uiPrefsServiceProvider).themeMode();
    // A choice made while it loaded wins.
    if (_chosen) return;
    state = switch (v) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> set(ThemeMode mode) async {
    _chosen = true;
    state = mode;
    await ref.read(uiPrefsServiceProvider).setThemeMode(mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ── Accent color ──────────────────────────────────────────────────

class AccentNotifier extends Notifier<Color> {
  var _chosen = false;

  @override
  Color build() {
    _load();
    return AppColors.accentCyan;
  }

  Future<void> _load() async {
    final v = await ref.read(uiPrefsServiceProvider).accent();
    if (!_chosen && v != null) state = Color(v);
  }

  Future<void> set(Color color) async {
    _chosen = true;
    state = color;
    await ref.read(uiPrefsServiceProvider).setAccent(color.toARGB32());
  }
}

final accentProvider = NotifierProvider<AccentNotifier, Color>(AccentNotifier.new);

// ── Server list view ──────────────────────────────────────────────

/// How the server list is shown: without subscription groups, sorted by ping.
typedef ConfigsView = ({bool hideGroups, bool sortByPing});

class ConfigsViewNotifier extends Notifier<ConfigsView> {
  bool? _hideGroups;
  bool? _sortByPing;

  @override
  ConfigsView build() {
    _load();
    return (hideGroups: false, sortByPing: false);
  }

  /// A flag chosen while it loaded wins; the other one is the stored value.
  Future<void> _load() async {
    final v = await ref.read(uiPrefsServiceProvider).configsView();
    state = (hideGroups: _hideGroups ?? v.hideGroups, sortByPing: _sortByPing ?? v.sortByPing);
  }

  /// Sets and stores only the flags given.
  Future<void> set({bool? hideGroups, bool? sortByPing}) async {
    _hideGroups = hideGroups ?? _hideGroups;
    _sortByPing = sortByPing ?? _sortByPing;
    state = (hideGroups: hideGroups ?? state.hideGroups, sortByPing: sortByPing ?? state.sortByPing);
    await ref.read(uiPrefsServiceProvider).setConfigsView(hideGroups: hideGroups, sortByPing: sortByPing);
  }
}

final configsViewProvider = NotifierProvider<ConfigsViewNotifier, ConfigsView>(ConfigsViewNotifier.new);
