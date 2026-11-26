import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/protocols/xray/xray_engine.dart';
import 'package:teapodstream/providers/vpn_session.dart';

NativeSession _n(VpnState state, {int attempt = 0, String? error, bool reconnecting = false}) => NativeSession(
  state: state,
  attempt: attempt,
  error: error,
  reconnecting: reconnecting,
  socksPort: state == VpnState.connected ? 2080 : 0,
);

const _connect = PendingConnect(7);
const _disconnect = PendingDisconnect();
const _refusal = SessionFailure(AppMessage.text('bad'), 7);
const _timeout = SessionFailure(AppMessage.text('timeout'), 7, stopping: true);

/// What happens to the failure.
enum _F { none, kept, settled }

void main() {
  group('onNative', () {
    // (case, session, snapshot, poll, foreign, pending kept, failure)
    final cases = <(String, VpnSession, NativeSession, bool, bool, bool, _F)>[
      (
        'own outcome settles the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.connected, attempt: 7),
        false,
        false,
        false,
        _F.none,
      ),
      (
        'own failure settles the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.error, attempt: 7),
        false,
        false,
        false,
        _F.none,
      ),
      (
        'own start keeps the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.connecting, attempt: 7),
        false,
        false,
        true,
        _F.none,
      ),
      (
        'own restart keeps the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.connecting, attempt: 7, reconnecting: true),
        false,
        false,
        true,
        _F.none,
      ),
      (
        'another attempt is foreign: kept as native, the connect waits',
        const VpnSession(pending: _connect),
        _n(VpnState.error, attempt: 6),
        false,
        true,
        true,
        _F.none,
      ),
      (
        'an untagged event replaces the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.error),
        false,
        false,
        false,
        _F.none,
      ),
      (
        'an untagged poll is foreign',
        const VpnSession(pending: _connect),
        _n(VpnState.disconnected),
        true,
        true,
        true,
        _F.none,
      ),
      (
        'an own poll applies',
        const VpnSession(pending: _connect),
        _n(VpnState.connected, attempt: 7),
        true,
        false,
        false,
        _F.none,
      ),
      (
        'no connect: any attempt applies',
        const VpnSession(),
        _n(VpnState.connected, attempt: 3),
        false,
        false,
        false,
        _F.none,
      ),
      (
        'a disconnect waits through disconnecting',
        const VpnSession(pending: _disconnect),
        _n(VpnState.disconnecting, attempt: 3),
        false,
        false,
        true,
        _F.none,
      ),
      (
        'a disconnect ends on any other state',
        const VpnSession(pending: _disconnect),
        _n(VpnState.disconnected, attempt: 3),
        false,
        false,
        false,
        _F.none,
      ),
      (
        'a refusal stays on the same snapshot',
        const VpnSession(failure: _refusal),
        _n(VpnState.disconnected),
        true,
        false,
        false,
        _F.kept,
      ),
      (
        'any change replaces a refusal',
        VpnSession(native: _n(VpnState.connected, attempt: 3), failure: _refusal),
        _n(VpnState.connecting, attempt: 3, reconnecting: true),
        false,
        false,
        false,
        _F.none,
      ),
      (
        'a stopping failure stays while the stop runs',
        const VpnSession(failure: _timeout),
        _n(VpnState.disconnecting, attempt: 3),
        false,
        false,
        false,
        _F.kept,
      ),
      (
        'a stopping failure settles with the stop, whatever its tag',
        const VpnSession(failure: _timeout),
        _n(VpnState.disconnected, attempt: 3),
        false,
        false,
        false,
        _F.settled,
      ),
      (
        "the stopped session's late connected doesn't replace a stopping failure",
        const VpnSession(failure: _timeout),
        _n(VpnState.connected, attempt: 7),
        false,
        false,
        false,
        _F.kept,
      ),
      (
        'another session replaces a stopping failure',
        const VpnSession(failure: _timeout),
        _n(VpnState.connecting),
        false,
        false,
        false,
        _F.none,
      ),
      (
        "the kill switch's sink replaces a stopping failure",
        const VpnSession(failure: _timeout),
        _n(VpnState.blocked, attempt: 7),
        false,
        false,
        false,
        _F.none,
      ),
    ];
    for (final (name, session, snapshot, poll, foreign, pending, failure) in cases) {
      test(name, () {
        expect(session.foreign(snapshot, poll: poll), foreign);
        final next = session.onNative(snapshot, poll: poll);
        expect(next.native, snapshot);
        expect(next.pending, pending ? session.pending : isNull);
        switch (failure) {
          case _F.none:
            expect(next.failure, isNull);
          case _F.kept:
            expect(next.failure, same(session.failure));
          case _F.settled:
            expect((next.failure?.reason, next.failure?.stopping), (session.failure!.reason, false));
        }
      });
    }

    test('a settled stop keeps its reason only on the same snapshot', () {
      final stopped = const VpnSession(failure: _timeout).onNative(_n(VpnState.disconnected, attempt: 3));
      expect(stopped.onNative(_n(VpnState.disconnected, attempt: 3), poll: true).failure, isNotNull);
      // A new tile session (untagged, as the stopped one may have been) replaces it.
      expect(stopped.onNative(_n(VpnState.connecting)).failure, isNull);
    });
  });

  group('view', () {
    // (case, session, state, error)
    final cases = <(String, VpnSession, VpnState, String?)>[
      ('a pending connect', VpnSession(native: _n(VpnState.connected), pending: _connect), VpnState.connecting, null),
      ('a pending disconnect', const VpnSession(pending: _disconnect), VpnState.disconnecting, null),
      (
        'a disconnect for a failure',
        const VpnSession(pending: _disconnect, failure: SessionFailure(AppMessage.text('no core'), 1, stopping: true)),
        VpnState.disconnecting,
        'no core',
      ),
      (
        'a refused switch keeps the session',
        VpnSession(native: _n(VpnState.connected), failure: _refusal),
        VpnState.connected,
        'bad',
      ),
      (
        'a timed-out switch stops the session',
        VpnSession(native: _n(VpnState.connected), failure: _timeout),
        VpnState.error,
        'timeout',
      ),
      ('a refusal over an idle service', const VpnSession(failure: _refusal), VpnState.error, 'bad'),
      (
        'a failure while its session stops',
        VpnSession(native: _n(VpnState.disconnecting, attempt: 7), failure: _timeout),
        VpnState.error,
        'timeout',
      ),
      (
        'native names the reason after the timeout',
        VpnSession(
          native: _n(VpnState.error, attempt: 7, error: 'port busy'),
          failure: _timeout,
        ),
        VpnState.error,
        'port busy',
      ),
      (
        'native without a reason after the timeout',
        VpnSession(native: _n(VpnState.error, attempt: 7), failure: _timeout),
        VpnState.error,
        'timeout',
      ),
      (
        'native error with its reason',
        VpnSession(native: _n(VpnState.error, error: 'port busy')),
        VpnState.error,
        'port busy',
      ),
      ('native error without a reason', VpnSession(native: _n(VpnState.error)), VpnState.error, 'Connection error'),
      ('blocked with its reason', VpnSession(native: _n(VpnState.blocked, error: 'drop')), VpnState.blocked, 'drop'),
      ('blocked without a reason', VpnSession(native: _n(VpnState.blocked)), VpnState.blocked, null),
      (
        'a native restart is connecting',
        VpnSession(native: _n(VpnState.connecting, reconnecting: true)),
        VpnState.connecting,
        null,
      ),
      ('native states otherwise', VpnSession(native: _n(VpnState.connected)), VpnState.connected, null),
    ];
    for (final (name, session, state, error) in cases) {
      final message = error == 'Connection error'
          ? const AppMessage(MessageCode.vpnConnectError)
          : error == null
          ? null
          : AppMessage.text(error);
      test(name, () => expect(session.view, (state: state, error: message)));
    }
  });
}
