import 'app_settings.dart';
import 'heartbeat_settings.dart';
import 'routing_settings.dart';
import 'setting_limits.dart';
import 'xray_tuning.dart';

/// One field of [AppSettings] a screen edits: how to read it and how to write a value into given settings, nested
/// sections included. Screens name the field; building the new settings object is done here.
class SettingField<T> {
  final T Function(AppSettings s) read;
  final AppSettings Function(AppSettings s, T value) _write;

  const SettingField(this.read, this._write);

  AppSettings write(AppSettings s, T value) => _write(s, value);
}

/// A numeric field: a written value is clamped to [limits].
class IntSettingField extends SettingField<int> {
  final SettingLimits limits;

  const IntSettingField(super.read, super._write, this.limits);

  @override
  AppSettings write(AppSettings s, int value) => _write(s, limits.clamp(value));
}

SettingField<T> _routing<T>(T Function(RoutingSettings r) read, RoutingSettings Function(RoutingSettings r, T v) w) =>
    SettingField((s) => read(s.routing), (s, v) => s.copyWith(routing: w(s.routing, v)));

SettingField<T> _heartbeat<T>(
  T Function(HeartbeatSettings h) read,
  HeartbeatSettings Function(HeartbeatSettings h, T v) w,
) => SettingField((s) => read(s.heartbeat), (s, v) => s.copyWith(heartbeat: w(s.heartbeat, v)));

SettingField<T> _fragment<T>(
  T Function(FragmentSettings f) read,
  FragmentSettings Function(FragmentSettings f, T v) w,
) => SettingField((s) => read(s.fragment), (s, v) => s.copyWith(fragment: w(s.fragment, v)));

SettingField<T> _noise<T>(T Function(NoiseSettings n) read, NoiseSettings Function(NoiseSettings n, T v) w) =>
    SettingField((s) => read(s.noise), (s, v) => s.copyWith(noise: w(s.noise, v)));

SettingField<T> _mux<T>(T Function(MuxSettings m) read, MuxSettings Function(MuxSettings m, T v) w) =>
    SettingField((s) => read(s.mux), (s, v) => s.copyWith(mux: w(s.mux, v)));

/// The fields the settings screens edit one at a time.
abstract final class SettingFields {
  // General.
  static final autoConnect = SettingField((s) => s.autoConnect, (s, bool v) => s.copyWith(autoConnect: v));
  static final autoStartOnBoot = SettingField((s) => s.autoStartOnBoot, (s, bool v) => s.copyWith(autoStartOnBoot: v));
  static final automationEnabled = SettingField(
    (s) => s.automationEnabled,
    (s, bool v) => s.copyWith(automationEnabled: v),
  );
  static final showNotification = SettingField(
    (s) => s.showNotification,
    (s, bool v) => s.copyWith(showNotification: v),
  );
  static final fontScale = SettingField((s) => s.fontScale, (s, FontScale v) => s.copyWith(fontScale: v));
  static final updateChannel = SettingField(
    (s) => s.updateChannel,
    (s, UpdateChannel v) => s.copyWith(updateChannel: v),
  );
  static final logsEnabled = SettingField((s) => s.logsEnabled, (s, bool v) => s.copyWith(logsEnabled: v));
  static final pingWhileConnected = SettingField(
    (s) => s.pingWhileConnected,
    (s, bool v) => s.copyWith(pingWhileConnected: v),
  );

  // Subscriptions.
  static final subAutoRefresh = SettingField((s) => s.subAutoRefresh, (s, bool v) => s.copyWith(subAutoRefresh: v));
  static final subAutoRefreshHours = SettingField(
    (s) => s.subAutoRefreshHours,
    (s, int v) => s.copyWith(subAutoRefreshHours: v),
  );
  static final hwidEnabled = SettingField((s) => s.hwidEnabled, (s, bool v) => s.copyWith(hwidEnabled: v));
  static final subUserAgent = SettingField((s) => s.subUserAgent, (s, String v) => s.copyWith(subUserAgent: v));

  // Split tunneling.
  static final splitTunnelingEnabled = SettingField(
    (s) => s.splitTunnelingEnabled,
    (s, bool v) => s.copyWith(splitTunnelingEnabled: v),
  );
  static final vpnMode = SettingField((s) => s.vpnMode, (s, VpnMode v) => s.copyWith(vpnMode: v));
  static final allowTethering = SettingField((s) => s.allowTethering, (s, bool v) => s.copyWith(allowTethering: v));

  // Network.
  static final randomPort = SettingField((s) => s.randomPort, (s, bool v) => s.copyWith(randomPort: v));
  static final socksPort = IntSettingField(
    (s) => s.socksPort,
    (s, v) => s.copyWith(socksPort: v),
    AppSettings.socksPortLimits,
  );
  static final randomCredentials = SettingField(
    (s) => s.randomCredentials,
    (s, bool v) => s.copyWith(randomCredentials: v),
  );
  static final proxyOnly = SettingField((s) => s.proxyOnly, (s, bool v) => s.copyWith(proxyOnly: v));
  static final enableUdp = SettingField((s) => s.enableUdp, (s, bool v) => s.copyWith(enableUdp: v));
  static final allowIcmp = SettingField((s) => s.allowIcmp, (s, bool v) => s.copyWith(allowIcmp: v));
  static final blockQuic = SettingField((s) => s.blockQuic, (s, bool v) => s.copyWith(blockQuic: v));
  static final ipv6Enabled = SettingField((s) => s.ipv6Enabled, (s, bool v) => s.copyWith(ipv6Enabled: v));
  static final mtu = IntSettingField((s) => s.mtu, (s, v) => s.copyWith(mtu: v), AppSettings.mtuLimits);
  static final obsProbeIntervalSec = IntSettingField(
    (s) => s.obsProbeIntervalSec,
    (s, v) => s.copyWith(obsProbeIntervalSec: v),
    AppSettings.obsProbeIntervalLimits,
  );
  static final tlsFingerprint = SettingField(
    (s) => s.tlsFingerprint,
    (s, TlsFingerprint v) => s.copyWith(tlsFingerprint: v),
  );

