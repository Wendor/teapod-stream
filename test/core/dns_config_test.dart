import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/dns_config.dart';

void main() {
  group('DnsServerConfig.fromPreset custom', () {
    DnsServerConfig custom(String address, DnsType type) =>
        DnsServerConfig.fromPreset('custom', customAddress: address, customType: type);

    test('udp defaults to port 53', () {
      final s = custom('9.9.9.9', DnsType.udp);
      expect(s.address, '9.9.9.9');
      expect(s.port, 53);
    });

    test('dot without explicit port defaults to 853', () {
      final s = custom('xbox-dns.ru', DnsType.dot);
      expect(s.address, 'xbox-dns.ru');
      expect(s.port, 853);
    });

    test('dot keeps explicit port from host:port', () {
      final s = custom('xbox-dns.ru:5853', DnsType.dot);
      expect(s.address, 'xbox-dns.ru');
      expect(s.port, 5853);
    });

    test('dot strips tls:// scheme', () {
      final s = custom('tls://dns.adguard.com', DnsType.dot);
      expect(s.address, 'dns.adguard.com');
      expect(s.port, 853);
    });

    test('udp keeps explicit port', () {
      final s = custom('9.9.9.9:5353', DnsType.udp);
      expect(s.address, '9.9.9.9');
      expect(s.port, 5353);
    });

    test('doh keeps full url and derives port', () {
      final s = custom('https://dns.example.org/dns-query', DnsType.doh);
      expect(s.address, 'https://dns.example.org/dns-query');
      expect(s.port, 443);
    });

    test('doh with bare hostname is normalized to a dns-query url', () {
      final s = custom('dns.example.org', DnsType.doh);
      expect(s.address, 'https://dns.example.org/dns-query');
      expect(s.port, 443);
    });

    test('empty address falls back to cloudflare udp', () {
      final s = custom('  ', DnsType.udp);
      expect(s.address, '1.1.1.1');
      expect(s.port, 53);
    });
  });
}
