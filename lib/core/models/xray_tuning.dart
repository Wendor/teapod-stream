/// Диапазон вида `от-до`, который xray разбирает через `ParseRangeString`.
final _rangeRe = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$');

bool _isRange(String v, {bool minPositive = false}) {
  final m = _rangeRe.firstMatch(v);
  if (m == null) return false;
  final from = int.parse(m.group(1)!);
  final to = int.parse(m.group(2)!);
  if (from > to) return false;
  return !minPositive || from > 0;
}

/// Фрагментация исходящего TCP-потока (xray freedom outbound `fragment`).
/// Применяется через `sockopt.dialerProxy` на proxy-outbound: полезная нагрузка
/// режется на части, чтобы DPI не собрал ClientHello целиком.
class FragmentSettings {
  final bool enabled;

  /// `tlshello` — резать только TLS ClientHello; диапазон вида `1-3` — первые N пакетов.
  final String packets;

  /// Длина куска в байтах, диапазон `от-до`.
  final String length;

  /// Пауза между кусками в мс, диапазон `от-до`.
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

  /// Поля вводятся руками: мусор в length/interval валит старт xray целиком
  /// («Length can't be empty», «Invalid PacketsFrom»). Билдер применяет
  /// фрагментацию только когда значения разбираемы.
  bool get isValid {
    final p = packets.trim();
    final packetsOk = p.isEmpty || p == 'tlshello' || _isRange(p, minPositive: true);
    return packetsOk && _isRange(length, minPositive: true) && _isRange(interval);
  }
}

/// Тип шумового пакета: случайный либо заданный пользователем.
enum NoiseType { rand, str, hex, base64 }

/// Шумовые UDP-пакеты перед первой полезной датаграммой (xray freedom `noises`).
/// Работают только на UDP-плече — Hysteria2 и QUIC-транспорт; TCP-соединения
/// шумом не обрабатываются (там работает [FragmentSettings]).
class NoiseSettings {
  final bool enabled;
  final NoiseType type;

  /// Для `rand` — диапазон длины в байтах (`50-100`); для остальных типов —
  /// сама строка / hex / base64.
  final String packet;

  /// Пауза перед отправкой, мс, диапазон `от-до`.
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

/// Поведение xray-mux для UDP/443 (QUIC): отбрасывать, пускать через mux или мимо него.
enum XudpUdp443 { reject, allow, skip }

/// Мультиплексирование нескольких соединений в одно (xray `mux`).
class MuxSettings {
  final bool enabled;

  /// Число TCP-подпотоков в одном соединении, 1–1024.
  final int concurrency;

  /// Число XUDP-подпотоков, 1–1024. Отвечает за UDP поверх mux.
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