  // Fragment and noise.
  static final fragmentEnabled = _fragment((f) => f.enabled, (f, bool v) => f.copyWith(enabled: v));
  static final fragmentPackets = _fragment((f) => f.packets, (f, String v) => f.copyWith(packets: v));
  static final fragmentLength = _fragment((f) => f.length, (f, String v) => f.copyWith(length: v));
  static final fragmentInterval = _fragment((f) => f.interval, (f, String v) => f.copyWith(interval: v));
  static final noiseEnabled = _noise((n) => n.enabled, (n, bool v) => n.copyWith(enabled: v));
  static final noiseType = _noise((n) => n.type, (n, NoiseType v) => n.copyWith(type: v));
  static final noisePacket = _noise((n) => n.packet, (n, String v) => n.copyWith(packet: v));
  static final noiseDelay = _noise((n) => n.delay, (n, String v) => n.copyWith(delay: v));

  // Mux.
  static final muxEnabled = _mux((m) => m.enabled, (m, bool v) => m.copyWith(enabled: v));
  static final muxConcurrency = IntSettingField(
    (s) => s.mux.concurrency,
    (s, v) => s.copyWith(mux: s.mux.copyWith(concurrency: v)),
    MuxSettings.concurrencyLimits,
  );
  static final muxXudpConcurrency = IntSettingField(
    (s) => s.mux.xudpConcurrency,
    (s, v) => s.copyWith(mux: s.mux.copyWith(xudpConcurrency: v)),
    MuxSettings.concurrencyLimits,
  );
  static final muxXudpProxyUdp443 = _mux((m) => m.xudpProxyUDP443, (m, XudpUdp443 v) => m.copyWith(xudpProxyUDP443: v));

  // Heartbeat.
  static final heartbeatProbe = _heartbeat((h) => h.probe, (h, HeartbeatProbe v) => h.copyWith(probe: v));
  static final heartbeatTarget = _heartbeat((h) => h.target, (h, HeartbeatTarget v) => h.copyWith(target: v));
  static final heartbeatCustomUrl = _heartbeat((h) => h.customUrl, (h, String v) => h.copyWith(customUrl: v));
  static final heartbeatFailureThreshold = IntSettingField(
    (s) => s.heartbeat.failureThreshold,
    (s, v) => s.copyWith(heartbeat: s.heartbeat.copyWith(failureThreshold: v)),
    HeartbeatSettings.failureThresholdLimits,
  );
  static final heartbeatFailAction = _heartbeat(
    (h) => h.failAction,
    (h, HeartbeatFailAction v) => h.copyWith(failAction: v),
  );
  static final heartbeatSwitchSource = _heartbeat(
    (h) => h.switchSource,
    (h, SwitchSource v) => h.copyWith(switchSource: v),
  );

  // Routing.
  static final sniffingEnabled = SettingField((s) => s.sniffingEnabled, (s, bool v) => s.copyWith(sniffingEnabled: v));
  static final killSwitchEnabled = SettingField(
    (s) => s.killSwitchEnabled,
    (s, bool v) => s.copyWith(killSwitchEnabled: v),
  );
  static final routingDirection = _routing((r) => r.direction, (r, RoutingDirection v) => r.copyWith(direction: v));
  static final bypassLocal = _routing((r) => r.bypassLocal, (r, bool v) => r.copyWith(bypassLocal: v));
  static final geoEnabled = _routing((r) => r.geoEnabled, (r, bool v) => r.copyWith(geoEnabled: v));
  static final geoCodes = _routing((r) => r.geoCodes, (r, List<String> v) => r.copyWith(geoCodes: v));
  static final domainEnabled = _routing((r) => r.domainEnabled, (r, bool v) => r.copyWith(domainEnabled: v));
  static final domainZones = _routing((r) => r.domainZones, (r, List<String> v) => r.copyWith(domainZones: v));
  static final geositeEnabled = _routing((r) => r.geositeEnabled, (r, bool v) => r.copyWith(geositeEnabled: v));
  static final geositeCodes = _routing((r) => r.geositeCodes, (r, List<String> v) => r.copyWith(geositeCodes: v));
  static final sitesEnabled = _routing((r) => r.sitesEnabled, (r, bool v) => r.copyWith(sitesEnabled: v));
  static final sites = _routing((r) => r.sites, (r, List<String> v) => r.copyWith(sites: v));
  static final adBlockEnabled = _routing((r) => r.adBlockEnabled, (r, bool v) => r.copyWith(adBlockEnabled: v));
  static final ruServicesEnabled = _routing(
    (r) => r.ruServicesEnabled,
    (r, bool v) => r.copyWith(ruServicesEnabled: v),
  );
}
