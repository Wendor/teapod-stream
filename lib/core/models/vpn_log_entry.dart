enum LogLevel { debug, info, warning, error }

class VpnLogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? source;

  const VpnLogEntry({required this.timestamp, required this.level, required this.message, this.source});

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'message': message,
    'source': source,
  };

  factory VpnLogEntry.fromJson(Map<String, dynamic> json) => VpnLogEntry(
    timestamp: DateTime.parse(json['timestamp'] as String),
    level: LogLevel.values.firstWhere((e) => e.name == json['level'], orElse: () => LogLevel.info),
    message: json['message'] as String,
    source: json['source'] as String?,
  );

  factory VpnLogEntry.info(String message, {String? source}) =>
      VpnLogEntry(timestamp: DateTime.now(), level: LogLevel.info, message: message, source: source);

  factory VpnLogEntry.error(String message, {String? source}) =>
      VpnLogEntry(timestamp: DateTime.now(), level: LogLevel.error, message: message, source: source);

  factory VpnLogEntry.warning(String message, {String? source}) =>
      VpnLogEntry(timestamp: DateTime.now(), level: LogLevel.warning, message: message, source: source);

  factory VpnLogEntry.debug(String message, {String? source}) =>
      VpnLogEntry(timestamp: DateTime.now(), level: LogLevel.debug, message: message, source: source);
}
