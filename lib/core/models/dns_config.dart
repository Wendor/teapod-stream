/// DNS operating mode
enum DnsMode {
  proxy, // DNS queries go through the proxy server
  direct, // DNS queries go direct
}

/// DNS server type
enum DnsType {
  udp, // Plain UDP DNS (port 53)
  doh, // DNS over HTTPS
  dot, // DNS over TLS
}

/// DNS server setting
class DnsServerConfig {
  final DnsType type;
  final String address;
  final int port;
  final String? domain; // For DoH/DoT (SNI)
  final String? fallbackIp; // IP fallback if DNS is unavailable (for DoH/DoT domains)

  const DnsServerConfig({required this.type, required this.address, this.port = 53, this.domain, this.fallbackIp});

  /// Preset DNS servers
  static const cloudflare = DnsServerConfig(type: DnsType.udp, address: '1.1.1.1');
  static const cloudflareDoH = DnsServerConfig(
    type: DnsType.doh,
    address: 'https://cloudflare-dns.com/dns-query',
    domain: 'cloudflare-dns.com',
    fallbackIp: '1.1.1.1',
  );
  static const cloudflareDoT = DnsServerConfig(
    type: DnsType.dot,
    address: '1.1.1.1',
    port: 853,
    domain: 'cloudflare-dns.com',
    fallbackIp: '1.1.1.1',
  );

  static const google = DnsServerConfig(type: DnsType.udp, address: '8.8.8.8');
  static const googleDoH = DnsServerConfig(
    type: DnsType.doh,
    address: 'https://dns.google/dns-query',
    domain: 'dns.google',
    fallbackIp: '8.8.8.8',
  );
  static const googleDoT = DnsServerConfig(
    type: DnsType.dot,
    address: '8.8.8.8',
    port: 853,
    domain: 'dns.google',
    fallbackIp: '8.8.8.8',
  );

  static const quad9 = DnsServerConfig(type: DnsType.udp, address: '9.9.9.9');
  static const quad9DoH = DnsServerConfig(
    type: DnsType.doh,
    address: 'https://dns.quad9.net/dns-query',
    domain: 'dns.quad9.net',
    fallbackIp: '9.9.9.9',
  );

  static const adguard = DnsServerConfig(type: DnsType.udp, address: '94.140.14.14');
  static const adguardDoH = DnsServerConfig(
    type: DnsType.doh,
    address: 'https://dns.adguard-dns.com/dns-query',
    domain: 'dns.adguard-dns.com',
    fallbackIp: '94.140.14.14',
  );

  /// The preset servers for the UI; the custom server (`custom`) is added there with a localized label.
  static const List<Map<String, String>> presets = [
    {'label': 'Cloudflare (UDP)', 'value': 'cf_udp'},
    {'label': 'Cloudflare (DoH)', 'value': 'cf_doh'},
    {'label': 'Cloudflare (DoT)', 'value': 'cf_dot'},
    {'label': 'Google (UDP)', 'value': 'google_udp'},
    {'label': 'Google (DoH)', 'value': 'google_doh'},
    {'label': 'Google (DoT)', 'value': 'google_dot'},
    {'label': 'Quad9 (UDP)', 'value': 'quad9_udp'},
    {'label': 'Quad9 (DoH)', 'value': 'quad9_doh'},
    {'label': 'AdGuard (UDP)', 'value': 'adguard_udp'},
    {'label': 'AdGuard (DoH)', 'value': 'adguard_doh'},
  ];

  static DnsServerConfig fromPreset(String preset, {String? customAddress, DnsType? customType}) {
    switch (preset) {
      case 'cf_udp':
        return cloudflare;
      case 'cf_doh':
        return cloudflareDoH;
      case 'cf_dot':
        return cloudflareDoT;
      case 'google_udp':
        return google;
      case 'google_doh':
        return googleDoH;
      case 'google_dot':
        return googleDoT;
      case 'quad9_udp':
        return quad9;
      case 'quad9_doh':
        return quad9DoH;
      case 'adguard_udp':
        return adguard;
      case 'adguard_doh':
        return adguardDoH;
      case 'custom':
        return _custom(customType ?? DnsType.udp, customAddress);
      default:
        return cloudflare;
    }
  }

  /// Parses a custom server address: strips the scheme, extracts `:port`
  /// and fills in the default for the type (UDP 53, DoT 853, DoH 443).
  /// Without this DoT went to xray with port 53 and the TLS handshake failed.
  static DnsServerConfig _custom(DnsType type, String? raw) {
    var input = (raw ?? '').trim();
    if (input.isEmpty) {
      return switch (type) {
        DnsType.udp => cloudflare,
        DnsType.doh => cloudflareDoH,
        DnsType.dot => cloudflareDoT,
      };
    }

    if (type == DnsType.doh) {
      if (!input.startsWith('http://') && !input.startsWith('https://')) {
        input = input.contains('/') ? 'https://$input' : 'https://$input/dns-query';
      }
      final uri = Uri.tryParse(input);
      return DnsServerConfig(
        type: type,
        address: input,
        port: uri?.hasPort == true ? uri!.port : 443,
        domain: uri?.host.isNotEmpty == true ? uri!.host : null,
      );
    }

    input = input.replaceFirst(RegExp(r'^[a-z0-9+]+://'), '');
    final slash = input.indexOf('/');
    if (slash >= 0) input = input.substring(0, slash);

    final defaultPort = type == DnsType.dot ? 853 : 53;
    var host = input;
    var port = defaultPort;
    // IPv6 literal in brackets: the port comes only after the closing bracket.
    // A bare IPv6 (several ':') has no port.
    final bracketed = input.startsWith('[');
    final sep = bracketed ? input.lastIndexOf(']:') : input.lastIndexOf(':');
    if (sep > 0 && (bracketed || input.indexOf(':') == sep)) {
      final parsed = int.tryParse(input.substring(bracketed ? sep + 2 : sep + 1));
      if (parsed != null && parsed > 0 && parsed <= 65535) {
        host = input.substring(0, bracketed ? sep + 1 : sep);
        port = parsed;
      }
    }

    return DnsServerConfig(type: type, address: host, port: port);
  }

  String get displayName {
    switch (type) {
      case DnsType.udp:
        return address;
      case DnsType.doh:
        return 'DoH: $address';
      case DnsType.dot:
        return 'DoT: $address:$port';
    }
  }
}
