class SpeedPoint {
  final int uploadSpeed;
  final int downloadSpeed;

  const SpeedPoint({this.uploadSpeed = 0, this.downloadSpeed = 0});

  factory SpeedPoint.fromMap(Map<String, dynamic> map) {
    return SpeedPoint(
      uploadSpeed: (map['uploadSpeed'] as num?)?.toInt() ?? 0,
      downloadSpeed: (map['downloadSpeed'] as num?)?.toInt() ?? 0,
    );
  }
}

class VpnStats {
  final int uploadBytes;
  final int downloadBytes;
  final int uploadSpeedBps;
  final int downloadSpeedBps;
  final Duration connectedDuration;
  final String? connectedServer;
  final List<SpeedPoint> speedHistory;

  const VpnStats({
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.uploadSpeedBps = 0,
    this.downloadSpeedBps = 0,
    this.connectedDuration = Duration.zero,
    this.connectedServer,
    this.speedHistory = const [],
  });

  VpnStats copyWith({
    int? uploadBytes,
    int? downloadBytes,
    int? uploadSpeedBps,
    int? downloadSpeedBps,
    Duration? connectedDuration,
    String? connectedServer,
    List<SpeedPoint>? speedHistory,
  }) {
    return VpnStats(
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      uploadSpeedBps: uploadSpeedBps ?? this.uploadSpeedBps,
      downloadSpeedBps: downloadSpeedBps ?? this.downloadSpeedBps,
      connectedDuration: connectedDuration ?? this.connectedDuration,
      connectedServer: connectedServer ?? this.connectedServer,
      speedHistory: speedHistory ?? this.speedHistory,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(int bps) {
    final bits = bps * 8;
    if (bits < 1024) return '$bits bit/s';
    if (bits < 1024 * 1024) return '${(bits / 1024).toStringAsFixed(1)} Kbit/s';
    return '${(bits / (1024 * 1024)).toStringAsFixed(1)} Mbit/s';
  }

  static String formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
