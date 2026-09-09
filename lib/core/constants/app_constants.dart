class AppConstants {
  static const String appName = 'Teapod Rust Probe';
  static const String appVersion = '1.1.0';

  /// Populated at startup from the xray binary via getBinaryVersions().
  static String xrayCoreVersion = '';

  /// User-Agent sent with subscription HTTP requests.
  /// Format matches common VPN clients so subscription providers don't block us.
  static String get subscriptionUserAgent {
    final xray = xrayCoreVersion.isNotEmpty ? xrayCoreVersion : 'unknown';
    return 'TeapodStream/$appVersion (Android; XrayNG-compatible) Xray-core/$xray';
  }

  static const String methodChannel = 'com.teapodstream/vpn';
  static const String vpnStatusChannel = 'com.teapodstream/vpn_status';

  // Default ports
  static const int defaultSocksPort = 10808;
  static const int defaultHttpPort = 10809;
  static const int defaultDnsPort = 10853;

  // SOCKS auth
  static const int socksAuthPasswordLength = 24;

  // Stats update interval ms
  static const int statsUpdateInterval = 1000;

  // Log limits
  static const int maxLogEntries = 1000;
}
