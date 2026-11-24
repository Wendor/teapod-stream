class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime createdAt;
  final DateTime? lastFetchedAt;
  final DateTime? expireAt;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final String? announce;
  final String? announceUrl;

  /// DER (base64) of a self-signed certificate the user accepted
  /// manually (TOFU). Auto-refresh trusts only it, not any certificate.
  final String? pinnedCertDer;

  /// Sends the raw device id as HWID (a subscription added before ids became per host: the provider already counts
  /// the device by it); otherwise the id derived for the subscription host (`HwidDeviceInfo.forHost`).
  final bool rawHwid;

  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
    this.lastFetchedAt,
    this.expireAt,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.announce,
    this.announceUrl,
    this.pinnedCertDer,
    this.rawHwid = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'createdAt': createdAt.toIso8601String(),
    'lastFetchedAt': lastFetchedAt?.toIso8601String(),
    'expireAt': expireAt?.toIso8601String(),
    'uploadBytes': uploadBytes,
    'downloadBytes': downloadBytes,
    'totalBytes': totalBytes,
    'announce': announce,
    'announceUrl': announceUrl,
    'pinnedCertDer': pinnedCertDer,
    'rawHwid': rawHwid,
  };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastFetchedAt: json['lastFetchedAt'] != null ? DateTime.parse(json['lastFetchedAt'] as String) : null,
    expireAt: json['expireAt'] != null ? DateTime.parse(json['expireAt'] as String) : null,
    uploadBytes: json['uploadBytes'] as int?,
    downloadBytes: json['downloadBytes'] as int?,
    totalBytes: json['totalBytes'] as int?,
    announce: json['announce'] as String?,
    announceUrl: json['announceUrl'] as String?,
    pinnedCertDer: json['pinnedCertDer'] as String?,
    // Stored before the field existed: the subscription has registered the raw id.
    rawHwid: json['rawHwid'] as bool? ?? true,
  );

  Subscription copyWith({
    String? name,
    DateTime? lastFetchedAt,
    DateTime? expireAt,
    int? uploadBytes,
    int? downloadBytes,
    int? totalBytes,
    String? announce,
    String? announceUrl,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      url: url,
      createdAt: createdAt,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      expireAt: expireAt ?? this.expireAt,
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      announce: announce ?? this.announce,
      announceUrl: announceUrl ?? this.announceUrl,
      pinnedCertDer: pinnedCertDer,
      rawHwid: rawHwid,
    );
  }
}
