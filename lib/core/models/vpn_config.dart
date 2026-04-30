import 'dart:convert';

enum VpnProtocol { vless, vmess, trojan, shadowsocks, hysteria2 }

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
  final String? method; // for Shadowsocks
  final String? password; // for Trojan/Shadowsocks
  final DateTime createdAt;
  final String? rawUri;
  final int? latencyMs;
  final String? subscriptionId; // ID of the subscription this config came from
  final String? ssPrefix; // hex-encoded prefix bytes for Outline Shadowsocks (e.g. "160301...")
  final String? obfsPassword; // for Hysteria2 salamander obfuscation
  final String? xhttpMode; // for xhttp transport: "auto", "packet-up", "stream-up", "stream-one"
  final Map<String, dynamic>? xhttpExtra; // raw extra object passed to xhttpSettings

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
    this.subscriptionId,
    this.ssPrefix,
    this.obfsPassword,
    this.xhttpMode,
    this.xhttpExtra,
  });

  String? validate() {
    if (address.isEmpty) return 'Пустой адрес сервера';
    if (port < 1 || port > 65535) return 'Неверный порт: $port';
    if (protocol == VpnProtocol.vless || protocol == VpnProtocol.vmess) {
      if (uuid.isEmpty) return 'Пустой UUID';
    }
    if ((protocol == VpnProtocol.shadowsocks || protocol == VpnProtocol.trojan ||
         protocol == VpnProtocol.hysteria2) && (password == null || password!.isEmpty)) {
      return 'Пустой пароль';
    }
    return null;
  }

  VpnConfig copyWith({
    String? name,
    int? latencyMs,
    String? subscriptionId,
    String? rawUri,
  }) {
    return VpnConfig(
      id: id,
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
      createdAt: createdAt,
      rawUri: rawUri ?? this.rawUri,
      latencyMs: latencyMs ?? this.latencyMs,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      ssPrefix: ssPrefix,
      obfsPassword: obfsPassword,
      xhttpMode: xhttpMode,
      xhttpExtra: xhttpExtra,
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
        'subscriptionId': subscriptionId,
        'ssPrefix': ssPrefix,
        'obfsPassword': obfsPassword,
        'xhttpMode': xhttpMode,
        'xhttpExtra': xhttpExtra,
      };

  factory VpnConfig.fromJson(Map<String, dynamic> json) => VpnConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        protocol: VpnProtocol.values.firstWhere(
          (e) => e.name == json['protocol'],
          orElse: () => VpnProtocol.vless,
        ),
        address: json['address'] as String,
        port: json['port'] as int,
        uuid: json['uuid'] as String? ?? '',
        security: VpnSecurity.values.firstWhere(
          (e) => e.name == json['security'],
          orElse: () => VpnSecurity.none,
        ),
        transport: VpnTransport.values.firstWhere(
          (e) => e.name == json['transport'],
          orElse: () => VpnTransport.tcp,
        ),
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
        rawUri: json['rawUri'] as String?,
        latencyMs: json['latencyMs'] as int?,
        subscriptionId: json['subscriptionId'] as String?,
        ssPrefix: json['ssPrefix'] as String?,
        obfsPassword: json['obfsPassword'] as String?,
        xhttpMode: json['xhttpMode'] as String?,
        xhttpExtra: json['xhttpExtra'] as Map<String, dynamic>?,
      );

  String toJsonString() => jsonEncode(toJson());
  factory VpnConfig.fromJsonString(String s) =>
      VpnConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
