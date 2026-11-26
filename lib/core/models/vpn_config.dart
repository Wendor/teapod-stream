import 'dart:convert';

import 'app_message.dart';

import 'core_kind.dart';
import 'protocol_settings.dart';

enum VpnProtocol {
  vless('VLESS', 'VLESS'),
  vmess('VMess', 'VMESS'),
  trojan('Trojan', 'TROJAN'),
  shadowsocks('Shadowsocks', 'SS'),
  hysteria2('Hysteria2', 'HY2'),
  wireguard('WireGuard', 'WG'),
  ssh('SSH', 'SSH'),
  naive('NaiveProxy', 'NAIVE');

  const VpnProtocol(this.label, this.shortTag);

  final String label;

  /// Short label in server lists.
  final String shortTag;

  /// Why Xray cores refuse protocols that only sing-box has.
  AppMessage get singBoxOnlyReason => AppMessage.l10n((l) => l.coreSingBoxOnly(label));

  /// Protocols whose parameters live in [VpnConfig.protocolSettings].
  bool get hasProtocolSettings => this == wireguard || this == ssh || this == naive;
}

enum VpnSecurity { none, tls, reality }

enum VpnTransport { tcp, ws, grpc, http2, quic, xhttp, httpupgrade, splithttp }

class VpnConfig {
  final String id;
  final String name;
  final VpnProtocol protocol;
  final String address;
  final int port;
  final String uuid;
  final VpnSecurity security;
  final VpnTransport transport;
  final String? sni;
  final String? wsPath;
  final String? wsHost;
  final String? grpcServiceName;
  final String? fingerprint;
  final String? publicKey; // for Reality
  final String? shortId; // for Reality
  final String? spiderX; // for Reality
  final String? postQuantumKey; // for Reality post-quantum (pqv)
  final String? flow;
  final String? encryption; // for VLESS: "none"
  final String? alterId; // for VMess
  final String? method; // Shadowsocks cipher; VMess `scy`
  final String? password; // for Trojan/Shadowsocks
  final DateTime createdAt;
  final String? rawUri;
  final int? latencyMs;
  final DateTime? lastPingedAt;
  final String? subscriptionId; // ID of the subscription this config came from
  final String? ssPrefix; // hex-encoded prefix bytes for Outline Shadowsocks (e.g. "160301...")
  final String? obfsPassword; // for Hysteria2 salamander obfuscation
  /// Hysteria2 port hopping: the URI's port range/list ("20000-30000",
  /// "443,5000-6000") or `mport`. [port] keeps the first port.
  final String? hopPorts;
  final bool allowInsecure;
  final String? pinSHA256;
  final String? xhttpMode; // for xhttp transport: "auto", "packet-up", "stream-up", "stream-one"
  final Map<String, dynamic>? xhttpExtra; // raw extra object passed to xhttpSettings
  final Map<String, dynamic>? finalmask; // xray finalmask stream setting (fm param in URL)
  final String? alpn; // comma-separated ALPN list, e.g. "h3" or "h2,http/1.1"
  final String? ech; // base64 ECH ConfigList for TLS Encrypted Client Hello
  final String? rawXrayConfig; // pre-built xray JSON config (from managed subscriptions)
  /// WireGuard/SSH/Naive parameters; null for other protocols.
  final ProtocolSettings? protocolSettings;

  /// Core pinned to the profile; null — by the priority in settings.
  final CoreKind? core;

  /// TCP header camouflage of the link (`headerType`, VMess `type`), lower case; null — none.
  final String? headerType;

  /// Shadowsocks SIP003 `plugin` of the link.
  final String? plugin;

  /// `mux=on|off` in the link: Mux for this server regardless of the global setting; null — not set.
  final bool? mux;

  /// Hysteria2 obfuscation with [obfsPassword]: `salamander` or `gecko`; null — none.
  final String? obfs;

  /// Gecko packet sizes `(min, max)`; null unless [obfs] is `gecko`.
  final (int, int)? geckoPacketSize;

  /// Stored before the link fields above were in the model: they are read again from [rawUri] when loaded. Stays
  /// set while the parser refuses [rawUri], so the check repeats on every load.
  final bool needsLinkFields;

  /// Why the parser refuses [rawUri] (an unknown security, transport or obfuscation) of a config stored before it
  /// did; not stored. Such a config doesn't connect: [validate] returns it, and no core takes it.
  final AppMessage? linkRejection;

