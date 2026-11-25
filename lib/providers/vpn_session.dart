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

/// Why the session failed on the Flutter side: a connect refused before native, rejected by it or timed out, or a
/// session stopped because no core runs its config. [attempt] — the native session it is about: native's states of
/// that session (the stop that follows) keep it on screen.
final class SessionFailure {
  const SessionFailure(this.reason, this.attempt);
  final String reason;
  final int attempt;
}

/// The session as `VpnNotifier` knows it: the last native snapshot, what Flutter waits for, and a failure Flutter
/// found itself. Immutable; [onNative] and [view] are pure.
final class VpnSession {
  const VpnSession({this.native = NativeSession.disconnected, this.pending, this.failure});

  final NativeSession native;
  final Pending? pending;
  final SessionFailure? failure;

  /// Native reported [s]: from an event, or from `getState` ([poll]: startup or resume). Null — dropped: while a
  /// Flutter connect waits, a snapshot of another attempt is an old session's late report, and an untagged poll may
  /// predate the connect reaching the service (an untagged event is a session started natively that replaced it).
  VpnSession? onNative(NativeSession s, {bool poll = false}) {
    final p = pending;
    if (p is PendingConnect && s.attempt != p.attempt && (s.attempt != 0 || poll)) return null;
    final keepPending = switch (p) {
      // Settled: connected, or off — the connect's own failure or a natively started session that replaced it.
      PendingConnect() => s.state == VpnState.connecting || s.state == VpnState.disconnecting,
      PendingDisconnect() => s.state == VpnState.disconnecting,
      null => false,
    };
    final f = failure;
    // A failure stays while native reports the same thing, or the stop of the session it is about; a session that
    // runs or holds the kill switch's sink replaces it.
    final keepFailure =
        f != null &&
        (s == native || (s.attempt == f.attempt && s.state != VpnState.connected && s.state != VpnState.blocked));
    return VpnSession(native: s, pending: keepPending ? p : null, failure: keepFailure ? f : null);
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
      if (native.state == VpnState.connected) return (state: VpnState.connected, error: f.reason);
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
