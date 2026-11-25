import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/log_service.dart';
import '../protocols/xray/xray_engine.dart';
import 'settings_provider.dart';

/// The native log file (`vpn_log.txt`) and tun2socks diagnostics; the in-app log is [LogService].
class NativeLogs {
  NativeLogs(this._ref);

  final Ref _ref;

  XrayEngine get _engine => _ref.read(xrayEngineProvider);

  /// At startup. Native persists logsEnabled in its own prefs — resynced in case they diverged (fresh install with
  /// restored Flutter prefs, etc.). The log history (previous + current session files) is restored even when
  /// disconnected — needed to diagnose failures that ended the last session.
  Future<void> restore() async {
    final settings = await _ref.read(settingsProvider.future);
    await _engine.setLogsEnabled(settings.logsEnabled);
    final entries = await _engine.getLogs();
    if (entries.isNotEmpty) _ref.read(logServiceProvider.notifier).loadFromEntries(entries);
  }

  Future<void> setLogsEnabled(bool enabled) => _engine.setLogsEnabled(enabled);

  Future<String?> getLogFilePath() => _engine.getLogFilePath();

  /// Dumps a tun2socks diagnostics snapshot into the app log.
  Future<void> dumpTunnelDiag() async {
    final diag = await _engine.getTunnelDiag();
    _ref
        .read(logServiceProvider.notifier)
        .addInfo(diag.isEmpty ? 'tunnel diag: not running' : 'tunnel diag: $diag', source: 'diag');
  }

  Future<void> clear() => _engine.clearLogs();
}

final nativeLogsProvider = Provider<NativeLogs>(NativeLogs.new);
