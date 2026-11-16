import 'package:flutter/widgets.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// Strings for code without a [BuildContext] (providers, config builders, models).
/// The root widget keeps [current] in sync with the app locale; English until then.
abstract final class L10n {
  static AppLocalizations current = lookupAppLocalizations(const Locale('en'));
}

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
