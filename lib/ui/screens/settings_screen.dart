import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/update_provider.dart';
import '../../core/models/dns_config.dart';
import '../../core/services/settings_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vpn_provider.dart';
import '../theme/app_colors.dart';
import 'split_tunnel_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';
  String _xrayVersion = '';
  String _tun2socksVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadBinaryVersions();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'v${info.version}');
      }
    } catch (_) {
      if (mounted) setState(() => _version = 'v1.0.0');
    }
  }

  Future<void> _loadBinaryVersions() async {
    try {
      const channel = MethodChannel('com.teapodstream/vpn');
      final result = await channel.invokeMethod<Map>('getBinaryVersions');
      if (result != null && mounted) {
        setState(() {
          _xrayVersion = result['xray'] ?? '—';
          _tun2socksVersion = result['tun2socks'] ?? '—';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _xrayVersion = '—';
          _tun2socksVersion = '—';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final vpnState = ref.watch(vpnProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (settings) => _SettingsBody(
          settings: settings,
          isConnected: vpnState.isConnected,
          version: _version,
          xrayVersion: _xrayVersion,
          tun2socksVersion: _tun2socksVersion,
          onUpdate: (s) => ref.read(settingsProvider.notifier).save(s),
        ),
      ),
    );
  }
}

class _SettingsBody extends StatefulWidget {
  final AppSettings settings;
  final bool isConnected;
  final String version;
  final String xrayVersion;
  final String tun2socksVersion;
  final void Function(AppSettings) onUpdate;

  const _SettingsBody({
    required this.settings,
    required this.isConnected,
    required this.version,
    required this.xrayVersion,
    required this.tun2socksVersion,
    required this.onUpdate,
  });

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  late final TextEditingController _socksPortCtrl;
  late final TextEditingController _socksUserCtrl;
  late final TextEditingController _socksPasswordCtrl;

  @override
  void initState() {
    super.initState();
    _socksPortCtrl =
        TextEditingController(text: widget.settings.socksPort.toString());
    _socksUserCtrl =
        TextEditingController(text: widget.settings.socksUser);
    _socksPasswordCtrl =
        TextEditingController(text: widget.settings.socksPassword);
  }

  @override
  void dispose() {
    _socksPortCtrl.dispose();
    _socksUserCtrl.dispose();
    _socksPasswordCtrl.dispose();
    super.dispose();
  }

  void _updatePorts() {
    final socks = int.tryParse(_socksPortCtrl.text);
    if (socks != null) {
      widget.onUpdate(widget.settings.copyWith(
        socksPort: socks.clamp(1024, 65535),
      ));
    }
  }

  void _updateCredentials() {
    widget.onUpdate(widget.settings.copyWith(
      socksUser: _socksUserCtrl.text,
      socksPassword: _socksPasswordCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Connection section
        _SectionHeader('Подключение'),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            SwitchListTile(
              title: const Text(
                'Автоподключение',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Подключаться при запуске приложения',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.autoConnect,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(autoConnect: v)),
            ),
            const _Divider(),
            SwitchListTile(
              title: const Text(
                'Уведомление',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Показывать скорость и кнопку отключения в шторке',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.showNotification,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(showNotification: v)),
            ),
          ],
        ),
        if (widget.isConnected) ...[
          const SizedBox(height: 6),
          const _DisabledNote('Настройки нельзя изменить во время подключения'),
        ],

        const SizedBox(height: 20),

        // Xray section
        _SectionHeader('Xray'),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            SwitchListTile(
              title: const Text(
                'Случайный порт',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Случайный SOCKS порт при каждом подключении',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.randomPort,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(randomPort: v)),
            ),
            if (!widget.settings.randomPort) ...[
              const _Divider(),
              _PortField(
                label: 'SOCKS5 порт',
                hint: '10808',
                controller: _socksPortCtrl,
                enabled: !widget.isConnected,
                onChanged: (_) => _updatePorts(),
              ),
            ],
            const _Divider(),
            SwitchListTile(
              title: const Text(
                'Случайные учётные данные',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Генерировать случайный логин/пароль SOCKS',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.randomCredentials,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(randomCredentials: v)),
            ),
            if (!widget.settings.randomCredentials) ...[
              const _Divider(),
              _TextField(
                label: 'Логин SOCKS',
                hint: 'Оставьте пустым для работы без пароля',
                controller: _socksUserCtrl,
                enabled: !widget.isConnected,
                onChanged: (_) => _updateCredentials(),
              ),
              const _Divider(),
              _TextField(
                label: 'Пароль SOCKS',
                hint: 'Оставьте пустым для работы без пароля',
                controller: _socksPasswordCtrl,
                enabled: !widget.isConnected,
                obscureText: true,
                onChanged: (_) => _updateCredentials(),
              ),
            ],
            const _Divider(),
            SwitchListTile(
              title: const Text(
                'Только прокси',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Запустить SOCKS прокси без VPN-туннеля',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.proxyOnly,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(proxyOnly: v)),
            ),
            const _Divider(),
            SwitchListTile(
              title: const Text(
                'UDP',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Разрешить UDP-трафик через SOCKS',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.enableUdp,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(enableUdp: v)),
            ),
            const _Divider(),
            ListTile(
              title: const Text(
                'Режим DNS',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: Text(
                widget.settings.dnsMode == DnsMode.proxy
                    ? 'DNS запросы через VPN-туннель'
                    : 'DNS запросы напрямую',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              trailing: DropdownButton<DnsMode>(
                value: widget.settings.dnsMode,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary),
                underline: const SizedBox(),
                items: DnsMode.values.map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(m == DnsMode.proxy ? 'Через VPN' : 'Напрямую',
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: widget.isConnected
                    ? null
                    : (v) => v != null
                        ? widget.onUpdate(widget.settings.copyWith(dnsMode: v))
                        : null,
              ),
            ),
            const _Divider(),
            ListTile(
              title: const Text(
                'DNS сервер',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: Text(
                _dnsLabel(widget.settings),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              onTap: widget.isConnected
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const _DnsSettingsScreen()),
                      ),
            ),
          ],
        ),
        if (widget.isConnected) ...[
          const SizedBox(height: 6),
          const _DisabledNote('Настройки Xray нельзя изменить во время подключения'),
        ],

        const SizedBox(height: 20),

        // Split tunneling
        _SectionHeader('Сплит-туннелирование'),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            SwitchListTile(
              title: const Text(
                'Включить сплит-туннелирование',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
              subtitle: const Text(
                'Выберите приложения, трафик которых НЕ будет проходить через VPN',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              value: widget.settings.splitTunnelingEnabled,
              onChanged: widget.isConnected
                  ? null
                  : (v) => widget.onUpdate(
                      widget.settings.copyWith(splitTunnelingEnabled: v)),
            ),
            if (widget.settings.splitTunnelingEnabled) ...[
              const _Divider(),
              ListTile(
                title: const Text(
                  'Выбрать приложения',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                ),
                subtitle: Text(
                  widget.settings.vpnMode == VpnMode.onlySelected
                      ? '${widget.settings.includedPackages.length} приложений выбрано'
                      : '${widget.settings.excludedPackages.length} приложений исключено',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
                enabled: !widget.isConnected,
                onTap: widget.isConnected
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SplitTunnelScreen(),
                          ),
                        ),
              ),
            ],
          ],
        ),
        if (widget.isConnected && widget.settings.splitTunnelingEnabled) ...[
          const SizedBox(height: 6),
          const _DisabledNote(
              'Сплит-туннелирование нельзя изменить во время подключения'),
        ],

        const SizedBox(height: 20),

        // Info section
        _SectionHeader('О приложении'),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            ListTile(
              title: const Text(
                'TeapodStream',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                'VPN клиент с поддержкой xray',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              trailing: Text(
                widget.version.isEmpty ? '...' : widget.version,
                style: const TextStyle(color: AppColors.textDisabled),
              ),
            ),
            const _Divider(),
            _LinkRow(icon: Icons.code_rounded, label: 'Исходный код', url: 'https://github.com/Wendor/teapod-stream'),
            const _Divider(),
            _ComponentRow(
              icon: Icons.shield_rounded,
              label: 'Xray Core',
              version: widget.xrayVersion.isEmpty ? '...' : widget.xrayVersion,
              license: 'MIT License',
              url: 'https://github.com/XTLS/Xray-core',
            ),
            _ComponentRow(
              icon: Icons.shuffle_rounded,
              label: 'teapod-tun2socks',
              version: widget.tun2socksVersion.isEmpty ? '...' : widget.tun2socksVersion,
              license: 'MIT License',
              url: 'https://github.com/Wendor/teapod-tun2socks',
            ),
            const _Divider(),
            const _UpdateTile(),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: AppColors.border,
    );
  }
}

class _PortField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final void Function(String) onChanged;

  const _PortField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:
                    enabled ? AppColors.textPrimary : AppColors.textDisabled,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final void Function(String) onChanged;

  const _TextField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              enabled: enabled,
              obscureText: obscureText,
              textAlign: TextAlign.end,
              onChanged: onChanged,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisabledNote extends StatelessWidget {
  final String text;
  const _DisabledNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.connecting, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.connecting,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String version;
  final String license;
  final String url;
  const _ComponentRow({
    required this.icon,
    required this.label,
    required this.version,
    required this.license,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: InkWell(
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryDim.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
      ),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(
        license,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
      trailing: Text(
        version,
        style: const TextStyle(
          color: AppColors.textDisabled,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _LinkRow({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.textDisabled, size: 18),
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}

class _UpdateTile extends ConsumerWidget {
  const _UpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    return switch (updateState) {
      UpdateIdle() => ListTile(
          title: const Text('Обновления',
              style: TextStyle(color: AppColors.textPrimary)),
          trailing: TextButton(
            onPressed: () =>
                ref.read(updateProvider.notifier).checkForUpdate(),
            child: const Text('Проверить'),
          ),
        ),
      UpdateChecking() => const ListTile(
          title: Text('Проверка...',
              style: TextStyle(color: AppColors.textSecondary)),
          trailing: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      UpdateUpToDate() => const ListTile(
          title: Text('Обновлений нет',
              style: TextStyle(color: AppColors.textSecondary)),
          trailing:
              Icon(Icons.check_circle_outline, color: AppColors.connected),
        ),
      UpdateAvailable(:final info, :final resumableBytes) => ListTile(
          title: Text('Доступна v${info.version}',
              style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: resumableBytes > 0
              ? Text(
                  'Продолжить (${(resumableBytes / 1024 / 1024).toStringAsFixed(1)} МБ)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                )
              : null,
          trailing: TextButton(
            onPressed: () =>
                ref.read(updateProvider.notifier).startDownload(info),
            child: Text(resumableBytes > 0 ? 'Продолжить' : 'Скачать'),
          ),
        ),
      UpdateDownloading(:final info, :final downloaded, :final total) =>
        ListTile(
          title: Text('Скачивается v${info.version}',
              style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: total > 0 ? downloaded / total : null,
                backgroundColor: AppColors.border,
                color: AppColors.primary,
              ),
              const SizedBox(height: 2),
              Text(
                total > 0
                    ? '${(downloaded / 1024 / 1024).toStringAsFixed(1)} / ${(total / 1024 / 1024).toStringAsFixed(1)} МБ'
                    : '${(downloaded / 1024 / 1024).toStringAsFixed(1)} МБ',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.cancel_outlined,
                color: AppColors.textSecondary),
            onPressed: () =>
                ref.read(updateProvider.notifier).cancelDownload(),
          ),
        ),
      UpdateDownloaded(:final info, :final filePath) => ListTile(
          title: Text('v${info.version} готова',
              style: const TextStyle(color: AppColors.textPrimary)),
          trailing: TextButton(
            onPressed: () =>
                ref.read(updateProvider.notifier).installApk(filePath),
            style: TextButton.styleFrom(foregroundColor: AppColors.connected),
            child: const Text('Установить'),
          ),
        ),
      UpdateError(:final message, :final retryInfo) => ListTile(
          title: Text(message,
              style:
                  const TextStyle(color: AppColors.error, fontSize: 13)),
          trailing: TextButton(
            onPressed: retryInfo != null
                ? () => ref
                    .read(updateProvider.notifier)
                    .startDownload(retryInfo)
                : () =>
                    ref.read(updateProvider.notifier).checkForUpdate(),
            child: const Text('Повтор'),
          ),
        ),
    };
  }
}

String _dnsLabel(AppSettings settings) {
  if (settings.dnsPreset == 'custom') {
    return settings.customDnsAddress;
  }
  return DnsServerConfig.presets.firstWhere(
    (p) => p['value'] == settings.dnsPreset,
    orElse: () => {'label': settings.dnsPreset},
  )['label'] ?? settings.dnsPreset;
}

class _DnsSettingsScreen extends ConsumerStatefulWidget {
  const _DnsSettingsScreen();

  @override
  ConsumerState<_DnsSettingsScreen> createState() => _DnsSettingsScreenState();
}

class _DnsSettingsScreenState extends ConsumerState<_DnsSettingsScreen> {
  late String _selectedPreset;
  late DnsType _customType;
  late TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings();
    _selectedPreset = s.dnsPreset;
    _customType = s.customDnsType == 'doh' ? DnsType.doh : s.customDnsType == 'dot' ? DnsType.dot : DnsType.udp;
    _customCtrl = TextEditingController(text: s.customDnsAddress);
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (s != null) {
      ref.read(settingsProvider.notifier).save(s.copyWith(
        dnsPreset: _selectedPreset,
        customDnsAddress: _customCtrl.text.trim().isEmpty ? '1.1.1.1' : _customCtrl.text.trim(),
        customDnsType: _customType.name,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = _selectedPreset == 'custom';

    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS сервер'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Выберите DNS сервер:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          ...DnsServerConfig.presets.map((p) {
            final val = p['value'] as String;
            final label = p['label'] as String;
            return RadioListTile<String>(
              title: Text(label, style: const TextStyle(fontSize: 14)),
              value: val,
              groupValue: _selectedPreset,
              onChanged: (v) => setState(() => _selectedPreset = v!),
            );
          }),
          if (isCustom) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Тип сервера:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButton<DnsType>(
                    value: _customType,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: DnsType.values.map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t == DnsType.udp ? 'UDP (порт 53)' : t == DnsType.doh ? 'DoH (HTTPS)' : 'DoT (TLS)',
                          style: const TextStyle(color: AppColors.textPrimary)),
                    )).toList(),
                    onChanged: (v) => setState(() => _customType = v!),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customCtrl,
                    decoration: InputDecoration(
                      hintText: _customType == DnsType.doh ? 'https://...' : 'IP-адрес',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
