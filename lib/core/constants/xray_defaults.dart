class XrayDefaults {
  static const socksListen = '127.0.0.1';
  static const bootstrapDns = '8.8.8.8';

  /// geosite codes ad blocking matches; codes missing from geosite.dat are left out.
  static const adBlockCodes = ['category-ads-all', 'win-spy'];

  // xray policy timeouts (seconds)
  static const handshakeTimeout = 4;
  static const connIdleTimeout = 120;
  static const uplinkOnlyTimeout = 5;
  static const downlinkOnlyTimeout = 30;
}
