part of 'network_settings_screen.dart';

extension _HeartbeatSections on _NetworkSettingsScreenState {
  /// The heartbeat: how the tunnel is probed and what a failure does.
  List<Widget> _heartbeatSection(BuildContext context, TeapodTokens t, AppSettings s, bool locked) {
    final l = context.l10n;
    return [
      SetSectionHeader(t: t, addr: '0x37', label: 'heartbeat'),
      _PickerRow(
        t: t,
        title: l.networkProbeType,
        hint: l.networkProbeTypeHint,
        value: s.heartbeat.probe.name.toUpperCase(),
        locked: locked,
        onTap: () => _showEnumPicker<HeartbeatProbe>(
          context,
          title: 'heartbeat // probe',
          values: HeartbeatProbe.values,
          current: s.heartbeat.probe,
          labelOf: (v) => v.name.toUpperCase(),
          onPick: (v) => _set(SettingFields.heartbeatProbe, v),
        ),
      ),
      if (s.heartbeat.probe != HeartbeatProbe.passive) ...[
        _PickerRow(
          t: t,
          title: l.networkProbeTarget,
          hint: l.networkProbeTargetHint,
          value: s.heartbeat.target.name.toUpperCase(),
          locked: locked,
          onTap: () => _showEnumPicker<HeartbeatTarget>(
            context,
            title: 'heartbeat // target',
            values: HeartbeatTarget.values,
            current: s.heartbeat.target,
            labelOf: (v) => v.name.toUpperCase(),
            onPick: (v) => _set(SettingFields.heartbeatTarget, v),
          ),
        ),
        if (s.heartbeat.target == HeartbeatTarget.custom)
          SetInlineField(
            t: t,
            label: 'URL',
            locked: locked,
            child: SetCredField(
              t: t,
              controller: _hbUrlCtrl!,
              enabled: !locked,
              hint: 'http://…/generate_204',
              onCommit: (v) => _set(SettingFields.heartbeatCustomUrl, v.trim()),
            ),
          ),
      ],
      SetInlineField(
        t: t,
        label: l.networkFailureThreshold,
        locked: locked,
        child: SetNumField(
          t: t,
          controller: _hbThresholdCtrl!,
          enabled: !locked,
          hint: '3',
          onCommit: (v) => _settings.commitInt(SettingFields.heartbeatFailureThreshold, v),
        ),
      ),
      _PickerRow(
        t: t,
        title: l.networkFailAction,
        hint: l.networkFailActionHint,
        value: s.heartbeat.failAction.name.toUpperCase(),
        locked: locked,
        onTap: () => _showEnumPicker<HeartbeatFailAction>(
          context,
          title: 'heartbeat // action',
          values: HeartbeatFailAction.values,
          current: s.heartbeat.failAction,
          labelOf: (v) => v.name.toUpperCase(),
          onPick: (v) => _set(SettingFields.heartbeatFailAction, v),
        ),
      ),
      if (s.heartbeat.failAction == HeartbeatFailAction.switchConfig)
        _PickerRow(
          t: t,
          title: l.networkSwitchSource,
          hint: l.networkSwitchSourceHint,
          value: s.heartbeat.switchSource.name.toUpperCase(),
          locked: locked,
          onTap: () => _showEnumPicker<SwitchSource>(
            context,
            title: 'heartbeat // source',
            values: SwitchSource.values,
            current: s.heartbeat.switchSource,
            labelOf: (v) => v.name.toUpperCase(),
            onPick: (v) => _set(SettingFields.heartbeatSwitchSource, v),
          ),
        ),
    ];
  }
}
