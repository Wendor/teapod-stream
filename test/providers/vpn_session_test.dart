import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('onNative', () {
    // (case, session, snapshot, poll, kept pending, kept failure); dropped → null.
    final cases = <(String, VpnSession, NativeSession, bool, ({bool pending, bool failure})?)>[
      (
        'own outcome settles the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.connected, attempt: 7),
        false,
        (pending: false, failure: false),
      ),
      (
        'own failure settles the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.error, attempt: 7),
        false,
        (pending: false, failure: false),
      ),
      (
        'own start keeps the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.connecting, attempt: 7),
        false,
        (pending: true, failure: false),
      ),
      (
        'own restart keeps the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.connecting, attempt: 7, reconnecting: true),
        false,
        (pending: true, failure: false),
      ),
      ('another attempt is dropped', const VpnSession(pending: _connect), _n(VpnState.error, attempt: 6), false, null),
      (
        'an untagged event replaces the connect',
        const VpnSession(pending: _connect),
        _n(VpnState.error),
        false,
        (pending: false, failure: false),
      ),
      ('an untagged poll is dropped', const VpnSession(pending: _connect), _n(VpnState.disconnected), true, null),
      (
        'an own poll applies',
        const VpnSession(pending: _connect),
        _n(VpnState.connected, attempt: 7),
        true,
        (pending: false, failure: false),
      ),
      (
        'no connect: any attempt applies',
        const VpnSession(),
        _n(VpnState.connected, attempt: 3),
        false,
        (pending: false, failure: false),
      ),
      (
        'a disconnect waits through disconnecting',
        const VpnSession(pending: _disconnect),
        _n(VpnState.disconnecting, attempt: 3),
        false,
        (pending: true, failure: false),
      ),
      (
        'a disconnect ends on any other state',
        const VpnSession(pending: _disconnect),
        _n(VpnState.disconnected, attempt: 3),
        false,
        (pending: false, failure: false),
      ),
      (
        'a failure stays through its session\'s stop',
        const VpnSession(failure: SessionFailure('t', 7)),
        _n(VpnState.disconnected, attempt: 7),
        false,
        (pending: false, failure: true),
      ),
      (
        'a failure stays on the same snapshot',
        const VpnSession(failure: SessionFailure('t', 9)),
        _n(VpnState.disconnected),
        true,
        (pending: false, failure: true),
      ),
      (
        'another session replaces a failure',
        const VpnSession(failure: SessionFailure('t', 7)),
        _n(VpnState.connecting),
        false,
        (pending: false, failure: false),
      ),
      (
        'its session connected replaces a failure',
        const VpnSession(failure: SessionFailure('t', 7)),
        _n(VpnState.connected, attempt: 7),
        false,
        (pending: false, failure: false),
      ),
      (
        'the kill switch\'s sink replaces a failure',
        const VpnSession(failure: SessionFailure('t', 7)),
        _n(VpnState.blocked, attempt: 7),
        false,
        (pending: false, failure: false),
      ),
    ];
    for (final (name, session, snapshot, poll, kept) in cases) {
      test(name, () {
        final next = session.onNative(snapshot, poll: poll);
        if (kept == null) return expect(next, isNull);
        expect(next!.native, snapshot);
        expect(next.pending, kept.pending ? session.pending : isNull);
        expect(next.failure, kept.failure ? session.failure : isNull);
      });
    }
  });

  group('view', () {
    // (case, session, state, error)
    final cases = <(String, VpnSession, VpnState, String?)>[
      ('a pending connect', VpnSession(native: _n(VpnState.connected), pending: _connect), VpnState.connecting, null),
      ('a pending disconnect', const VpnSession(pending: _disconnect), VpnState.disconnecting, null),
      (
        'a disconnect for a failure',
        const VpnSession(pending: _disconnect, failure: SessionFailure('no core', 1)),
        VpnState.disconnecting,
        'no core',
      ),
      (
        'a refused switch keeps the session',
        VpnSession(native: _n(VpnState.connected), failure: const SessionFailure('bad', 1)),
        VpnState.connected,
        'bad',
      ),
      (
        'a failure over an idle service',
        const VpnSession(failure: SessionFailure('timeout', 1)),
        VpnState.error,
        'timeout',
      ),
      (
        'a failure while its session stops',
        VpnSession(native: _n(VpnState.disconnecting, attempt: 1), failure: const SessionFailure('timeout', 1)),
        VpnState.error,
        'timeout',
      ),
      (
        'native names the reason after the timeout',
        VpnSession(
          native: _n(VpnState.error, attempt: 1, error: 'port busy'),
          failure: const SessionFailure('timeout', 1),
        ),
        VpnState.error,
        'port busy',
      ),
      (
        'native without a reason after the timeout',
        VpnSession(native: _n(VpnState.error, attempt: 1), failure: const SessionFailure('timeout', 1)),
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
      test(name, () => expect(session.view, (state: state, error: error)));
    }
  });
}
