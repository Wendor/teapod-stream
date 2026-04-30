class XrayDefaults {
  static const socksListen = '127.0.0.1';
  static const bootstrapDns = '8.8.8.8';
  static const adBlockGeosite = 'geosite:category-ads-all';

  // xray policy timeouts (seconds)
  static const handshakeTimeout = 4;
  static const connIdleTimeout = 120;
  static const uplinkOnlyTimeout = 5;
  static const downlinkOnlyTimeout = 30;
}
