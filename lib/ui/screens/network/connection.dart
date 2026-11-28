part of 'network_settings_screen.dart';

extension _ConnectionSections on _NetworkSettingsScreenState {
  /// The local SOCKS proxy: port and credentials.
  List<Widget> _socksSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x31', label: 'socks'),
      SetRowToggle(
        t: t,
        title: l.networkRandomPort,
        hint: l.networkRandomPortHint,
        value: s.randomPort,
        locked: locked,
        onChange: (v) => _set(SettingFields.randomPort, v),
      ),
      if (!s.randomPort)
        SetInlineField(
          t: t,
          label: l.networkSocksPort,
          locked: locked,
          child: SetNumField(
            t: t,
            controller: _socksPortCtrl!,
            enabled: !locked,
            hint: '10808',
            onCommit: (v) => _settings.commitInt(SettingFields.socksPort, v),
          ),
        ),
      SetRowToggle(
        t: t,
        title: l.networkRandomCreds,
        hint: l.networkRandomCredsHint,
        value: s.randomCredentials,
        locked: locked,
        onChange: (v) => _set(SettingFields.randomCredentials, v),
      ),
      if (!s.randomCredentials) ...[
        SetInlineField(
          t: t,
          label: l.networkSocksLogin,
          locked: locked,
          child: SetCredField(
            controller: _socksUserCtrl!,
            enabled: !locked,
            hint: l.networkNoAuth,
            onCommit: (_) => _updateSocksCredentials(),
            t: t,
          ),
        ),
        SetInlineField(
          t: t,
          label: l.networkSocksPassword,
          locked: locked,
          child: SetCredField(
            controller: _socksPasswordCtrl!,
            enabled: !locked,
            hint: l.networkNoAuth,
            obscureText: true,
            onCommit: (_) => _updateSocksCredentials(),
            t: t,
          ),
        ),
      ],
      FeatureGate(
        feature: CoreFeature.proxyOnly,
        child: SetRowToggle(
          t: t,
          title: l.networkProxyOnly,
          hint: l.networkProxyOnlyHint,
          value: s.proxyOnly,
          locked: locked,
          onChange: (v) => _set(SettingFields.proxyOnly, v),
        ),
      ),
    ];
  }

  /// What the tunnel carries: proxy-only mode, UDP, ICMP, QUIC.
  List<Widget> _trafficSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x32', label: 'traffic'),
      SetRowToggle(
        t: t,
        title: 'UDP',
        hint: l.networkUdpHint,
        value: s.enableUdp,
        locked: locked,
        onChange: (v) => _set(SettingFields.enableUdp, v),
      ),
      FeatureGate(
        feature: CoreFeature.icmpToggle,
        child: SetRowToggle(
          t: t,
          title: 'ICMP (ping)',
          hint: l.networkIcmpHint,
          value: s.allowIcmp,
          locked: locked,
          onChange: (v) => _set(SettingFields.allowIcmp, v),
        ),
      ),
      SetRowToggle(
        t: t,
        title: l.networkBlockQuic,
        hint: l.networkBlockQuicHint,
        value: s.blockQuic,
        locked: locked,
        onChange: (v) => _set(SettingFields.blockQuic, v),
      ),
      // TLS fingerprint (uTLS) override
      Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TLS fingerprint', style: AppTheme.sans(size: 14, color: t.text)),
                  const SizedBox(height: 3),
                  Text(
                    l.networkFingerprintHint,
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            TapTarget(
              onTap: locked ? () => showReadonlySnack(context) : () => _showFingerprintPicker(context, s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: t.line)),
                child: Text(
                  _fpLabel(s.tlsFingerprint),
                  style: AppTheme.mono(size: 11, color: locked ? t.textDim : t.accent, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// The TUN interface: IPv6, MTU and the observatory interval.
  List<Widget> _tunSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x33', label: 'tun'),
      if (!s.proxyOnly)
        SetRowToggle(
          t: t,
          title: l.networkIpv6,
          hint: l.networkIpv6Hint,
          value: s.ipv6Enabled,
          locked: locked,
          onChange: (v) => _set(SettingFields.ipv6Enabled, v),
        ),
      if (!s.proxyOnly)
        FeatureGate(
          feature: CoreFeature.customMtu,
          child: SetInlineField(
            t: t,
            label: 'MTU',
            locked: locked,
            child: SetNumField(
              t: t,
              controller: _mtuCtrl!,
              enabled: !locked,
              hint: '1500',
              onCommit: (v) => _settings.commitInt(SettingFields.mtu, v),
            ),
          ),
        ),
      FeatureGate(
        feature: CoreFeature.observatory,
        child: SetInlineField(
          t: t,
          label: l.networkObservatoryInterval,
          locked: locked,
          child: SetNumField(
            t: t,
            controller: _obsCtrl!,
            enabled: !locked,
            hint: '600',
            onCommit: (v) => _settings.commitInt(SettingFields.obsProbeIntervalSec, v),
          ),
        ),
      ),
    ];
  }
}