  static const _linkProtocols = {
    VpnProtocol.vless,
    VpnProtocol.vmess,
    VpnProtocol.trojan,
    VpnProtocol.shadowsocks,
    VpnProtocol.hysteria2,
  };

  const VpnConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    required this.uuid,
    required this.security,
    required this.transport,
    this.sni,
    this.wsPath,
    this.wsHost,
    this.grpcServiceName,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.postQuantumKey,
    this.flow,
    this.encryption,
    this.alterId,
    this.method,
    this.password,
    required this.createdAt,
    this.rawUri,
    this.latencyMs,
    this.lastPingedAt,
    this.subscriptionId,
    this.ssPrefix,
    this.obfsPassword,
    this.hopPorts,
    this.allowInsecure = false,
    this.pinSHA256,
    this.xhttpMode,
    this.xhttpExtra,
    this.finalmask,
    this.alpn,
    this.ech,
    this.rawXrayConfig,
    this.protocolSettings,
    this.core,
    this.headerType,
    this.plugin,
    this.mux,
    this.obfs,
    this.geckoPacketSize,
    this.needsLinkFields = false,
    this.linkRejection,
  });

  /// Protocol label in lists: AmneziaWG differs from WireGuard.
  String get protoTag => switch (protocolSettings) {
    WireGuardSettings(amnezia: != null) => 'AWG',
    _ => protocol.shortTag,
  };

  /// TCP with HTTP camouflage: without the header the server drops the connection.
  bool get tcpHttpHeader => transport == VpnTransport.tcp && protocol != VpnProtocol.hysteria2 && headerType == 'http';

  AppMessage? validate() {
    if (linkRejection != null) return linkRejection;
    if (rawXrayConfig != null) return null;
    if (protocol.hasProtocolSettings && protocolSettings?.type != protocol.name) {
      return AppMessage.l10n((l) => l.validateNoProtocolParams(protocol.label));
    }
    if (address.isEmpty) return AppMessage.l10n((l) => l.validateEmptyAddress);
    if (port < 1 || port > 65535) return AppMessage.l10n((l) => l.validateInvalidPort(port));
    if (protocol == VpnProtocol.vless || protocol == VpnProtocol.vmess) {
      if (uuid.isEmpty) return AppMessage.l10n((l) => l.validateEmptyUuid);
    }
    if ((protocol == VpnProtocol.shadowsocks || protocol == VpnProtocol.trojan || protocol == VpnProtocol.hysteria2) &&
        (password == null || password!.isEmpty)) {
      return AppMessage.l10n((l) => l.validateEmptyPassword);
    }
    return null;
  }

  /// `address:port`: what pings measure and are stored by.
  String get endpoint => '$address:$port';

  VpnConfig copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    int? latencyMs,
    bool clearLatency = false,
    CoreKind? core,
    bool clearCore = false,
    DateTime? lastPingedAt,
    String? subscriptionId,
    bool? allowInsecure,
    String? pinSHA256,
    String? rawUri,
    AppMessage? linkRejection,
  }) {
    return VpnConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol,
      address: address,
      port: port,
      uuid: uuid,
      security: security,
      transport: transport,
      sni: sni,
      wsPath: wsPath,
      wsHost: wsHost,
      grpcServiceName: grpcServiceName,
      fingerprint: fingerprint,
      publicKey: publicKey,
      shortId: shortId,
      spiderX: spiderX,
      postQuantumKey: postQuantumKey,
      flow: flow,
      encryption: encryption,
      alterId: alterId,
      method: method,
      password: password,
      createdAt: createdAt ?? this.createdAt,
      rawUri: rawUri ?? this.rawUri,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
      lastPingedAt: lastPingedAt ?? this.lastPingedAt,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      ssPrefix: ssPrefix,
      obfsPassword: obfsPassword,
      hopPorts: hopPorts,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      pinSHA256: pinSHA256 ?? this.pinSHA256,
      xhttpMode: xhttpMode,
      xhttpExtra: xhttpExtra,
      finalmask: finalmask,
      alpn: alpn,
      ech: ech,
      rawXrayConfig: rawXrayConfig,
      protocolSettings: protocolSettings,
      core: clearCore ? null : (core ?? this.core),
      headerType: headerType,
      plugin: plugin,
      mux: mux,
      obfs: obfs,
      geckoPacketSize: geckoPacketSize,
      needsLinkFields: needsLinkFields,
      linkRejection: linkRejection ?? this.linkRejection,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'address': address,
    'port': port,
    'uuid': uuid,
    'security': security.name,
    'transport': transport.name,
    'sni': sni,
    'wsPath': wsPath,
    'wsHost': wsHost,
    'grpcServiceName': grpcServiceName,
    'fingerprint': fingerprint,
    'publicKey': publicKey,
    'shortId': shortId,
    'spiderX': spiderX,
    'postQuantumKey': postQuantumKey,
    'flow': flow,
    'encryption': encryption,
    'alterId': alterId,
    'method': method,
    'password': password,
    'createdAt': createdAt.toIso8601String(),
    'rawUri': rawUri,
    'latencyMs': latencyMs,
    'lastPingedAt': lastPingedAt?.toIso8601String(),
    'subscriptionId': subscriptionId,
    'ssPrefix': ssPrefix,
    'obfsPassword': obfsPassword,
    'hopPorts': hopPorts,
    'allowInsecure': allowInsecure,
    'pinSHA256': pinSHA256,
    'xhttpMode': xhttpMode,
    'xhttpExtra': xhttpExtra,
    'finalmask': finalmask,
    'alpn': alpn,
    'ech': ech,
    'rawXrayConfig': rawXrayConfig,
    'protocolSettings': ?protocolSettings?.toJson(),
    'core': ?core?.name,
    'headerType': ?headerType,
    'plugin': ?plugin,
    'mux': ?mux,
    'obfs': ?obfs,
    'geckoPacketSize': ?switch (geckoPacketSize) {
      (final min, final max) => [min, max],
      null => null,
    },
    if (!needsLinkFields) 'linkFields': true,
  };

  factory VpnConfig.fromJson(Map<String, dynamic> json) {
    final protocol = VpnProtocol.values.firstWhere((e) => e.name == json['protocol'], orElse: () => VpnProtocol.vless);
    final rawUri = json['rawUri'] as String?;
    final rawXrayConfig = json['rawXrayConfig'] as String?;
    final gecko = (json['geckoPacketSize'] as List<dynamic>?)?.cast<int>();
    return VpnConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      protocol: protocol,
      address: json['address'] as String,
      port: json['port'] as int,
      uuid: json['uuid'] as String? ?? '',
      security: VpnSecurity.values.firstWhere((e) => e.name == json['security'], orElse: () => VpnSecurity.none),
      transport: VpnTransport.values.firstWhere((e) => e.name == json['transport'], orElse: () => VpnTransport.tcp),
      sni: json['sni'] as String?,
      wsPath: json['wsPath'] as String?,
      wsHost: json['wsHost'] as String?,
      grpcServiceName: json['grpcServiceName'] as String?,
      fingerprint: json['fingerprint'] as String?,
      publicKey: json['publicKey'] as String?,
      shortId: json['shortId'] as String?,
      spiderX: json['spiderX'] as String?,
      postQuantumKey: json['postQuantumKey'] as String?,
      flow: json['flow'] as String?,
      encryption: json['encryption'] as String?,
      alterId: json['alterId'] as String?,
      method: json['method'] as String?,
      password: json['password'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      rawUri: rawUri,
      latencyMs: json['latencyMs'] as int?,
      lastPingedAt: json['lastPingedAt'] != null ? DateTime.parse(json['lastPingedAt'] as String) : null,
      subscriptionId: json['subscriptionId'] as String?,
      ssPrefix: json['ssPrefix'] as String?,
      obfsPassword: json['obfsPassword'] as String?,
      hopPorts: json['hopPorts'] as String?,
      allowInsecure: json['allowInsecure'] as bool? ?? false,
      pinSHA256: json['pinSHA256'] as String?,
      xhttpMode: json['xhttpMode'] as String?,
      xhttpExtra: json['xhttpExtra'] as Map<String, dynamic>?,
      finalmask: json['finalmask'] as Map<String, dynamic>?,
      alpn: json['alpn'] as String?,
      ech: json['ech'] as String?,
      rawXrayConfig: rawXrayConfig,
      protocolSettings: ProtocolSettings.fromJson(json['protocolSettings'] as Map<String, dynamic>?),
      core: CoreKind.tryName(json['core'] as String?),
      headerType: json['headerType'] as String?,
      plugin: json['plugin'] as String?,
      mux: json['mux'] as bool?,
      obfs: json['obfs'] as String?,
      geckoPacketSize: gecko == null || gecko.length != 2 ? null : (gecko[0], gecko[1]),
      needsLinkFields:
          json['linkFields'] != true && rawUri != null && rawXrayConfig == null && _linkProtocols.contains(protocol),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory VpnConfig.fromJsonString(String s) => VpnConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
