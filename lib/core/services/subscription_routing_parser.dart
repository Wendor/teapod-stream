import 'dart:convert';

/// Parses and normalizes routing rules from various subscription formats
/// (Xray/V2Ray, v2rayNG RulesetItem, sing-box/Happ, Streisand).
class SubscriptionRoutingParser {
  /// Parses raw input into a list of normalized Xray routing rules.
  /// Returns null if no valid routing rules could be extracted.
  static List<Map<String, dynamic>>? parse(dynamic input) {
    if (input == null) return null;

    if (input is String) {
      final trimmed = input.trim();
      if (trimmed.isEmpty) return null;

      // Handle routing://, rules://, ruleset://, rule://, sub-rule:// schemes
      if (trimmed.startsWith('routing://') ||
          trimmed.startsWith('rules://') ||
          trimmed.startsWith('ruleset://') ||
          trimmed.startsWith('rule://') ||
          trimmed.startsWith('sub-rule://')) {
        final payload = trimmed.split('://').last;
        try {
          final cleaned = payload.replaceAll(RegExp(r'\s'), '');
          final padded = cleaned.padRight((cleaned.length + 3) ~/ 4 * 4, '=');
          final decoded = utf8.decode(base64Decode(padded));
          return parse(jsonDecode(decoded));
        } catch (_) {
          return null;
        }
      }

      // Try decoding JSON directly or from base64
      try {
        final decoded = jsonDecode(trimmed);
        return parse(decoded);
      } catch (_) {
        try {
          final cleaned = trimmed.replaceAll(RegExp(r'\s'), '');
          final padded = cleaned.padRight((cleaned.length + 3) ~/ 4 * 4, '=');
          final decoded = utf8.decode(base64Decode(padded));
          final res = parse(jsonDecode(decoded));
          if (res != null) return res;
        } catch (_) {}
      }

      // Check if string contains line-by-line Clash rules or URI lines
      final lines = trimmed.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
      final clashRules = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.isEmpty || line.startsWith('#')) continue;
        final cleanLine = line.startsWith('- ') ? line.substring(2).trim() : line;
        final rule = _normalizeClashRule(cleanLine);
        if (rule != null) {
          clashRules.add(rule);
        }
      }
      if (clashRules.isNotEmpty) return clashRules;
    }

    if (input is Map<String, dynamic>) {
      // 1. Xray/V2Ray format: { "routing": { "rules": [...] } } or { "routing": [...] }
      if (input.containsKey('routing')) {
        final routing = input['routing'];
        if (routing is Map<String, dynamic> && routing.containsKey('rules')) {
          return parse(routing['rules']);
        } else if (routing is List) {
          return parse(routing);
        }
      }

      // 2. sing-box format: { "route": { "rules": [...] } } or { "route": { "rule_set": [...] } }
      if (input.containsKey('route')) {
        final route = input['route'];
        if (route is Map<String, dynamic>) {
          if (route.containsKey('rules')) {
            return parse(route['rules']);
          } else if (route.containsKey('rule_set')) {
            return parse(route['rule_set']);
          }
        }
      }

      // 3. Top-level rules list: { "rules": [...] } (sing-box, Clash, or custom)
      if (input.containsKey('rules') && input['rules'] is List) {
        return parse(input['rules']);
      }

      // Single rule object
      final single = _normalizeRule(input);
      return single != null ? [single] : null;
    }

    if (input is List) {
      final normalizedRules = <Map<String, dynamic>>[];
      for (final item in input) {
        if (item is Map<String, dynamic>) {
          // Check if item contains its own routing definition
          if (item.containsKey('routing') ||
              item.containsKey('route') ||
              item.containsKey('rules')) {
            final sub = parse(item);
            if (sub != null && sub.isNotEmpty) {
              normalizedRules.addAll(sub);
              continue;
            }
          }
          final rule = _normalizeRule(item);
          if (rule != null) {
            normalizedRules.add(rule);
          }
        } else if (item is String) {
          // Could be a Clash rule line e.g. "DOMAIN-SUFFIX,google.com,DIRECT"
          final clean = item.trim().startsWith('- ') ? item.trim().substring(2).trim() : item.trim();
          final rule = _normalizeClashRule(clean);
          if (rule != null) {
            normalizedRules.add(rule);
          }
        }
      }
      return normalizedRules.isNotEmpty ? normalizedRules : null;
    }

    return null;
  }

  /// Normalizes a single rule from either Xray, v2rayNG, or sing-box schema into Xray format.
  static Map<String, dynamic>? _normalizeRule(Map<String, dynamic> raw) {
    // Skip if disabled (v2rayNG RulesetItem style)
    if (raw['enabled'] == false) return null;

    // Detect outbound tag / action
    String rawAction = (raw['action'] ?? '').toString().toLowerCase().trim();
    String rawOut = (raw['outboundTag'] ??
            raw['outbound'] ??
            raw['tag'] ??
            rawAction)
        .toString()
        .toLowerCase()
        .trim();

    String outboundTag;
    if (rawAction == 'reject' ||
        rawOut == 'block' ||
        rawOut == 'blackhole' ||
        rawOut == 'reject' ||
        rawOut == 'drop') {
      outboundTag = 'block';
    } else if (rawAction == 'direct' ||
        rawAction == 'bypass' ||
        rawOut == 'direct' ||
        rawOut == 'freedom' ||
        rawOut == 'bypass' ||
        rawOut == 'pass') {
      outboundTag = 'direct';
    } else {
      outboundTag = 'proxy';
    }

    final domains = <String>[];
    final ips = <String>[];
    final sources = <String>[];

    // Extract Xray/v2ray domains
    if (raw['domain'] != null) {
      final d = raw['domain'];
      if (d is List) {
        for (final item in d) {
          final s = item.toString().trim();
          if (s.isNotEmpty) domains.add(s);
        }
      } else if (d is String && d.trim().isNotEmpty) {
        domains.add(d.trim());
      }
    }

    // Extract sing-box domains / geosites
    if (raw['domain_suffix'] != null) {
      final ds = raw['domain_suffix'];
      if (ds is List) {
        for (final s in ds) {
          final str = s.toString().trim();
          if (str.isNotEmpty) domains.add('domain:$str');
        }
      } else if (ds is String && ds.trim().isNotEmpty) {
        domains.add('domain:${ds.trim()}');
      }
    }
    if (raw['domain_keyword'] != null) {
      final dk = raw['domain_keyword'];
      if (dk is List) {
        for (final k in dk) {
          final str = k.toString().trim();
          if (str.isNotEmpty) domains.add('keyword:$str');
        }
      } else if (dk is String && dk.trim().isNotEmpty) {
        domains.add('keyword:${dk.trim()}');
      }
    }
    if (raw['domain_regex'] != null) {
      final dr = raw['domain_regex'];
      if (dr is List) {
        for (final r in dr) {
          final str = r.toString().trim();
          if (str.isNotEmpty) domains.add('regexp:$str');
        }
      } else if (dr is String && dr.trim().isNotEmpty) {
        domains.add('regexp:${dr.trim()}');
      }
    }
    if (raw['geosite'] != null) {
      final gs = raw['geosite'];
      if (gs is List) {
        for (final g in gs) {
          final str = g.toString().trim();
          if (str.isNotEmpty) domains.add('geosite:$str');
        }
      } else if (gs is String && gs.trim().isNotEmpty) {
        domains.add('geosite:${gs.trim()}');
      }
    }

    // Extract sing-box rule_set (e.g. ["geosite-cn", "geoip-cn", "geosite-category-ads-all"])
    if (raw['rule_set'] != null) {
      final rs = raw['rule_set'];
      final list = rs is List ? rs : [rs];
      for (final item in list) {
        final str = item.toString().trim().toLowerCase();
        if (str.isEmpty) continue;
        if (str.startsWith('geosite-')) {
          domains.add('geosite:${str.substring(8)}');
        } else if (str.startsWith('geosite:')) {
          domains.add('geosite:${str.substring(8)}');
        } else if (str.startsWith('geoip-')) {
          ips.add('geoip:${str.substring(6)}');
        } else if (str.startsWith('geoip:')) {
          ips.add('geoip:${str.substring(6)}');
        } else if (str.contains('ads') || str.contains('site')) {
          domains.add('geosite:$str');
        } else if (str.contains('ip') || str == 'cn' || str == 'ru') {
          ips.add('geoip:$str');
        } else {
          domains.add('geosite:$str');
        }
      }
    }

    // Extract Xray/v2ray IPs
    if (raw['ip'] != null) {
      final ipVal = raw['ip'];
      if (ipVal is List) {
        ips.addAll(ipVal.map((e) => e.toString().trim()).where((s) => s.isNotEmpty));
      } else if (ipVal is String && ipVal.trim().isNotEmpty) {
        ips.add(ipVal.trim());
      }
    }

    // Extract sing-box IPs / geoips
    if (raw['ip_cidr'] != null) {
      final cidr = raw['ip_cidr'];
      if (cidr is List) {
        for (final c in cidr) {
          final str = c.toString().trim();
          if (str.isNotEmpty) ips.add(str);
        }
      } else if (cidr is String && cidr.trim().isNotEmpty) {
        ips.add(cidr.trim());
      }
    }
    if (raw['geoip'] != null) {
      final gi = raw['geoip'];
      if (gi is List) {
        for (final g in gi) {
          final str = g.toString().trim();
          if (str.isNotEmpty) ips.add('geoip:${str.toLowerCase()}');
        }
      } else if (gi is String && gi.trim().isNotEmpty) {
        ips.add('geoip:${gi.trim().toLowerCase()}');
      }
    }

    // Extract source IP CIDRs
    if (raw['source_ip_cidr'] != null || raw['source'] != null) {
      final src = raw['source_ip_cidr'] ?? raw['source'];
      if (src is List) {
        sources.addAll(src.map((e) => e.toString().trim()).where((s) => s.isNotEmpty));
      } else if (src is String && src.trim().isNotEmpty) {
        sources.add(src.trim());
      }
    }

    // Extract port and port_range
    String? port;
    if (raw['port'] != null) {
      final p = raw['port'];
      if (p is List) {
        port = p.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join(',');
      } else {
        port = p.toString().trim();
      }
    } else if (raw['port_range'] != null) {
      final pr = raw['port_range'];
      if (pr is List) {
        port = pr
            .map((e) => e.toString().replaceAll(':', '-').trim())
            .where((s) => s.isNotEmpty)
            .join(',');
      } else {
        port = pr.toString().replaceAll(':', '-').trim();
      }
    }

    // Extract network (tcp, udp)
    String? network;
    if (raw['network'] != null) {
      final net = raw['network'];
      if (net is List) {
        network = net.map((e) => e.toString().trim().toLowerCase()).join(',');
      } else {
        network = net.toString().trim().toLowerCase();
      }
    }

    // Extract protocol
    final protocol = raw['protocol'] is List
        ? List<String>.from(raw['protocol'])
        : (raw['protocol'] != null ? [raw['protocol'].toString()] : null);

    // Must match at least some matcher
    if (domains.isEmpty &&
        ips.isEmpty &&
        sources.isEmpty &&
        (port == null || port.isEmpty) &&
        (network == null || network.isEmpty) &&
        (protocol == null || protocol.isEmpty)) {
      return null;
    }

    final rule = <String, dynamic>{
      'type': 'field',
      'outboundTag': outboundTag,
    };

    if (domains.isNotEmpty) {
      rule['domain'] = domains.toSet().toList();
    }
    if (ips.isNotEmpty) {
      rule['ip'] = ips.toSet().toList();
    }
    if (sources.isNotEmpty) {
      rule['source'] = sources.toSet().toList();
    }
    if (port != null && port.isNotEmpty) {
      rule['port'] = port;
    }
    if (network != null && network.isNotEmpty) {
      rule['network'] = network;
    }
    if (protocol != null && protocol.isNotEmpty) {
      rule['protocol'] = protocol;
    }

    return rule;
  }

  /// Normalizes Clash rule lines like "DOMAIN-SUFFIX,google.com,DIRECT"
  static Map<String, dynamic>? _normalizeClashRule(String line) {
    final parts = line.split(',').map((p) => p.trim()).toList();
    if (parts.length < 2) return null;

    final type = parts[0].toUpperCase();
    final target = (parts.length >= 3 ? parts[2] : parts[1]).toUpperCase();

    String outboundTag;
    if (target == 'DIRECT' || target == 'PASS' || target == 'BYPASS') {
      outboundTag = 'direct';
    } else if (target == 'REJECT' || target == 'DROP' || target == 'BLOCK') {
      outboundTag = 'block';
    } else {
      outboundTag = 'proxy';
    }

    final arg = parts.length >= 2 ? parts[1] : '';

    switch (type) {
      case 'DOMAIN':
      case 'DOMAIN-FULL':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'domain': ['full:$arg'],
        };
      case 'DOMAIN-SUFFIX':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'domain': ['domain:$arg'],
        };
      case 'DOMAIN-KEYWORD':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'domain': ['keyword:$arg'],
        };
      case 'DOMAIN-REGEX':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'domain': ['regexp:$arg'],
        };
      case 'GEOSITE':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'domain': ['geosite:${arg.toLowerCase()}'],
        };
      case 'GEOIP':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'ip': ['geoip:${arg.toLowerCase()}'],
        };
      case 'IP-CIDR':
      case 'IP-CIDR6':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'ip': [arg],
        };
      case 'SRC-IP-CIDR':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'source': [arg],
        };
      case 'DST-PORT':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'port': arg,
        };
      case 'SRC-PORT':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'sourcePort': arg,
        };
      case 'NETWORK':
        return {
          'type': 'field',
          'outboundTag': outboundTag,
          'network': arg.toLowerCase(),
        };
      case 'MATCH':
      case 'FINAL':
        // Only emit if directing to direct or block (default is proxy)
        if (outboundTag != 'proxy') {
          return {
            'type': 'field',
            'outboundTag': outboundTag,
            'network': 'tcp,udp',
          };
        }
        return null;
      default:
        return null;
    }
  }
}
