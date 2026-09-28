/// DNS режим работы
enum DnsMode {
  proxy,   // DNS запросы идут через прокси-сервер
  direct,  // DNS запросы идут напрямую
}

/// Тип DNS сервера
enum DnsType {
  udp,   // Обычный UDP DNS (порт 53)
  doh,   // DNS over HTTPS
  dot,   // DNS over TLS
}

/// Настройка DNS сервера
class DnsServerConfig {
  final DnsType type;
  final String address;
  final int port;
  final String? domain; // Для DoH/DoT (SNI)
  final String? fallbackIp; // IP fallback если DNS недоступен (для DoH/DoT доменов)

  const DnsServerConfig({
    required this.type,
    required this.address,
    this.port = 53,
    this.domain,
    this.fallbackIp,
  });

  /// Предустановленные DNS сервера
  static const cloudflare = DnsServerConfig(type: DnsType.udp, address: '1.1.1.1');
  static const cloudflareDoH = DnsServerConfig(type: DnsType.doh, address: 'https://cloudflare-dns.com/dns-query', domain: 'cloudflare-dns.com', fallbackIp: '1.1.1.1');
  static const cloudflareDoT = DnsServerConfig(type: DnsType.dot, address: '1.1.1.1', port: 853, domain: 'cloudflare-dns.com', fallbackIp: '1.1.1.1');

  static const google = DnsServerConfig(type: DnsType.udp, address: '8.8.8.8');
  static const googleDoH = DnsServerConfig(type: DnsType.doh, address: 'https://dns.google/dns-query', domain: 'dns.google', fallbackIp: '8.8.8.8');
  static const googleDoT = DnsServerConfig(type: DnsType.dot, address: '8.8.8.8', port: 853, domain: 'dns.google', fallbackIp: '8.8.8.8');

  static const quad9 = DnsServerConfig(type: DnsType.udp, address: '9.9.9.9');
  static const quad9DoH = DnsServerConfig(type: DnsType.doh, address: 'https://dns.quad9.net/dns-query', domain: 'dns.quad9.net', fallbackIp: '9.9.9.9');

  static const adguard = DnsServerConfig(type: DnsType.udp, address: '94.140.14.14');
  static const adguardDoH = DnsServerConfig(type: DnsType.doh, address: 'https://dns.adguard.com/dns-query', domain: 'dns.adguard.com', fallbackIp: '94.140.14.14');

  /// Все предустановленные сервера для UI
  static const List<Map<String, dynamic>> presets = [
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
    {'label': 'Свой сервер', 'value': 'custom'},
  ];

  static DnsServerConfig fromPreset(String preset, {String? customAddress, DnsType? customType}) {
    switch (preset) {
      case 'cf_udp': return cloudflare;
      case 'cf_doh': return cloudflareDoH;
      case 'cf_dot': return cloudflareDoT;
      case 'google_udp': return google;
      case 'google_doh': return googleDoH;
      case 'google_dot': return googleDoT;
      case 'quad9_udp': return quad9;
      case 'quad9_doh': return quad9DoH;
      case 'adguard_udp': return adguard;
      case 'adguard_doh': return adguardDoH;
      case 'custom':
        return _custom(customType ?? DnsType.udp, customAddress);
      default: return cloudflare;
    }
  }

  /// Разбирает адрес кастомного сервера: снимает схему, вытаскивает `:port`
  /// и подставляет дефолт по типу (UDP 53, DoT 853, DoH 443).
  /// Без этого DoT уходил в xray с портом 53 и TLS-рукопожатие не проходило.
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
    // IPv6-литерал в скобках: порт только после закрывающей скобки.
    final sep = input.startsWith('[') ? input.lastIndexOf(']:') : input.lastIndexOf(':');
    if (sep > 0 && !input.substring(sep + 1).contains(':')) {
      final parsed = int.tryParse(input.substring(input.startsWith('[') ? sep + 2 : sep + 1));
      if (parsed != null && parsed > 0 && parsed <= 65535) {
        host = input.substring(0, input.startsWith('[') ? sep + 1 : sep);
        port = parsed;
      }
    }

    return DnsServerConfig(type: type, address: host, port: port);
  }

  String get displayName {
    switch (type) {
      case DnsType.udp: return address;
      case DnsType.doh: return 'DoH: $address';
      case DnsType.dot: return 'DoT: $address:$port';
    }
  }
}
