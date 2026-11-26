import '../../l10n/l10n.dart';

/// The messages the app itself raises into state; [AppMessage.localize] turns a code into text.
enum MessageCode {
  vpnConnectError,
  vpnConnectTimeout,
  vpnNoConfigSelected,
  geositeMissing,
  geoNoFilesDir,
  updateUnsupportedDevice,
  updateNoReleaseInfo,
  updateCheckError,
  updateDownloadError,
  updateInstallError,
  subHwidLimit,
  subEmpty,
  coreUnavailable,
  coreDisabled,
  coreNoneAvailable,
}

/// A message in state (an error, a refusal), localized only where it is shown: a [code] with its [arg] that the app
/// tells apart, a string of the app's picked by [AppMessage.l10n] (a core's or a check's reason), or [text] that came
/// from outside the app's strings (native, a server, an exception).
final class AppMessage implements Exception {
  const AppMessage(MessageCode this.code, [this.arg]) : text = null, _pick = null;
  const AppMessage.text(String this.text) : code = null, arg = null, _pick = null;

  /// [pick] takes the string, with its arguments, from the strings of the language it is shown in.
  const AppMessage.l10n(String Function(AppLocalizations l) pick) : _pick = pick, code = null, arg = null, text = null;

  final MessageCode? code;
  final String? arg;
  final String? text;
  final String Function(AppLocalizations l)? _pick;

  String localize(AppLocalizations l) => switch (code) {
    null => _pick?.call(l) ?? text!,
    MessageCode.vpnConnectError => l.vpnConnectError,
    MessageCode.vpnConnectTimeout => l.vpnConnectTimeout,
    MessageCode.vpnNoConfigSelected => l.vpnNoConfigSelected,
    MessageCode.geositeMissing => l.geositeMissing(arg!),
    MessageCode.geoNoFilesDir => l.geoNoFilesDir,
    MessageCode.updateUnsupportedDevice => l.updateUnsupportedDevice(arg!),
    MessageCode.updateNoReleaseInfo => l.updateNoReleaseInfo,
    MessageCode.updateCheckError => l.updateCheckError(arg!),
    MessageCode.updateDownloadError => l.updateDownloadError(arg!),
    MessageCode.updateInstallError => l.updateInstallError,
    MessageCode.subHwidLimit => l.subHwidLimit,
    MessageCode.subEmpty => l.subEmpty,
    MessageCode.coreUnavailable => l.coreUnavailable,
    MessageCode.coreDisabled => l.coreDisabled,
    MessageCode.coreNoneAvailable => l.coreNoneAvailable,
  };

  /// For logs and `'$e'` in a catch: no context there.
  @override
  String toString() => localize(L10n.current);

  @override
  bool operator ==(Object other) =>
      other is AppMessage && other.code == code && other.arg == arg && other.text == text && other._pick == _pick;

  @override
  int get hashCode => Object.hash(code, arg, text, _pick);
}
