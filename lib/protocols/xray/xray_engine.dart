import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_stats.dart';
import '../../core/models/vpn_log_entry.dart';
import 'xray_config_builder.dart';

/// XrayEngine communicates with native Android VPN service via MethodChannel.
/// The native side:
///   1. Creates a TUN interface via VpnService API
///   2. Starts xray with the provided JSON config (SOCKS inbound with auth)
///   3. Starts tun2socks to bridge TUN → xray SOCKS (using the generated auth)
///   4. Handles split tunneling via VpnService app allow/deny lists
class XrayEngine implements VpnEngine {
  static const _channel =
      MethodChannel(AppConstants.methodChannel);
  static const _eventChannel =
      EventChannel('${AppConstants.methodChannel}/events');

  final _stateController = StreamController<VpnState>.broadcast();
  final _statsController = StreamController<VpnStats>.broadcast();
  final _logController = StreamController<VpnLogEntry>.broadcast();

  VpnState _state = VpnState.disconnected;
  VpnStats _stats = const VpnStats();
  StreamSubscription<dynamic>? _eventSub;
  Timer? _statsTimer;
  DateTime? _connectedAt;

  @override
  String get protocolName => 'xray';

  @override
  Stream<VpnState> get stateStream => _stateController.stream;

  @override
  Stream<VpnStats> get statsStream => _statsController.stream;

  @override
  Stream<VpnLogEntry> get logStream => _logController.stream;

  @override
  VpnState get currentState => _state;

  @override
  VpnStats get currentStats => _stats;

  XrayEngine() {
    _setupEventChannel();
  }

  void _setupEventChannel() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (dynamic error) {
        _addLog(VpnLogEntry.error('Event channel error: $error'));
      },
    );
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'state':
        final stateStr = event['value'] as String?;
        final newState = _parseState(stateStr);
        _setState(newState);
      case 'log':
        final level = event['level'] as String? ?? 'info';
        final msg = event['message'] as String? ?? '';
        _addLog(VpnLogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.values.firstWhere(
            (e) => e.name == level,
            orElse: () => LogLevel.info,
          ),
          message: msg,
          source: 'xray',
        ));
      case 'stats':
        _handleStats(event);
    }
  }

  void _handleStats(Map<String, dynamic> event) {
    final upload = event['upload'] as int? ?? 0;
    final download = event['download'] as int? ?? 0;
    final uploadSpeed = event['uploadSpeed'] as int? ?? 0;
    final downloadSpeed = event['downloadSpeed'] as int? ?? 0;

    final duration = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!)
        : Duration.zero;

    _stats = VpnStats(
      uploadBytes: upload,
      downloadBytes: download,
      uploadSpeedBps: uploadSpeed,
      downloadSpeedBps: downloadSpeed,
      connectedDuration: duration,
    );
    _statsController.add(_stats);
  }

  VpnState _parseState(String? s) {
    return switch (s) {
      'connecting' => VpnState.connecting,
      'connected' => VpnState.connected,
      'disconnecting' => VpnState.disconnecting,
      'disconnected' => VpnState.disconnected,
      'error' => VpnState.error,
      _ => VpnState.disconnected,
    };
  }

  void _setState(VpnState newState) {
    _state = newState;
    _stateController.add(newState);

    if (newState == VpnState.connected) {
      _connectedAt = DateTime.now();
      _startStatsPolling();
      _addLog(VpnLogEntry.info('VPN connected'));
    } else if (newState == VpnState.disconnected ||
        newState == VpnState.error) {
      _connectedAt = null;
      _stopStatsPolling();
      if (newState == VpnState.disconnected) {
        _addLog(VpnLogEntry.info('VPN disconnected'));
      }
    }
  }

  void _startStatsPolling() {
    _stopStatsPolling(); // Cancel any existing timer first
    _statsTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.statsUpdateInterval),
      (_) => _fetchStats(),
    );
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Restarts stream subscriptions after app wake from background.
  /// Called by vpn_provider when syncNativeState detects connected state.
  Future<void> reconnectStreams() async {
    _startStatsPolling();
    // Fetch stats immediately instead of waiting for next tick
    await _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStats');
      if (result != null) {
        _handleStats(Map<String, dynamic>.from(result));
      }
    } catch (_) {}
  }

  void _addLog(VpnLogEntry entry) {
    _logController.add(entry);
  }

  @override
  Future<void> connect(VpnConfig config, VpnEngineOptions options) async {
    if (_state == VpnState.connected || _state == VpnState.connecting) return;

    _setState(VpnState.connecting);
    _addLog(VpnLogEntry.info(
        'Connecting to ${config.name} (${config.address}:${config.port})'));
    _addLog(VpnLogEntry.debug(
        'SOCKS port: ${options.socksPort}, UDP: ${options.enableUdp}'));
    _addLog(VpnLogEntry.debug(
        'DNS mode: ${options.dnsMode}, server: ${options.dnsServer.address}'));

    try {
      final xrayConfig = XrayConfigBuilder.buildJson(config, options);
      _addLog(VpnLogEntry.debug('Xray config generated (${xrayConfig.length} bytes)'));

      await _channel.invokeMethod('connect', {
        'xrayConfig': xrayConfig,
        'socksPort': options.socksPort,
        'socksUser': options.socksUser,
        'socksPassword': options.socksPassword,
        'excludedPackages': options.excludedPackages.toList(),
        'includedPackages': options.includedPackages.toList(),
        'vpnMode': options.vpnMode.name,
        'tunAddress': AppConstants.tunAddress,
        'tunNetmask': AppConstants.tunNetmask,
        'tunMtu': AppConstants.tunMtu,
        'tunDns': AppConstants.tunDns,
        'enableUdp': options.enableUdp,
      });
    } on PlatformException catch (e) {
      _setState(VpnState.error);
      _addLog(VpnLogEntry.error('Connection failed: ${e.message}'));
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == VpnState.disconnected ||
        _state == VpnState.disconnecting) {
      return;
    }

    _setState(VpnState.disconnecting);
    _addLog(VpnLogEntry.info('Disconnecting...'));

    try {
      await _channel.invokeMethod('disconnect');
    } on PlatformException catch (e) {
      _addLog(VpnLogEntry.error('Disconnect error: ${e.message}'));
      _setState(VpnState.disconnected);
    }
  }

  @override
  Future<int?> pingConfig(VpnConfig config) async {
    try {
      final result = await _channel.invokeMethod<int>('ping', {
        'address': config.address,
        'port': config.port,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  bool supportsConfig(VpnConfig config) {
    return true; // xray supports all common protocols
  }

  Future<Map<String, String>> getBinaryVersions() async {
    try {
      final result = await _channel.invokeMethod<Map>('getBinaryVersions');
      if (result != null) {
        return Map<String, String>.from(result);
      }
    } catch (_) {}
    return {'xray': '—', 'tun2socks': '—'};
  }

  /// Generate cryptographically random SOCKS credentials
  static ({String user, String password}) generateSocksCredentials() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    String randomString(int len) =>
        List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();

    return (
      user: 'u${randomString(8)}',
      password: randomString(AppConstants.socksAuthPasswordLength),
    );
  }

  void dispose() {
    _eventSub?.cancel();
    _statsTimer?.cancel();
    _stateController.close();
    _statsController.close();
    _logController.close();
  }
}
