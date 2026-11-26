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
}

/// A message in state (an error, a refusal): a [code] with its [arg], localized only where it is shown, or [text]
/// that came as text from outside the app's strings (native, a server, a core's check, an exception).
final class AppMessage implements Exception {
  const AppMessage(MessageCode this.code, [this.arg]) : text = null;
  const AppMessage.text(String this.text) : code = null, arg = null;

  final MessageCode? code;
  final String? arg;
  final String? text;

  String localize(AppLocalizations l) => switch (code) {
    null => text!,
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
  };

  /// For logs and `'$e'` in a catch: no context there.
  @override
  String toString() => localize(L10n.current);

  @override
  bool operator ==(Object other) => other is AppMessage && other.code == code && other.arg == arg && other.text == text;

  @override
  int get hashCode => Object.hash(code, arg, text);
}
