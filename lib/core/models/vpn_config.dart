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
  final DateTime? lastPingedAt;
  final String? subscriptionId; // ID of the subscription this config came from
  final String? ssPrefix; // hex-encoded prefix bytes for Outline Shadowsocks (e.g. "160301...")
  final String? obfsPassword; // for Hysteria2 salamander obfuscation
  final bool allowInsecure;
  final String? pinSHA256;
  final String? xhttpMode; // for xhttp transport: "auto", "packet-up", "stream-up", "stream-one"
  final Map<String, dynamic>? xhttpExtra; // raw extra object passed to xhttpSettings
  final Map<String, dynamic>? finalmask; // xray finalmask stream setting (fm param in URL)
  final String? alpn; // comma-separated ALPN list, e.g. "h3" or "h2,http/1.1"
  final String? ech; // base64 ECH ConfigList for TLS Encrypted Client Hello
  final String? rawXrayConfig; // pre-built xray JSON config (from managed subscriptions)

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
    this.allowInsecure = false,
    this.pinSHA256,
    this.xhttpMode,
    this.xhttpExtra,
    this.finalmask,
    this.alpn,
    this.ech,
    this.rawXrayConfig,
  });

  String? validate() {
    if (rawXrayConfig != null) return null;
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
    VpnProtocol? protocol,
    String? address,
    int? port,
    String? uuid,
    VpnSecurity? security,
    VpnTransport? transport,
    String? sni,
    String? wsPath,
    String? wsHost,
    String? grpcServiceName,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    String? spiderX,
    String? postQuantumKey,
    String? flow,
    String? encryption,
    String? alterId,
    String? method,
    String? password,
    int? latencyMs,
    bool clearLatency = false,
    DateTime? lastPingedAt,
    String? subscriptionId,
    String? ssPrefix,
    String? obfsPassword,
    bool? allowInsecure,
    String? pinSHA256,
    String? xhttpMode,
    Map<String, dynamic>? xhttpExtra,
    Map<String, dynamic>? finalmask,
    String? alpn,
    String? ech,
    String? rawXrayConfig,
    String? rawUri,
  }) {
    return VpnConfig(
      id: id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      address: address ?? this.address,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      security: security ?? this.security,
      transport: transport ?? this.transport,
      sni: sni ?? this.sni,
      wsPath: wsPath ?? this.wsPath,
      wsHost: wsHost ?? this.wsHost,
      grpcServiceName: grpcServiceName ?? this.grpcServiceName,
      fingerprint: fingerprint ?? this.fingerprint,
      publicKey: publicKey ?? this.publicKey,
      shortId: shortId ?? this.shortId,
      spiderX: spiderX ?? this.spiderX,
      postQuantumKey: postQuantumKey ?? this.postQuantumKey,
      flow: flow ?? this.flow,
      encryption: encryption ?? this.encryption,
      alterId: alterId ?? this.alterId,
      method: method ?? this.method,
      password: password ?? this.password,
      createdAt: createdAt,
      rawUri: rawUri ?? this.rawUri,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
      lastPingedAt: lastPingedAt ?? this.lastPingedAt,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      ssPrefix: ssPrefix ?? this.ssPrefix,
      obfsPassword: obfsPassword ?? this.obfsPassword,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      pinSHA256: pinSHA256 ?? this.pinSHA256,
      xhttpMode: xhttpMode ?? this.xhttpMode,
      xhttpExtra: xhttpExtra ?? this.xhttpExtra,
      finalmask: finalmask ?? this.finalmask,
      alpn: alpn ?? this.alpn,
      ech: ech ?? this.ech,
      rawXrayConfig: rawXrayConfig ?? this.rawXrayConfig,
    );
  }

  String toUri() {
    if (rawUri != null && rawUri!.isNotEmpty) return rawUri!;
    if (rawXrayConfig != null) return rawXrayConfig!;

    switch (protocol) {
      case VpnProtocol.vless:
        final query = <String, String>{};
        query['type'] = transport.name;
        if (security != VpnSecurity.none) query['security'] = security.name;
        if (sni != null && sni!.isNotEmpty) query['sni'] = sni!;
        if (fingerprint != null && fingerprint!.isNotEmpty) query['fp'] = fingerprint!;
        if (flow != null && flow!.isNotEmpty) query['flow'] = flow!;
        if (publicKey != null && publicKey!.isNotEmpty) query['pbk'] = publicKey!;
        if (shortId != null && shortId!.isNotEmpty) query['sid'] = shortId!;
        if (spiderX != null && spiderX!.isNotEmpty) query['spx'] = spiderX!;
        if (wsPath != null && wsPath!.isNotEmpty) query['path'] = wsPath!;
        if (wsHost != null && wsHost!.isNotEmpty) query['host'] = wsHost!;
        if (grpcServiceName != null && grpcServiceName!.isNotEmpty) query['serviceName'] = grpcServiceName!;
        if (alpn != null && alpn!.isNotEmpty) query['alpn'] = alpn!;
        final qStr = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
        final qPart = qStr.isNotEmpty ? '?$qStr' : '';
        return 'vless://$uuid@$address:$port$qPart#${Uri.encodeComponent(name)}';

      case VpnProtocol.hysteria2:
        final query = <String, String>{};
        if (sni != null && sni!.isNotEmpty) query['sni'] = sni!;
        if (obfsPassword != null && obfsPassword!.isNotEmpty) {
          query['obfs'] = 'salamander';
          query['obfs-password'] = obfsPassword!;
        }
        if (pinSHA256 != null && pinSHA256!.isNotEmpty) query['pinSHA256'] = pinSHA256!;
        if (allowInsecure) query['insecure'] = '1';
        final qStr = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
        final qPart = qStr.isNotEmpty ? '?$qStr' : '';
        final pass = (password != null && password!.isNotEmpty) ? password! : uuid;
        return 'hysteria2://$pass@$address:$port$qPart#${Uri.encodeComponent(name)}';

      case VpnProtocol.shadowsocks:
        final meth = method ?? 'chacha20-ietf-poly1305';
        final pass = password ?? '';
        final userInfo = base64Url.encode(utf8.encode('$meth:$pass')).replaceAll('=', '');
        return 'ss://$userInfo@$address:$port#${Uri.encodeComponent(name)}';

      case VpnProtocol.vmess:
        final vmessJson = {
          'v': '2',
          'ps': name,
          'add': address,
          'port': port,
          'id': uuid,
          'aid': alterId ?? '0',
          'net': transport.name,
          'type': 'none',
          'host': wsHost ?? '',
          'path': wsPath ?? '',
          'tls': security == VpnSecurity.tls ? 'tls' : '',
          'sni': sni ?? '',
          'fp': fingerprint ?? '',
        };
        final enc = base64.encode(utf8.encode(jsonEncode(vmessJson)));
        return 'vmess://$enc';

      case VpnProtocol.trojan:
        final query = <String, String>{};
        query['type'] = transport.name;
        if (security != VpnSecurity.none) query['security'] = security.name;
        if (sni != null && sni!.isNotEmpty) query['sni'] = sni!;
        if (fingerprint != null && fingerprint!.isNotEmpty) query['fp'] = fingerprint!;
        if (wsPath != null && wsPath!.isNotEmpty) query['path'] = wsPath!;
        if (wsHost != null && wsHost!.isNotEmpty) query['host'] = wsHost!;
        if (alpn != null && alpn!.isNotEmpty) query['alpn'] = alpn!;
        final qStr = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
        final qPart = qStr.isNotEmpty ? '?$qStr' : '';
        final pass = (password != null && password!.isNotEmpty) ? password! : uuid;
        return 'trojan://$pass@$address:$port$qPart#${Uri.encodeComponent(name)}';
    }
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
        'allowInsecure': allowInsecure,
        'pinSHA256': pinSHA256,
        'xhttpMode': xhttpMode,
        'xhttpExtra': xhttpExtra,
        'finalmask': finalmask,
        'alpn': alpn,
        'ech': ech,
        'rawXrayConfig': rawXrayConfig,
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
        lastPingedAt: json['lastPingedAt'] != null
            ? DateTime.parse(json['lastPingedAt'] as String)
            : null,
        subscriptionId: json['subscriptionId'] as String?,
        ssPrefix: json['ssPrefix'] as String?,
        obfsPassword: json['obfsPassword'] as String?,
        allowInsecure: json['allowInsecure'] as bool? ?? false,
        pinSHA256: json['pinSHA256'] as String?,
        xhttpMode: json['xhttpMode'] as String?,
        xhttpExtra: json['xhttpExtra'] as Map<String, dynamic>?,
        finalmask: json['finalmask'] as Map<String, dynamic>?,
        alpn: json['alpn'] as String?,
        ech: json['ech'] as String?,
        rawXrayConfig: json['rawXrayConfig'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());
  factory VpnConfig.fromJsonString(String s) =>
      VpnConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
