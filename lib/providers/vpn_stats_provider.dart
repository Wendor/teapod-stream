import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/vpn_stats.dart';
import '../protocols/xray/xray_engine.dart';
import 'vpn_provider.dart';

/// Traffic of the running session: `getStats` every second while connected (paused in the background), carrying the
/// chart's speed history while the home tab shows it — one channel call per tick. Reset when the session ends.
class VpnStatsNotifier extends Notifier<VpnStats> {
  late XrayEngine _engine;
  Timer? _poller;

  /// false — the app is in the background ([pause]): no polling, also when a session connects meanwhile.
  bool _foreground = true;

  /// true — the home tab is on screen; chart history is pulled only then.
  bool _chartVisible = true;

  /// Chart history: native returns only points after `_historySeq` of epoch
  /// `_historyEpoch`; any lag (background, hidden tab longer than the buffer, a new
  /// session) arrives in one response — the chart catches up immediately.
  static const _maxHistory = 300;
  int _historyEpoch = -1;
  int _historySeq = 0;
  bool _historyFetching = false;

  /// The last list set: if state holds a different one, it was reset (disconnect,
  /// timeout) — nothing to append to, the whole buffer is needed.
  List<SpeedPoint> _history = const [];

  /// False after disposal too: a queued [resume] or a channel answer may complete after it.
  bool get _connected => ref.mounted && ref.read(vpnProvider).isConnected;

  @override
  VpnStats build() {
    _engine = ref.read(xrayEngineProvider);
    final sub = XrayEngine.events.listen((dynamic event) {
      if (event is Map && event['type'] == 'statsHistory') _applyHistory(Map<Object?, Object?>.from(event));
    });
    ref.listen(vpnProvider.select((s) => s.isConnected), (_, connected) {
      if (connected) {
        _start();
      } else {
        _stop();
        state = const VpnStats();
      }
    });
    ref.onDispose(() {
      sub.cancel();
      _poller?.cancel();
    });
    if (_connected) Future.microtask(_start);
    return const VpnStats();
  }

  /// Back from the background: polling again while connected.
  void resume() {
    _foreground = true;
    _start();
  }

  /// No per-second channel calls in the background; [resume] restarts them.
  void pause() {
    _foreground = false;
    _stop();
  }

  /// Polls while connected in the foreground; history right away, not on the next tick.
  void _start() {
    if (!_foreground || !_connected) return;
    if (_poller?.isActive != true) {
      _poller = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!_connected) return;
        try {
          // History is needed only for the chart; it comes in the same call. Not while a catch-up is in flight.
          final withHistory = _chartVisible && !_historyFetching;
          final s = await _engine.getStats(history: withHistory ? (epoch: _historyEpoch, since: _historySeq) : null);
          _apply(s);
          if (s.history case final history?) _applyHistory(history);
        } catch (_) {}
      });
    }
    if (_chartVisible) _pullHistory().ignore();
  }

  void _stop() {
    _poller?.cancel();
    _poller = null;
  }

  /// Called from app.dart on tab change: chart history is pulled
  /// only while home is visible; on return — an immediate catch-up.
  void setChartVisible(bool visible) {
    if (_chartVisible == visible) return;
    _chartVisible = visible;
    if (visible && _connected) _pullHistory().ignore();
  }

  void _apply(({int upload, int download, int uploadSpeed, int downloadSpeed, Map<Object?, Object?>? history}) s) {
    // A late response after a drop.
    if (!_connected) return;
    final connectedAt = ref.read(vpnProvider).connectedAt;
    // Always update speed, even if bytes haven't changed (for re-connect)
    state = state.copyWith(
      uploadBytes: s.upload,
      downloadBytes: s.download,
      uploadSpeedBps: s.uploadSpeed,
      downloadSpeedBps: s.downloadSpeed,
      connectedDuration: connectedAt != null ? DateTime.now().difference(connectedAt) : Duration.zero,
    );
  }

  Future<void> _pullHistory() async {
    if (_historyFetching) return;
    _historyFetching = true;
    try {
      final r = await _engine.getStatsHistory(_historyEpoch, _historySeq);
      if (r != null) _applyHistory(r);
    } finally {
      _historyFetching = false;
    }
  }

  /// Native response: `full` replaces the history, otherwise points are appended — only if
  /// they continue the current one (`from == _historySeq`), so a late response doesn't duplicate them.
  /// Any mismatch — the next request asks for the whole buffer.
  void _applyHistory(Map<Object?, Object?> r) {
    if (!_connected) return;
    final full = r['full'] == true;
    final epoch = (r['epoch'] as num?)?.toInt() ?? -1;
    final from = (r['from'] as num?)?.toInt() ?? 0;
    if (!full && (epoch != _historyEpoch || from != _historySeq || !identical(state.speedHistory, _history))) {
      _historyEpoch = -1;
      return;
    }
    final points = (r['history'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((m) => SpeedPoint.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    _historyEpoch = epoch;
    _historySeq = (r['seq'] as num?)?.toInt() ?? 0;
    if (!full && points.isEmpty) return;
    final merged = full ? points : [..._history, ...points];
    _history = merged.length > _maxHistory ? merged.sublist(merged.length - _maxHistory) : merged;
    state = state.copyWith(speedHistory: _history);
  }
}

final vpnStatsProvider = NotifierProvider<VpnStatsNotifier, VpnStats>(VpnStatsNotifier.new);
