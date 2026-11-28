part of 'network_settings_screen.dart';

extension _TuningSections on _NetworkSettingsScreenState {
  /// TLS ClientHello fragmentation.
  List<Widget> _fragmentSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x34', label: 'fragment'),
      SetRowToggle(
        t: t,
        title: l.networkFragment,
        hint: l.networkFragmentHint,
        value: s.fragment.enabled,
        locked: locked,
        onChange: (v) => _set(SettingFields.fragmentEnabled, v),
      ),
      if (s.fragment.enabled) ...[
        SetInlineField(
          t: t,
          label: l.networkFragmentPackets,
          locked: locked,
          child: SetCredField(
            t: t,
            controller: _fragPacketsCtrl!,
            enabled: !locked,
            hint: 'tlshello',
            onCommit: (v) => _set(SettingFields.fragmentPackets, v.trim()),
          ),
        ),
        SetInlineField(
          t: t,
          label: l.networkFragmentLength,
          locked: locked,
          child: SetCredField(
            t: t,
            controller: _fragLengthCtrl!,
            enabled: !locked,
            hint: '100-200',
            onCommit: (v) => _set(SettingFields.fragmentLength, v.trim()),
          ),
        ),
        SetInlineField(
          t: t,
          label: l.networkPauseMs,
          locked: locked,
          child: SetCredField(
            t: t,
            controller: _fragIntervalCtrl!,
            enabled: !locked,
            hint: '10-20',
            onCommit: (v) => _set(SettingFields.fragmentInterval, v.trim()),
          ),
        ),
      ],
      if (s.fragment.enabled && !s.fragment.isValid) _HintRow(t: t, text: l.networkFragmentInvalid),
    ];
  }

  /// Noise packets before the first UDP datagram.
  List<Widget> _noiseSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x35', label: 'noise'),
      SetRowToggle(
        t: t,
        title: l.networkNoise,
        hint: l.networkNoiseHint,
        value: s.noise.enabled,
        locked: locked,
        onChange: (v) => _set(SettingFields.noiseEnabled, v),
      ),
      if (s.noise.enabled) ...[
        _PickerRow(
          t: t,
          title: l.networkNoiseType,
          hint: l.networkNoiseTypeHint,
          value: s.noise.type.name.toUpperCase(),
          locked: locked,
          onTap: () => _showEnumPicker<NoiseType>(
            context,
            title: 'noise // type',
            values: NoiseType.values,
            current: s.noise.type,
            labelOf: (v) => v.name.toUpperCase(),
            onPick: (v) => _set(SettingFields.noiseType, v),
          ),
        ),
        SetInlineField(
          t: t,
          label: s.noise.type == NoiseType.rand ? l.networkNoiseLength : l.networkNoisePacket,
          locked: locked,
          child: SetCredField(
            t: t,
            controller: _noisePacketCtrl!,
            enabled: !locked,
            hint: s.noise.type == NoiseType.rand ? '50-100' : l.networkNoiseContent,
            onCommit: (v) => _set(SettingFields.noisePacket, v.trim()),
          ),
        ),
        SetInlineField(
          t: t,
          label: l.networkPauseMs,
          locked: locked,
          child: SetCredField(
            t: t,
            controller: _noiseDelayCtrl!,
            enabled: !locked,
            hint: '10-20',
            onCommit: (v) => _set(SettingFields.noiseDelay, v.trim()),
          ),
        ),
        if (!s.noise.isValid)
          _HintRow(
            t: t,
            text: s.noise.type == NoiseType.rand ? l.networkNoiseInvalidRand : l.networkNoiseInvalidPacket,
          ),
      ],
    ];
  }

  /// Mux: several streams in one connection.
  List<Widget> _muxSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x36', label: 'mux'),
      FeatureGate(
        feature: CoreFeature.mux,
        child: SetRowToggle(
          t: t,
          title: 'Mux',
          hint: l.networkMuxHint,
          value: s.mux.enabled,
          locked: locked,
          onChange: (v) => _set(SettingFields.muxEnabled, v),
        ),
      ),
      if (s.mux.enabled) ...[
        SetInlineField(
          t: t,
          label: l.networkMuxTcp,
          locked: locked,
          child: SetNumField(
            t: t,
            controller: _muxConcCtrl!,
            enabled: !locked,
            hint: '8',
            onCommit: (v) => _settings.commitInt(SettingFields.muxConcurrency, v),
          ),
        ),
        SetInlineField(
          t: t,
          label: l.networkMuxXudp,
          locked: locked,
          child: SetNumField(
            t: t,
            controller: _muxXudpCtrl!,
            enabled: !locked,
            hint: '16',
            onCommit: (v) => _settings.commitInt(SettingFields.muxXudpConcurrency, v),
          ),
        ),
        _PickerRow(
          t: t,
          title: l.networkMuxQuic,
          hint: l.networkMuxQuicHint,
          value: s.mux.xudpProxyUDP443.name.toUpperCase(),
          locked: locked,
          onTap: () => _showEnumPicker<XudpUdp443>(
            context,
            title: 'mux // xudpProxyUDP443',
            values: XudpUdp443.values,
            current: s.mux.xudpProxyUDP443,
            labelOf: (v) => v.name.toUpperCase(),
            onPick: (v) => _set(SettingFields.muxXudpProxyUdp443, v),
          ),
        ),
      ],
    ];
  }
}
