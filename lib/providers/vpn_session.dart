import '../core/interfaces/vpn_engine.dart';
import '../l10n/l10n.dart';
import '../protocols/xray/xray_engine.dart';

/// What Flutter waits native to report: the outcome of its own connect, or the end of a disconnect.
sealed class Pending {
  const Pending();
}

/// A Flutter connect waiting for its outcome; [attempt] — the id it sent to native.
final class PendingConnect extends Pending {
  const PendingConnect(this.attempt);
  final int attempt;
}

final class PendingDisconnect extends Pending {
  const PendingDisconnect();
}

/// Why the session failed on the Flutter side. A refusal (a connect refused before native or rejected by it) leaves
/// native as it is and shows over its current state. A [stopping] failure (a connect timed out, a session no core runs)
/// asked native to stop the session [attempt]: it shows as `error` through that session's reports and the stop's, whose
/// tag is native's last Flutter connect rather than the session's.
final class SessionFailure {
  const SessionFailure(this.reason, this.attempt, {this.stopping = false});
  final String reason;
  final int attempt;
  final bool stopping;
}

/// The session as `VpnNotifier` knows it: the last native snapshot, what Flutter waits for, and a failure Flutter
/// found itself. Immutable; [onNative] and [view] are pure.
final class VpnSession {
  const VpnSession({this.native = NativeSession.disconnected, this.pending, this.failure});

  final NativeSession native;
  final Pending? pending;
  final SessionFailure? failure;

  /// [s] is not about the connect Flutter waits for: a snapshot of another attempt is an old session's late report,
  /// and an untagged poll may predate the connect reaching the service (an untagged event is a session started
  /// natively that replaced it).
  bool foreign(NativeSession s, {bool poll = false}) {
    final p = pending;
    return p is PendingConnect && s.attempt != p.attempt && (s.attempt != 0 || poll);
  }

  /// Native reported [s]: from an event, or from `getState` ([poll]: startup or resume). A [foreign] report is still
  /// native's latest state (what a refused switch leaves running), but doesn't settle the connect.
  VpnSession onNative(NativeSession s, {bool poll = false}) {
    final p = pending;
    if (foreign(s, poll: poll)) return VpnSession(native: s, pending: p, failure: failure);
    final keepPending = switch (p) {
      // Settled: connected, or off — the connect's own failure or a natively started session that replaced it.
      PendingConnect() => s.state == VpnState.connecting || s.state == VpnState.disconnecting,
      PendingDisconnect() => s.state == VpnState.disconnecting,
      null => false,
    };
    final f = failure;
    // A refusal stays while native reports the same thing. A stopping failure stays through the stop and the stopped
    // session's own reports; another session or the kill switch's sink replaces it.
    final stop = s.state == VpnState.disconnecting || s.state == VpnState.disconnected || s.state == VpnState.error;
    final keepFailure =
        f != null && (s == native || (f.stopping && s.state != VpnState.blocked && (stop || s.attempt == f.attempt)));
    // Once the stop is done, the stopped session's tag means nothing (a tile session reuses 0): only the same
    // snapshot keeps the reason.
    final stopped = keepFailure && f.stopping && (s.state == VpnState.disconnected || s.state == VpnState.error);
    return VpnSession(
      native: s,
      pending: keepPending ? p : null,
      failure: !keepFailure ? null : (stopped ? SessionFailure(f.reason, f.attempt) : f),
    );
  }

  /// The state and the reason the UI shows.
  ({VpnState state, String? error}) get view {
    final f = failure;
    switch (pending) {
      case PendingConnect():
        return (state: VpnState.connecting, error: null);
      case PendingDisconnect():
        return (state: VpnState.disconnecting, error: f?.reason);
      case null:
    }
    if (f != null) {
      // A switch refused before native: the old session runs on.
      if (!f.stopping && native.state == VpnState.connected) return (state: VpnState.connected, error: f.reason);
      // Native may name the reason after Flutter's timeout already did.
      return (state: VpnState.error, error: native.state == VpnState.error ? native.error ?? f.reason : f.reason);
    }
    return switch (native.state) {
      VpnState.error => (state: VpnState.error, error: native.error ?? L10n.current.vpnConnectError),
      VpnState.blocked => (state: VpnState.blocked, error: native.error),
      final s => (state: s, error: null),
    };
  }
}
