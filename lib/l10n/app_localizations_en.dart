// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tabConfigs => 'Configs';

  @override
  String get tabRouting => 'Routing';

  @override
  String get tabSettings => 'Settings';

  @override
  String get homeNoConfigShort => 'no config';

  @override
  String get homeUnsupported => 'not supported';

  @override
  String get homeNoConfig => 'no configuration';

  @override
  String get homeLogs => 'logs';

  @override
  String homeTunnel(String proto) {
    return 'TUNNEL · $proto';
  }

  @override
  String get homeKillSwitchBlocked => 'kill switch · traffic blocked';

  @override
  String get homeConnectError => 'connection error';

  @override
  String get homeTapToRetry => 'tap to retry';

  @override
  String get homeConnecting => 'establishing connection…';

  @override
  String get homeDisconnecting => 'closing session…';

  @override
  String get homeNoConfigAdd => 'no configuration — add one';

  @override
  String get homeTapToConnect => 'tap to connect';

  @override
  String get homeIpUnknown => 'IP not detected';

  @override
  String get homeDisconnectButton => 'DISCONNECT';

  @override
  String get homeActionReconnect => 'reconnect';

  @override
  String get homeActionDisconnect => 'disconnect';

  @override
  String get homeActionWait => 'waiting';

  @override
  String get homeActionConnect => 'connect';

  @override
  String get homeChangeServer => 'change server';

  @override
  String get homeServer => 'Server';

  @override
  String get homePing => 'Ping';

  @override
  String get homeUpload => 'Upload';

  @override
  String get homeDownload => 'Download';

  @override
  String get homeCoreEnableHint => 'enable a core in settings or switch the config';

  @override
  String get homeCorePinned => 'pinned';

  @override
  String get homeManagedOnlySelected =>
      'domain \"Only\" mode and DNS settings don\'t apply · routing is controlled by the server';

  @override
  String get homeManagedDns => 'DNS settings don\'t apply · routing is controlled by the server';

  @override
  String get homeTrafficLive => 'TRAFFIC — LIVE';

  @override
  String homePeak(String value) {
    return 'peak $value';
  }

  @override
  String commonErrorWith(String error) {
    return 'Error: $error';
  }

  @override
  String get commonRename => 'Rename';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonName => 'Name';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonContinue => 'Continue';

  @override
  String get configsHideGroups => 'hide groups';

  @override
  String get configsSortByPing => 'sort by ping';

  @override
  String get configsSortMode => 'sort mode';

  @override
  String get configsPin => 'Pin';

  @override
  String get configsUnpin => 'Unpin';

  @override
  String get configsCore => 'Core';

  @override
  String get configsCoreNone => 'none';

  @override
  String get configsEditUri => 'Edit URI';

  @override
  String get configsCopyUrl => 'Copy URL';

  @override
  String get configsUrlCopied => 'URL copied';

  @override
  String get configsShare => 'Share';

  @override
  String get configsUriParseFailed => 'Couldn\'t parse the URI';

  @override
  String get configsDeleteTitle => 'Delete?';

  @override
  String configsDeleteMessage(String name) {
    return 'Configuration \"$name\" will be deleted.';
  }

  @override
  String get configsSubUpdated => 'Subscription updated';

  @override
  String get certUntrustedTitle => 'Untrusted certificate';

  @override
  String get certUntrustedMessage =>
      'The server uses a self-signed or unknown certificate. The connection may be insecure.';

  @override
  String certServer(String host) {
    return 'Server: $host';
  }

  @override
  String certSubject(String subject) {
    return 'Certificate: $subject';
  }

  @override
  String certIssuer(String issuer) {
    return 'Issuer: $issuer';
  }

  @override
  String certFingerprint(String fingerprint) {
    return 'SHA-256: $fingerprint';
  }

  @override
  String get certContinueAnyway => 'Continue anyway?';

  @override
  String configsUpdateError(String error) {
    return 'Update error: $error';
  }

  @override
  String get configsRenameSub => 'Rename subscription';

  @override
  String get configsEditSubUrl => 'Change subscription URL';

  @override
  String get configsSaveAndRefresh => 'Save and refresh';

  @override
  String get configsSubUpdatedNewUrl => 'Subscription updated from the new URL';

  @override
  String get configsDeleteSubTitle => 'Delete subscription?';

  @override
  String configsDeleteSubMessage(String name) {
    return 'Subscription \"$name\" and all its configurations will be deleted.';
  }

  @override
  String configsSubsUpdated(int count) {
    return 'Subscriptions updated: $count';
  }

  @override
  String configsSubsUpdatedPartial(int ok, int total) {
    return 'Updated $ok of $total';
  }

  @override
  String get configsTagline => 'CONFIGURATIONS';

  @override
  String get configsDisplaySettings => 'display settings';

  @override
  String get configsSubSettings => 'subscription settings';

  @override
  String get configsExport => 'export connections';

  @override
  String get configsRefreshSubs => 'refresh subscriptions';

  @override
  String get configsAdd => 'add';

  @override
  String get subNeverUpdated => 'Never updated';

  @override
  String get subJustNow => 'Just now';

  @override
  String subMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String subHoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String subDaysAgo(int count) {
    return '$count d ago';
  }

  @override
  String get subExpired => 'Expired';

  @override
  String get configsSubMenu => 'subscription menu';

  @override
  String configsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count configs', one: '$count config');
    return '$_temp0';
  }

  @override
  String get configsAutoSelectReset => 'Reset auto-select';

  @override
  String get configsAutoSelectBest => 'Auto-select best';

  @override
  String get configsEditUrl => 'Change URL';

  @override
  String get configsRefresh => 'Refresh';

  @override
  String get configsConfigMenu => 'configuration menu';

  @override
  String get configsNotInSub => 'not in subscription';

  @override
  String get configsPinned => 'pinned';

  @override
  String get configsPinUnavailable => 'unavailable · tap to unpin';

  @override
  String get configsEmpty => 'Add a configuration\nor a subscription';

  @override
  String get routingSplitOff => 'off · all apps through VPN';

  @override
  String routingSplitOnly(int count) {
    return '$count apps · ONLY';
  }

  @override
  String routingSplitExcept(int count) {
    return '$count apps · EXCEPT';
  }

  @override
  String get routingModeGlobalHint => 'all traffic through VPN · rules off';

  @override
  String routingModeBypassHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count rules', one: '$count rule');
    return '$_temp0 · matched go direct, the rest through VPN';
  }

  @override
  String routingModeOnlyHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count rules', one: '$count rule');
    return '$_temp0 · only matched through VPN';
  }

  @override
  String get routingGeoMissingHint => 'Download the geo databases (geo.data section below)';

  @override
  String get routingSniffHint => 'Requires sniffing (the \"Sniffing\" switch above)';

  @override
  String get routingTagline => 'ROUTING · SPLIT-TUNNEL';

  @override
  String get routingSplitTunnel => 'Split tunneling';

  @override
  String get routingLocalNetworks => 'Local networks';

  @override
  String get routingLocalNetworksHint => 'Don\'t tunnel 10/8, 192.168/16';

  @override
  String get routingAddRegion => 'region';

  @override
  String get routingSniffing => 'Sniffing';

  @override
  String get routingSniffingHint => 'Detect the domain from TLS SNI · needed for domain.suffix and geosite';

  @override
  String get routingAddSuffix => 'suffix';

  @override
  String get routingAddCategory => 'category';

  @override
  String get routingAddSite => 'site';

  @override
  String get routingAdBlock => 'Ad blocking';

  @override
  String get routingRuServices => 'Russian services';

  @override
  String get routingRuServicesHint => 'Yandex, VK, Sber, Ozon, Avito, etc. → selected outbound';

  @override
  String get routingKillSwitchHint => 'Block traffic when the VPN drops';

  @override
  String get routingSource => 'SOURCE';

  @override
  String get routingSourceCustom => 'Custom';

  @override
  String get countryRu => 'Russia';

  @override
  String get countryBy => 'Belarus';

  @override
  String get countryKz => 'Kazakhstan';

  @override
  String get countryUa => 'Ukraine';

  @override
  String get countryCn => 'China';

  @override
  String get countryUs => 'USA';

  @override
  String get countryDe => 'Germany';

  @override
  String get countryGb => 'United Kingdom';

  @override
  String get countryFr => 'France';

  @override
  String get countryNl => 'Netherlands';

  @override
  String get countryTr => 'Turkey';

  @override
  String get countryJp => 'Japan';

  @override
  String get countrySe => 'Sweden';

  @override
  String get countryFi => 'Finland';

  @override
  String get countryPl => 'Poland';

  @override
  String get routingRegions => 'REGIONS';

  @override
  String get routingCountries => 'countries';

  @override
  String get routingServices => 'services';

  @override
  String get routingGeoipCustomHint => 'Code or category (e.g. IT, netflix)';

  @override
  String get routingSuffixes => 'SUFFIXES';

  @override
  String get routingDomainCustomHint => 'Domain or zone (e.g. example.com)';

  @override
  String get routingSites => 'SITES';

  @override
  String get routingSiteCustomHint => 'Site (e.g. example.com)';

  @override
  String get geositeCategoryRu => 'Russia (category)';

  @override
  String get geositeGeoDetect => 'Geo-detect services';

  @override
  String get geositeGames => 'Games';

  @override
  String get routingCategories => 'CATEGORIES';

  @override
  String get routingGeositeCustomHint => 'Category (e.g. geolocation-!cn)';

  @override
  String get routingModeAll => 'all traffic';

  @override
  String get routingModeRules => 'by rules';

  @override
  String get routingModeMatch => 'match only';

  @override
  String get commonDone => 'DONE';

  @override
  String get geoNotLoaded => 'Geo databases not downloaded';

  @override
  String get geoDownload => 'DOWNLOAD';

  @override
  String get geoLoaded => 'Geo databases downloaded';

  @override
  String get geoUpdate => 'UPDATE';

  @override
  String get geoDownloading => 'Downloading geo databases...';

  @override
  String get unitMb => 'MB';

  @override
  String get commonRetryUpper => 'RETRY';

  @override
  String get geoUpdatedToday => 'Updated today';

  @override
  String get geoUpdatedYesterday => 'Updated yesterday';

  @override
  String geoUpdatedDaysAgo(int count) {
    return 'Updated $count days ago';
  }

  @override
  String get commonApplyUpper => 'APPLY';

  @override
  String get settingsTagline => 'PARAMETERS · LOCAL PROFILE';

  @override
  String get settingsProfileLocked => 'profile locked · read-only';

  @override
  String settingsProfileAutosave(String name) {
    return 'profile: $name · autosave';
  }

  @override
  String get settingsLogs => 'Logs';

  @override
  String get settingsLogsHint => 'app and xray log';

  @override
  String get settingsAutoConnect => 'Auto-connect';

  @override
  String get settingsAutoConnectHint => 'Connect when the app starts';

  @override
  String get settingsStartOnBoot => 'Start on boot';

  @override
  String get settingsStartOnBootHint => 'Connect automatically after the device reboots';

  @override
  String get settingsAutomation => 'Automation';

  @override
  String get settingsAutomationHint =>
      'Tasker/Anubis: CONNECT/DISCONNECT commands and state broadcasts. Any app will be able to turn off the VPN and learn that it is on';

  @override
  String get settingsNotification => 'Notification';

  @override
  String get settingsNotificationHint => 'Speed and a disconnect button in the shade';

  @override
  String get settingsSubscriptions => 'Subscriptions';

  @override
  String settingsSubAutoRefreshOn(int hours) {
    return 'auto-refresh · ${hours}h';
  }

  @override
  String get settingsSubAutoRefreshOff => 'auto-refresh off';

  @override
  String get settingsNetwork => 'Network';

  @override
  String get settingsProxyOnlyShort => 'proxy only';

  @override
  String get dnsViaVpn => 'via VPN';

  @override
  String get dnsDirect => 'direct';

  @override
  String get settingsUpdateChannel => 'Update channel';

  @override
  String get settingsCoreLastEnabled => 'At least one core must stay enabled';

  @override
  String get settingsCores => 'Cores';

  @override
  String get settingsCoresHint => 'A profile runs on the topmost core that supports it';

  @override
  String settingsCoreMoveUp(String core) {
    return 'move $core up';
  }

  @override
  String get settingsCoreUnavailable => 'doesn\'t load on this device';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'DARK';

  @override
  String get settingsThemeLight => 'LIGHT';

  @override
  String get settingsSystem => 'SYSTEM';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsFontSize => 'Font size';

  @override
  String get settingsFontNormal => 'NORMAL';

  @override
  String get settingsFontLarge => 'LARGE';

  @override
  String get settingsAccentColor => 'ACCENT COLOR';

  @override
  String get updateTitle => 'Updates';

  @override
  String get updateCheck => 'CHECK';

  @override
  String get updateChecking => 'Checking...';

  @override
  String updateDownloading(String version) {
    return 'Downloading v$version';
  }

  @override
  String get commonCancelUpper => 'CANCEL';

  @override
  String updateReadyToInstall(String version) {
    return 'v$version ready to install';
  }

  @override
  String get updateInstall => 'INSTALL';

  @override
  String get updateAvailable => 'update available';

  @override
  String get updateUpToDate => 'up to date';

  @override
  String get updateResume => 'RESUME';

  @override
  String get updateDownload => 'DOWNLOAD';

  @override
  String get updateReinstall => 'REINSTALL';

  @override
  String get commonLoading => 'loading...';

  @override
  String get profileReadonly => 'read-only';

  @override
  String get settingsProfiles => 'Profiles';

  @override
  String get networkTagline => 'NETWORK · SOCKS · TUN';

  @override
  String get networkRandomPort => 'Random port';

  @override
  String get networkRandomPortHint => 'Random SOCKS port on every connection';

  @override
  String get networkSocksPort => 'SOCKS5 port';

  @override
  String get networkRandomCreds => 'Random credentials';

  @override
  String get networkRandomCredsHint => 'Generate a random SOCKS login/password';

  @override
  String get networkSocksLogin => 'SOCKS login';

  @override
  String get networkNoAuth => 'no password';

  @override
  String get networkSocksPassword => 'SOCKS password';

  @override
  String get networkProxyOnly => 'Proxy only';

  @override
  String get networkProxyOnlyHint => 'Run the SOCKS proxy without a VPN tunnel';

  @override
  String get networkUdpHint => 'Allow UDP traffic through SOCKS';

  @override
  String get networkIcmpHint =>
      'Answer pings: the proxy doesn\'t carry ICMP, the VPN replies itself — the time doesn\'t reflect latency to the host';

  @override
  String get networkBlockQuic => 'Block QUIC';

  @override
  String get networkBlockQuicHint =>
      'TUN answers UDP 443 with an ICMP \"port unreachable\": the browser instantly falls back to TCP instead of waiting for the QUIC timeout (~55s). No traffic leaves the device.';

  @override
  String get networkFingerprintHint => 'uTLS ClientHello camouflage (TLS/REALITY)';

  @override
  String get networkIpv6 => 'IPv6 in tunnel';

  @override
  String get networkIpv6Hint =>
      'Add an IPv6 address to the TUN interface. Enable only if the VPN server has IPv6: otherwise apps with IPv6 addresses (Telegram) hang. When off, IPv6 is blocked by the system without leaks — apps fall back to IPv4 instantly.';

  @override
  String get networkObservatoryInterval => 'Observatory min. interval, sec';

  @override
  String get networkFragment => 'Fragmentation';

  @override
  String get networkFragmentHint =>
      'Splits the outgoing TCP stream into pieces so DPI can\'t reassemble the whole ClientHello. Doesn\'t apply to Hysteria2 (QUIC over UDP).';

  @override
  String get networkFragmentPackets => 'Packets';

  @override
  String get networkFragmentLength => 'Chunk length, bytes';

  @override
  String get networkPauseMs => 'Pause, ms';

  @override
  String get networkFragmentInvalid =>
      'Length and pause must be ranges like 100-200 and 10-20, packets — tlshello or a range. Fragmentation is not applied.';

  @override
  String get networkNoise => 'Noise';

  @override
  String get networkNoiseHint =>
      'Junk UDP datagrams before the first real one. Work only on the UDP leg — Hysteria2 and the QUIC transport; they don\'t affect TCP (use fragmentation there). Xray DNS queries are not affected.';

  @override
  String get networkNoiseType => 'Packet type';

  @override
  String get networkNoiseTypeHint => 'RAND — random bytes; STR / HEX / BASE64 — set manually';

  @override
  String get networkNoiseLength => 'Length, bytes';

  @override
  String get networkNoisePacket => 'Packet';

  @override
  String get networkNoiseContent => 'content';

  @override
  String get networkNoiseInvalidRand => 'Length must be a range like 50-100, pause — 10-20. Noise is not applied.';

  @override
  String get networkNoiseInvalidPacket => 'Packet must not be empty, pause — a range like 10-20. Noise is not applied.';

  @override
  String get networkMuxHint =>
      'Multiplexes several connections into one — fewer handshakes. With XTLS Vision the TCP branch is disabled automatically (XUDP stays). Doesn\'t apply to Hysteria2.';

  @override
  String get networkMuxTcp => 'TCP substreams';

  @override
  String get networkMuxXudp => 'XUDP substreams';

  @override
  String get networkMuxQuic => 'QUIC (UDP/443) via mux';

  @override
  String get networkMuxQuicHint => 'reject — drop, allow — pass through mux, skip — bypass mux';

  @override
  String get networkProbeType => 'Probe type';

  @override
  String get networkProbeTypeHint =>
      'SOCKS — HTTP request through SOCKS5 into xray; XRAYDELAY — measured inside the core, gives latency directly; PASSIVE — no active probes, only tun2socks metrics (saves battery, a drop is noticed only with real traffic)';

  @override
  String get networkProbeTarget => 'Probe target';

  @override
  String get networkProbeTargetHint => 'Where the probe goes. CUSTOM — your own URL below';

  @override
  String get networkFailureThreshold => 'Failures before action';

  @override
  String get networkFailAction => 'When the tunnel is lost';

  @override
  String get networkFailActionHint =>
      'RECONNECT — reconnect to the same server; SWITCHCONFIG — move to the fastest live config';

  @override
  String get networkSwitchSource => 'Where to take a config from';

  @override
  String get networkSwitchSourceHint =>
      'SUBSCRIPTION — configs of the same subscription; PINNED — pinned ones; ALL — all saved. Candidates are checked with a full measurement through the protocol itself, not a TCP ping';

  @override
  String get profilesTagline => 'MANAGEMENT · PROFILES';

  @override
  String get profilesSubtitle => 'switch and manage settings profiles';

  @override
  String get profilesNew => 'New profile';

  @override
  String get profilesNameHint => 'Profile name';

  @override
  String get profilesCopyCurrent => 'Copy current settings';

  @override
  String get commonCreate => 'Create';

  @override
  String get profileImportTitle => 'Import profile';

  @override
  String get profilesImportHint => 'Paste a link (teapod://...) or profile JSON';

  @override
  String get profilesSwitchAfterImport => 'Switch after import';

  @override
  String get profilesReadonly => 'Read-only';

  @override
  String get profilesInvalidFormat => 'Invalid format';

  @override
  String get commonImport => 'Import';

  @override
  String get profilesExportUpper => 'EXPORT';

  @override
  String get profilesCopyLink => 'Copy link';

  @override
  String get profilesLinkCopied => 'Link copied';

  @override
  String get profilesShareFile => 'Share as file';

  @override
  String get profilesDeleteTitle => 'Delete profile?';

  @override
  String profilesDeleteMessage(String name) {
    return '\"$name\" will be deleted permanently.';
  }

  @override
  String profilesUpdated(String name) {
    return 'Profile \"$name\" updated';
  }

  @override
  String get profilesUpdateError => 'Update error';

  @override
  String get profilesSwitch => 'Switch';

  @override
  String get profilesUnlock => 'Unlock';

  @override
  String get profilesLock => 'Lock editing';

  @override
  String get profilesExport => 'Export';

  @override
  String get deeplinkFetchFailed => 'Couldn\'t load data from the link';

  @override
  String get splitTethering => 'Tethering through VPN';

  @override
  String get splitTetheringWarning =>
      'Hotspot traffic is indistinguishable from the traffic of excluded apps. With this option any excluded app can send a request through the VPN and learn the server IP — for example, to report it.\n\nEnable only if you need to share internet through the VPN.';

  @override
  String get commonEnable => 'Enable';

  @override
  String get splitTagline => 'APPS · SPLIT-TUNNEL';

  @override
  String splitSelectedOnly(int count) {
    return '$count selected · only through VPN';
  }

  @override
  String splitExcluded(int count) {
    return '$count excluded · the rest through VPN';
  }

  @override
  String get splitEnabled => 'enabled';

  @override
  String get splitDisabled => 'disabled — all traffic through VPN';

  @override
  String get splitVpnMode => 'VPN mode';

  @override
  String get splitModeOnly => 'ONLY';

  @override
  String get splitModeExcept => 'EXCEPT';

  @override
  String get splitTetheringHint => 'Route hotspot traffic into the tunnel';

  @override
  String get splitTetheringWeakened =>
      'Protection weakened: excluded apps can go out through the VPN and learn the server IP';

  @override
  String get splitSearchHint => 'search apps...';

  @override
  String get splitHideSystem => 'Hide system apps';

  @override
  String get splitNoApps => 'no apps';

  @override
  String get addTagline => 'CONFIGURATION · NEW PROFILE';

  @override
  String addFromClipboard(String text) {
    return 'from clipboard: $text';
  }

  @override
  String get addPaste => 'PASTE';

  @override
  String get addAdd => 'ADD';

  @override
  String get addEnterUrl => 'Enter a URL';

  @override
  String get addDeeplinkParseFailed => 'Couldn\'t parse the deeplink';

  @override
  String addImported(String configs, String subscriptions) {
    return 'Imported: $configs, $subscriptions';
  }

  @override
  String subscriptionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subscriptions',
      one: '$count subscription',
    );
    return '$_temp0';
  }

  @override
  String get addParseFailed =>
      'Couldn\'t recognize the configuration. Supported: vless://, vmess://, trojan://, ss://, hy2://, wireguard://, vpn:// (AmneziaVPN) and WireGuard .conf';

  @override
  String get whatsNewTitle => 'What\'s new';

  @override
  String get whatsNewTagline => 'RELEASE NOTES · ALL VERSIONS';

  @override
  String get subsTagline => 'SUBSCRIPTIONS · REFRESH';

  @override
  String get subsAutoRefresh => 'Subscription auto-refresh';

  @override
  String get subsAutoRefreshHint => 'Refresh subscriptions on a schedule';

  @override
  String get subsInterval => 'Interval';

  @override
  String unitHours(int count) {
    return '${count}h';
  }

  @override
  String get subsHwidHint => 'Send the device ID to bind the subscription';

  @override
  String get commonDefaultLower => 'default';

  @override
  String get logsEmpty => 'Log is empty';

  @override
  String get logsTagline => 'LOG · XRAY · TUN2SOCKS';

  @override
  String qrCameraError(String error) {
    return 'Camera error: $error';
  }

  @override
  String get qrTitle => 'Scan QR';

  @override
  String get commonRetry => 'Retry';

  @override
  String get qrHint => 'Point the camera at a QR code';

  @override
  String get commonSaveUpper => 'SAVE';

  @override
  String get dnsTagline => 'SETTINGS · DNS RESOLVER';

  @override
  String get dnsMode => 'DNS mode';

  @override
  String get dnsViaTunnel => 'via VPN tunnel';

  @override
  String get dnsStrategy => 'DNS strategy';

  @override
  String get dnsStrategyHint => 'IP version for DNS queries';

  @override
  String get dnsProtocolType => 'PROTOCOL TYPE';

  @override
  String get dnsServerAddress => 'SERVER ADDRESS';

  @override
  String get coreInUse => 'in use';

  @override
  String get coreCompatible => 'compatible';

  @override
  String get coreProfileCore => 'PROFILE CORE';

  @override
  String get coreAuto => 'AUTO';

  @override
  String get coreAutoHint =>
      'AUTO — the first suitable core by the priority in settings. A pinned core is tried first.';

  @override
  String featureUnsupported(String cores) {
    return 'Not supported: $cores.';
  }

  @override
  String get reconnectBanner => 'settings changed · will apply after reconnecting';

  @override
  String get reconnectButton => 'RECONNECT';

  @override
  String get settingsReadonlySnack => 'Profile is read-only';

  @override
  String get deeplinkHttpsOnly => 'Import by link supports https only';

  @override
  String deeplinkProfile(String name) {
    return 'Profile: \"$name\"';
  }

  @override
  String deeplinkExported(String date) {
    return 'Exported: $date';
  }

  @override
  String deeplinkSource(String url) {
    return 'Source: $url';
  }

  @override
  String deeplinkProfileImported(String name) {
    return 'Profile \"$name\" imported';
  }

  @override
  String get deeplinkConnectionsTitle => 'Import connections';

  @override
  String deeplinkBundle(String label) {
    return 'Bundle: \"$label\"';
  }

  @override
  String deeplinkAdded(String items) {
    return 'Added: $items';
  }

  @override
  String deeplinkAddedNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added: $count new configs',
      one: 'Added: $count new config',
    );
    return '$_temp0';
  }

  @override
  String get deeplinkFetchTitle => 'Load from link?';

  @override
  String deeplinkFetchMessage(String host) {
    return 'Import data will be loaded from $host directly, bypassing the VPN: the server will see your real IP.';
  }

  @override
  String get deeplinkFetchButton => 'Load';

  @override
  String get rustNoRawJson => 'Full JSON import isn\'t available in the xray-rust core yet.';

  @override
  String get rustNoFinalmask =>
      'The xray-rust core doesn\'t apply the link\'s fm (finalmask) parameter. Set fragmentation and noise in network settings.';

  @override
  String get rustLinkMux => 'The link asks for Mux (mux=on), which isn\'t available in the xray-rust core.';

  @override
  String get rustVlessEncryption => 'The xray-rust core only accepts VLESS with encryption=none so far.';

  @override
  String get rustVlessUuid => 'The VLESS UUID must be a real UUID: the Rust core doesn\'t accept arbitrary strings.';

  @override
  String get rustVlessSecurity => 'For VLESS in the xray-rust core choose TLS or Reality.';

  @override
  String get rustVlessFlow => 'Unknown VLESS flow.';

  @override
  String get rustVision => 'Vision with encryption=none is supported only over TCP/RAW with TLS or Reality.';

  @override
  String get rustTrojanPassword => 'The Trojan password must be non-empty and at most 4096 bytes.';

  @override
  String get rustTrojanSecurity => 'Trojan in the xray-rust core works only with TLS or Reality.';

  @override
  String get rustVmessId => 'The VMess id must be a real UUID: the Rust core doesn\'t accept arbitrary strings.';

  @override
  String rustVmessSecurity(String security) {
    return 'The xray-rust core doesn\'t support VMess with security=$security from the link: TLS and an unencrypted transport are available.';
  }

  @override
  String rustVmessTls(String value) {
    return 'The VMess link sets tls=\"$value\": the parser understands only an exact \"tls\", and the profile would go without TLS. Fix the value in the link.';
  }

  @override
  String rustSsMethod(String method) {
    return 'The Rust core supports only Shadowsocks 2022 (2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305). Method \"$method\" is not supported.';
  }

  @override
  String get rustSsPlugin => 'The xray-rust core doesn\'t support Shadowsocks plugins (SIP003, plugin=…).';

  @override
  String get rustSsPrefix => 'The xray-rust core doesn\'t support the Outline prefix (prefix=…) for Shadowsocks.';

  @override
  String get rustTransport => 'Transport not supported. Available: TCP/RAW, WebSocket, HTTPUpgrade, gRPC and xHTTP.';

  @override
  String rustTcpHeader(String header) {
    return 'The Rust core doesn\'t support TCP with HTTP camouflage (headerType=$header).';
  }

  @override
  String get rustReality => 'Reality is supported with TCP/RAW, gRPC and xHTTP. WebSocket/HTTPUpgrade need TLS.';

  @override
  String get rustEch => 'ECH isn\'t available in the xray-rust core yet.';

  @override
  String rustSsOneKey(String method) {
    return '$method needs a single key (no colon-separated identity keys).';
  }

  @override
  String rustSsMaxKeys(String method) {
    return '$method allows up to 8 colon-separated keys.';
  }

  @override
  String rustSsKey(String method, int bytes) {
    return 'The Shadowsocks 2022 key ($method) must be padded base64 of at least $bytes bytes.';
  }

  @override
  String get rustInsecure =>
      'Rust doesn\'t support allowInsecure without pinSHA256. Use a valid TLS certificate or set the server certificate\'s pinSHA256.';

  @override
  String rustHy2Obfs(String obfs) {
    return 'Hysteria2 obfuscation \"$obfs\" is not supported: the Rust core knows only Salamander.';
  }

  @override
  String get rustSalamanderNoPassword => 'Salamander (obfs=salamander) needs obfs-password.';

  @override
  String get rustSalamanderPassword => 'The Salamander password (obfs-password) must be 4 to 4096 bytes.';

  @override
  String get rustPortHopping => 'The port hopping list is too long: the Rust core accepts up to 65535 ports.';

  @override
  String get rustHy2Password =>
      'The Hysteria2 password must be non-empty, at most 4096 bytes and without control characters.';

  @override
  String get rustTunOnly => 'Only VPN (TUN) mode is available in the xray-rust core.';

  @override
  String get rustMux => 'Mux isn\'t available in the xray-rust core: turn it off in network settings.';

  @override
  String get rustMtu => 'The xray-rust core works with MTU 1500: restore that value in network settings.';

  @override
  String get rustSniffing => 'Enable domain sniffing for GeoSite and domain rules.';

  @override
  String get rustAdBlockLimit =>
      'Ad blocking (~187k domains) together with a large GeoSite category (cn, china-list, category-ads-all) exceeds the Rust core\'s limit of 250k domain rules. Turn off one of the two.';

  @override
  String get rustFragmentPackets =>
      'The Rust core splits only the TLS ClientHello: set tlshello in the fragmentation \"Packets\" field.';

  @override
  String get rustFragmentLength => 'Fragment chunk length in the Rust core is 1 to 16384 bytes.';

  @override
  String get rustFragmentDelay => 'Fragmentation pause in the Rust core is at most 1000 ms.';

  @override
  String get rustFragmentXhttp =>
      'The Rust core doesn\'t apply ClientHello fragmentation to xHTTP with a separate downloadSettings. Fragmentation is a global setting: turn it off in network settings to connect to this profile.';

  @override
  String get rustNoiseSs =>
      'The Rust core doesn\'t send noise before Shadowsocks UDP (only for Hysteria2 and xHTTP over HTTP/3). Noise is a global setting: turn it off in network settings to connect to this profile.';

  @override
  String get rustNoiseDelay => 'Noise pause in the Rust core is at most 1000 ms.';

  @override
  String get rustNoiseHex => 'HEX noise must consist of pairs of hex digits.';

  @override
  String get rustNoiseBase64 => 'BASE64 noise must be standard padded base64.';

  @override
  String get rustNoisePacket => 'A noise packet in the Rust core is at most 4096 bytes.';

  @override
  String coreSingBoxOnly(String protocol) {
    return 'Protocol $protocol is supported only by the sing-box core.';
  }

  @override
  String validateNoProtocolParams(String protocol) {
    return 'No $protocol protocol parameters';
  }

  @override
  String get validateEmptyAddress => 'Empty server address';

  @override
  String validateInvalidPort(int port) {
    return 'Invalid port: $port';
  }

  @override
  String get validateEmptyUuid => 'Empty UUID';

  @override
  String get validateEmptyPassword => 'Empty password';

  @override
  String get routingSummaryGlobal => 'Global';

  @override
  String get routingSummaryBypass => 'Bypass';

  @override
  String get routingSummaryOnly => 'Only';

  @override
  String get dnsCustomServer => 'Custom server';

  @override
  String get coreNoneAvailable => 'No cores available.';

  @override
  String get coreUnavailable => 'Doesn\'t load on this device.';

  @override
  String get coreDisabled => 'Disabled in settings.';

  @override
  String get wgOneInterface => 'A single [Interface] section is required.';

  @override
  String get wgNoPeer => 'No [Peer] section.';

  @override
  String wgOnePeer(int count) {
    return 'A single [Peer] is supported; the config has $count.';
  }

  @override
  String wgMissingKey(String key) {
    return 'The config has no $key.';
  }

  @override
  String wgInvalidEndpoint(String value) {
    return 'Invalid Endpoint: $value';
  }

  @override
  String get singboxNoNoise => 'Noise isn\'t available in the sing-box core and is not applied.';

  @override
  String get singboxNoMux => 'Xray Mux is incompatible with the sing-box core and is not applied.';

  @override
  String get singboxNoObservatory =>
      'Observatory and managed Xray JSON configs aren\'t available in the sing-box core.';

  @override
  String get singboxNoRawConfig => 'A full Xray JSON config isn\'t available in the sing-box core.';

  @override
  String get singboxNoPqv =>
      'Reality: the sing-box core doesn\'t verify the ML-DSA signature (pqv) — the server is verified by the Reality key only.';

  @override
  String singboxFragmentMode(String mode) {
    return 'Fragmentation in the sing-box core covers only the TLS ClientHello; mode \"$mode\" is not applied.';
  }

  @override
  String get singboxNoXhttp => 'The XHTTP transport isn\'t available in the sing-box core.';

  @override
  String get singboxNoXrayExtra => 'Advanced Xray settings (finalmask/extra) aren\'t available in the sing-box core.';

  @override
  String get singboxLinkMux => 'The link asks for Xray Mux (mux=on), which the sing-box core doesn\'t have.';

  @override
  String get singboxNoCertPin =>
      'The sing-box core doesn\'t support certificate pinning: it checks only the public key hash.';

  @override
  String get singboxNoVlessEncryption => 'VLESS Encryption isn\'t available in the sing-box core.';

  @override
  String singboxFlow(String flow) {
    return 'Flow \"$flow\" isn\'t available in the sing-box core.';
  }

  @override
  String get singboxNoSsPlugins => 'Shadowsocks plugins aren\'t available in the sing-box core.';

  @override
  String singboxSsMethod(String method) {
    return 'Shadowsocks method \"$method\" isn\'t available in the sing-box core.';
  }

  @override
  String get singboxAwgReserved => 'AmneziaWG doesn\'t support reserved.';

  @override
  String get singboxAwgHeaders => 'AmneziaWG: header protection requires S1–S4 of at least 12.';

  @override
  String get singboxNoTcpHttp => 'TCP with HTTP obfuscation isn\'t available in the sing-box core.';

  @override
  String get rustNoProxyOnly =>
      '\"Proxy only\" mode isn\'t available in the xray-rust core: it works only through TUN.';

  @override
  String get rustIcmpLocal => 'ICMP is handled locally by the xray-rust core; the setting is not applied.';

  @override
  String get rustMtuIgnored => 'The xray-rust core works with MTU 1500; another value is not applied.';

  @override
  String get rustMuxIgnored => 'Mux isn\'t available in the xray-rust core and is not applied.';

  @override
  String get rustNoObservatory => 'Observatory and managed JSON configs aren\'t available in the xray-rust core.';

  @override
  String get rustNoRawConfig => 'A full JSON config isn\'t available in the xray-rust core.';

  @override
  String get rustSniffingForced =>
      'Domain rules in the xray-rust core require domain sniffing — it is enabled for this connection.';

  @override
  String get rustAdBlockDropped =>
      'Ad blocking together with a large GeoSite category exceeds the xray-rust core\'s limit of 250k domain rules — ad blocking is not applied.';

  @override
  String rustFragmentDropped(String reason) {
    return 'Fragmentation is not applied: $reason';
  }

  @override
  String rustNoiseDropped(String reason) {
    return 'Noise is not applied: $reason';
  }

  @override
  String get xrayNoH2Quic =>
      'The HTTP/2 and QUIC transports were removed from Xray-core: the server needs to move to xHTTP.';

  @override
  String get xrayInsecure =>
      'Xray-core no longer supports allowInsecure: set the server certificate\'s pinSHA256 or use a valid certificate.';

  @override
  String get xrayPinFormat => 'pinSHA256 must be the certificate\'s SHA-256: 64 hex characters or base64 of 32 bytes.';

  @override
  String xrayRawJsonParse(String error) {
    return 'Couldn\'t parse the subscription JSON config: $error';
  }

  @override
  String get profileDefaultName => 'Default';

  @override
  String get geoNoFilesDir => 'Couldn\'t get the files directory';

  @override
  String get subHwidLimit => 'Subscription device limit reached (HWID)';

  @override
  String get subEmpty => 'The subscription returned no configurations';

  @override
  String updateUnsupportedDevice(String abi) {
    return 'Device not supported: $abi';
  }

  @override
  String get updateNoReleaseInfo => 'Couldn\'t get release info';

  @override
  String updateCheckError(String error) {
    return 'Check error: $error';
  }

  @override
  String updateDownloadError(String error) {
    return 'Download error: $error';
  }

  @override
  String get updateInstallError => 'Install error';

  @override
  String get vpnConnectTimeout => 'Connection timeout';

  @override
  String get vpnConnectError => 'Connection error';

  @override
  String get vpnNoConfigSelected => 'No configuration selected';
}
