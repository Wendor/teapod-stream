import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/ui_prefs_service.dart';

/// App language: `null` follows the system ([UiPrefsService.locale]).
class LocaleNotifier extends Notifier<Locale?> {
  var _chosen = false;

  @override
  Locale? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final v = await ref.read(uiPrefsServiceProvider).locale();
    // A choice made while it loaded wins.
    if (!_chosen && v != null && v.isNotEmpty) state = Locale(v);
  }

  Future<void> set(Locale? locale) async {
    _chosen = true;
    state = locale;
    await ref.read(uiPrefsServiceProvider).setLocale(locale?.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);
