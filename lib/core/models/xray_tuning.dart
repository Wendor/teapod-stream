/// A `from-to` range that xray parses with `ParseRangeString`.
final _rangeRe = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$');

bool _isRange(String v, {bool minPositive = false}) {
  final m = _rangeRe.firstMatch(v);
  if (m == null) return false;
  final from = int.parse(m.group(1)!);
  final to = int.parse(m.group(2)!);
  if (from > to) return false;
  return !minPositive || from > 0;
}

/// Fragmentation of the outgoing TCP stream (xray freedom outbound `fragment`).
/// Applied via `sockopt.dialerProxy` on the proxy outbound: the payload
/// is split into pieces so DPI can't reassemble the whole ClientHello.
class FragmentSettings {
  final bool enabled;

  /// `tlshello` — split only the TLS ClientHello; a range like `1-3` — the first N packets.
  final String packets;

  /// Chunk length in bytes, a `from-to` range.
  final String length;

  /// Pause between chunks in ms, a `from-to` range.
  final String interval;

  const FragmentSettings({
    this.enabled = false,
    this.packets = 'tlshello',
    this.length = '100-200',
    this.interval = '10-20',
  });

  FragmentSettings copyWith({
    bool? enabled,
    String? packets,
    String? length,
    String? interval,
  }) =>
      FragmentSettings(
        enabled: enabled ?? this.enabled,
        packets: packets ?? this.packets,
        length: length ?? this.length,
        interval: interval ?? this.interval,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'packets': packets,
        'length': length,
        'interval': interval,
      };

  static FragmentSettings fromJson(Map<String, dynamic> json) => FragmentSettings(
        enabled: json['enabled'] as bool? ?? false,
        packets: json['packets'] as String? ?? 'tlshello',
        length: json['length'] as String? ?? '100-200',
        interval: json['interval'] as String? ?? '10-20',
      );

  /// Fields are entered by hand: garbage in length/interval breaks the whole xray startup
  /// ("Length can't be empty", "Invalid PacketsFrom"). The builder applies
  /// fragmentation only when the values parse.
  bool get isValid {
    final p = packets.trim();
    final packetsOk = p.isEmpty || p == 'tlshello' || _isRange(p, minPositive: true);
    return packetsOk && _isRange(length, minPositive: true) && _isRange(interval);
  }
}

/// Noise packet type: random or user-defined.
enum NoiseType { rand, str, hex, base64 }

/// Noise UDP packets before the first real datagram (xray freedom `noises`).
/// Work only on the UDP leg — Hysteria2 and the QUIC transport; TCP connections
/// aren't affected by noise (there [FragmentSettings] works).
class NoiseSettings {
  final bool enabled;
  final NoiseType type;

  /// For `rand` — a length range in bytes (`50-100`); for other types —
  /// the string / hex / base64 itself.
  final String packet;

  /// Pause before sending, ms, a `from-to` range.
  final String delay;

  const NoiseSettings({
    this.enabled = false,
    this.type = NoiseType.rand,
    this.packet = '50-100',
    this.delay = '10-20',
  });

  NoiseSettings copyWith({
    bool? enabled,
    NoiseType? type,
    String? packet,
    String? delay,
  }) =>
      NoiseSettings(
        enabled: enabled ?? this.enabled,
        type: type ?? this.type,
        packet: packet ?? this.packet,
        delay: delay ?? this.delay,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'type': type.name,
        'packet': packet,
        'delay': delay,
      };

  static NoiseSettings fromJson(Map<String, dynamic> json) => NoiseSettings(
        enabled: json['enabled'] as bool? ?? false,
        type: NoiseType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => NoiseType.rand,
        ),
        packet: json['packet'] as String? ?? '50-100',
        delay: json['delay'] as String? ?? '10-20',
      );

  bool get isValid {
    if (packet.trim().isEmpty) return false;
    if (type == NoiseType.rand && !_isRange(packet, minPositive: true)) return false;
    return _isRange(delay);
  }
}

/// xray-mux behavior for UDP/443 (QUIC): drop, pass through mux or bypass it.
enum XudpUdp443 { reject, allow, skip }

/// Multiplexing several connections into one (xray `mux`).
class MuxSettings {
  final bool enabled;

  /// Number of TCP substreams in one connection, 1–1024.
  final int concurrency;

  /// Number of XUDP substreams, 1–1024. Responsible for UDP over mux.
  final int xudpConcurrency;

  final XudpUdp443 xudpProxyUDP443;

  const MuxSettings({
    this.enabled = false,
    this.concurrency = 8,
    this.xudpConcurrency = 16,
    this.xudpProxyUDP443 = XudpUdp443.reject,
  });

  MuxSettings copyWith({
    bool? enabled,
    int? concurrency,
    int? xudpConcurrency,
    XudpUdp443? xudpProxyUDP443,
  }) =>
      MuxSettings(
        enabled: enabled ?? this.enabled,
        concurrency: concurrency ?? this.concurrency,
        xudpConcurrency: xudpConcurrency ?? this.xudpConcurrency,
        xudpProxyUDP443: xudpProxyUDP443 ?? this.xudpProxyUDP443,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'concurrency': concurrency,
        'xudpConcurrency': xudpConcurrency,
        'xudpProxyUDP443': xudpProxyUDP443.name,
      };

  static MuxSettings fromJson(Map<String, dynamic> json) => MuxSettings(
        enabled: json['enabled'] as bool? ?? false,
        concurrency: json['concurrency'] as int? ?? 8,
        xudpConcurrency: json['xudpConcurrency'] as int? ?? 16,
        xudpProxyUDP443: XudpUdp443.values.firstWhere(
          (e) => e.name == json['xudpProxyUDP443'],
          orElse: () => XudpUdp443.reject,
        ),
      );
}
