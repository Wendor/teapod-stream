/// Параметры протоколов, которых нет в общей модели `VpnConfig` (WireGuard, SSH, Naive).
sealed class ProtocolSettings {
  const ProtocolSettings();

  String get type;

  Map<String, dynamic> toJson();

  static ProtocolSettings? fromJson(Map<String, dynamic>? json) => switch (json?['type']) {
        'wireguard' => WireGuardSettings.fromJson(json!),
        'ssh' => SshSettings.fromJson(json!),
        'naive' => NaiveSettings.fromJson(json!),
        _ => null,
      };
}

List<String> _strings(Object? v) => (v as List?)?.map((e) => e.toString()).toList() ?? const [];

/// WireGuard / AmneziaWG (один peer). Сервер — `VpnConfig.address`/`port`.
final class WireGuardSettings extends ProtocolSettings {
  final String privateKey;
  final List<String> addresses;
  final String peerPublicKey;
  final String? presharedKey;
  final int? mtu;
  final List<int>? reserved;
  final List<String> allowedIps;
  final int? keepalive;

  /// null — обычный WireGuard.
  final AmneziaParams? amnezia;

  const WireGuardSettings({
    required this.privateKey,
    required this.addresses,
    required this.peerPublicKey,
    this.presharedKey,
    this.mtu,
    this.reserved,
    this.allowedIps = const ['0.0.0.0/0', '::/0'],
    this.keepalive,
    this.amnezia,
  });

  @override
  String get type => 'wireguard';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'privateKey': privateKey,
        'addresses': addresses,
        'peerPublicKey': peerPublicKey,
        'presharedKey': ?presharedKey,
        'mtu': ?mtu,
        'reserved': ?reserved,
        'allowedIps': allowedIps,
        'keepalive': ?keepalive,
        'amnezia': ?amnezia?.toJson(),
      };

  factory WireGuardSettings.fromJson(Map<String, dynamic> json) => WireGuardSettings(
        privateKey: json['privateKey'] as String? ?? '',
        addresses: _strings(json['addresses']),
        peerPublicKey: json['peerPublicKey'] as String? ?? '',
        presharedKey: json['presharedKey'] as String?,
        mtu: json['mtu'] as int?,
        reserved: (json['reserved'] as List?)?.map((e) => e as int).toList(),
        allowedIps: _strings(json['allowedIps']),
        keepalive: json['keepalive'] as int?,
        amnezia: json['amnezia'] == null ? null : AmneziaParams.fromJson(json['amnezia'] as Map<String, dynamic>),
      );
}

/// Параметры AmneziaWG 3.1; null — не задан (AWG считает нулём).
final class AmneziaParams {
  final int? jc, jmin, jmax, s1, s2, s3, s4;
  final String? h1, h2, h3, h4, i1, i2, i3, i4, i5;
  final String? headerProtectionKey, contentPaddingAddition;
  final String? rekeyAfterTime, rekeyTimeout, rejectAfterTime, keepaliveTimeout, maxHandshakeAttempts;
  final bool randomTrailers, disableCookies;

  const AmneziaParams({
    this.jc, this.jmin, this.jmax, this.s1, this.s2, this.s3, this.s4,
    this.h1, this.h2, this.h3, this.h4, this.i1, this.i2, this.i3, this.i4, this.i5,
    this.headerProtectionKey, this.contentPaddingAddition,
    this.rekeyAfterTime, this.rekeyTimeout, this.rejectAfterTime, this.keepaliveTimeout, this.maxHandshakeAttempts,
    this.randomTrailers = false, this.disableCookies = false,
  });

  /// Ключи в формате endpoint'а `awg` teapod-core (= ключи UAPI amneziawg-go).
  Map<String, dynamic> toJson() => {
        'jc': ?jc, 'jmin': ?jmin, 'jmax': ?jmax, 's1': ?s1, 's2': ?s2, 's3': ?s3, 's4': ?s4,
        'h1': ?h1, 'h2': ?h2, 'h3': ?h3, 'h4': ?h4,
        'i1': ?i1, 'i2': ?i2, 'i3': ?i3, 'i4': ?i4, 'i5': ?i5,
        'header_protection_key': ?headerProtectionKey,
        'content_padding_addition': ?contentPaddingAddition,
        'rekey_after_time': ?rekeyAfterTime,
        'rekey_timeout': ?rekeyTimeout,
        'reject_after_time': ?rejectAfterTime,
        'keepalive_timeout': ?keepaliveTimeout,
        'max_handshake_attempts': ?maxHandshakeAttempts,
        if (randomTrailers) 'random_trailers': true,
        if (disableCookies) 'disable_cookies': true,
      };

  factory AmneziaParams.fromJson(Map<String, dynamic> j) => AmneziaParams(
        jc: j['jc'] as int?, jmin: j['jmin'] as int?, jmax: j['jmax'] as int?,
        s1: j['s1'] as int?, s2: j['s2'] as int?, s3: j['s3'] as int?, s4: j['s4'] as int?,
        h1: j['h1'] as String?, h2: j['h2'] as String?, h3: j['h3'] as String?, h4: j['h4'] as String?,
        i1: j['i1'] as String?, i2: j['i2'] as String?, i3: j['i3'] as String?, i4: j['i4'] as String?,
        i5: j['i5'] as String?,
        headerProtectionKey: j['header_protection_key'] as String?,
        contentPaddingAddition: j['content_padding_addition'] as String?,
        rekeyAfterTime: j['rekey_after_time'] as String?,
        rekeyTimeout: j['rekey_timeout'] as String?,
        rejectAfterTime: j['reject_after_time'] as String?,
        keepaliveTimeout: j['keepalive_timeout'] as String?,
        maxHandshakeAttempts: j['max_handshake_attempts'] as String?,
        randomTrailers: j['random_trailers'] == true,
        disableCookies: j['disable_cookies'] == true,
      );
}

/// SSH: пароль и/или приватный ключ; [hostKeys] — pin ключей сервера.
final class SshSettings extends ProtocolSettings {
  final String user;
  final String? password;
  final String? privateKey;
  final String? privateKeyPassphrase;
  final List<String> hostKeys;

  const SshSettings({
    required this.user,
    this.password,
    this.privateKey,
    this.privateKeyPassphrase,
    this.hostKeys = const [],
  });

  @override
  String get type => 'ssh';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'user': user,
        'password': ?password,
        'privateKey': ?privateKey,
        'privateKeyPassphrase': ?privateKeyPassphrase,
        'hostKeys': hostKeys,
      };

  factory SshSettings.fromJson(Map<String, dynamic> json) => SshSettings(
        user: json['user'] as String? ?? '',
        password: json['password'] as String?,
        privateKey: json['privateKey'] as String?,
        privateKeyPassphrase: json['privateKeyPassphrase'] as String?,
        hostKeys: _strings(json['hostKeys']),
      );
}

/// NaiveProxy (HTTPS/HTTP3 CONNECT через Cronet).
final class NaiveSettings extends ProtocolSettings {
  final String user;
  final String password;
  final bool quic;
  final Map<String, String> extraHeaders;

  const NaiveSettings({required this.user, required this.password, this.quic = false, this.extraHeaders = const {}});

  @override
  String get type => 'naive';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'user': user,
        'password': password,
        'quic': quic,
        'extraHeaders': extraHeaders,
      };

  factory NaiveSettings.fromJson(Map<String, dynamic> json) => NaiveSettings(
        user: json['user'] as String? ?? '',
        password: json['password'] as String? ?? '',
        quic: json['quic'] as bool? ?? false,
        extraHeaders: (json['extraHeaders'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
      );
}
