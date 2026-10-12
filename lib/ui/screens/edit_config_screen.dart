import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../protocols/xray/xray_config_builder.dart';
import '../../providers/config_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class EditConfigScreen extends ConsumerStatefulWidget {
  final VpnConfig config;

  const EditConfigScreen({super.key, required this.config});

  @override
  ConsumerState<EditConfigScreen> createState() => _EditConfigScreenState();
}

class _EditConfigScreenState extends ConsumerState<EditConfigScreen> {
  int _activeTab = 0; // 0 = Parameters, 1 = Raw JSON

  // Form controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _uuidCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _sniCtrl;
  late final TextEditingController _wsPathCtrl;
  late final TextEditingController _wsHostCtrl;
  late final TextEditingController _grpcServiceCtrl;
  late final TextEditingController _publicKeyCtrl;
  late final TextEditingController _shortIdCtrl;
  late final TextEditingController _spiderXCtrl;
  late final TextEditingController _flowCtrl;
  late final TextEditingController _obfsPasswordCtrl;
  late final TextEditingController _pinShaCtrl;
  late final TextEditingController _alpnCtrl;

  // Raw JSON editor controller
  late final TextEditingController _jsonCtrl;

  // Protocol & Enums (Protocol priority: VLESS, Hysteria2, Shadowsocks, VMess, Trojan)
  late VpnProtocol _protocol;
  late VpnSecurity _security;
  late VpnTransport _transport;
  late String _method;
  late String _fingerprint;
  late bool _allowInsecure;

  static const _supportedProtocols = [
    VpnProtocol.vless,
    VpnProtocol.hysteria2,
    VpnProtocol.shadowsocks,
    VpnProtocol.vmess,
    VpnProtocol.trojan,
  ];

  static const _ssMethods = [
    'chacha20-ietf-poly1305',
    'aes-128-gcm',
    'aes-256-gcm',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  ];

  static const _fingerprints = [
    'chrome',
    'firefox',
    'safari',
    'ios',
    'edge',
    'random',
    'randomized',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _nameCtrl = TextEditingController(text: c.name);
    _addressCtrl = TextEditingController(text: c.address);
    _portCtrl = TextEditingController(text: c.port.toString());
    _uuidCtrl = TextEditingController(text: c.uuid);
    _passwordCtrl = TextEditingController(text: c.password ?? '');
    _sniCtrl = TextEditingController(text: c.sni ?? '');
    _wsPathCtrl = TextEditingController(text: c.wsPath ?? '');
    _wsHostCtrl = TextEditingController(text: c.wsHost ?? '');
    _grpcServiceCtrl = TextEditingController(text: c.grpcServiceName ?? '');
    _publicKeyCtrl = TextEditingController(text: c.publicKey ?? '');
    _shortIdCtrl = TextEditingController(text: c.shortId ?? '');
    _spiderXCtrl = TextEditingController(text: c.spiderX ?? '');
    _flowCtrl = TextEditingController(text: c.flow ?? '');
    _obfsPasswordCtrl = TextEditingController(text: c.obfsPassword ?? '');
    _pinShaCtrl = TextEditingController(text: c.pinSHA256 ?? '');
    _alpnCtrl = TextEditingController(text: c.alpn ?? '');

    _protocol = c.protocol;
    _security = c.security;
    _transport = c.transport;
    _method = c.method ?? 'chacha20-ietf-poly1305';
    _fingerprint = c.fingerprint ?? 'chrome';
    _allowInsecure = c.allowInsecure;

    String jsonStr;
    if (c.rawXrayConfig != null && c.rawXrayConfig!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(c.rawXrayConfig!);
        jsonStr = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        jsonStr = c.rawXrayConfig!;
      }
    } else {
      try {
        const options = VpnEngineOptions(
          socksPort: 10808,
          httpPort: 10809,
          socksUser: '',
          socksPassword: '',
        );
        final map = XrayConfigBuilder.build(c, options);
        jsonStr = const JsonEncoder.withIndent('  ').convert(map);
      } catch (e) {
        jsonStr = '{\n  // Ошибка генерации: $e\n}';
      }
    }
    _jsonCtrl = TextEditingController(text: jsonStr);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _portCtrl.dispose();
    _uuidCtrl.dispose();
    _passwordCtrl.dispose();
    _sniCtrl.dispose();
    _wsPathCtrl.dispose();
    _wsHostCtrl.dispose();
    _grpcServiceCtrl.dispose();
    _publicKeyCtrl.dispose();
    _shortIdCtrl.dispose();
    _spiderXCtrl.dispose();
    _flowCtrl.dispose();
    _obfsPasswordCtrl.dispose();
    _pinShaCtrl.dispose();
    _alpnCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  VpnConfig _buildConfigFromForm() {
    final name = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : widget.config.name;
    final address = _addressCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? widget.config.port;

    return widget.config.copyWith(
      name: name,
      protocol: _protocol,
      address: address,
      port: port,
      uuid: _uuidCtrl.text.trim(),
      password: _passwordCtrl.text.trim().isNotEmpty ? _passwordCtrl.text.trim() : null,
      security: _security,
      transport: _transport,
      sni: _sniCtrl.text.trim().isNotEmpty ? _sniCtrl.text.trim() : null,
      wsPath: _wsPathCtrl.text.trim().isNotEmpty ? _wsPathCtrl.text.trim() : null,
      wsHost: _wsHostCtrl.text.trim().isNotEmpty ? _wsHostCtrl.text.trim() : null,
      grpcServiceName: _grpcServiceCtrl.text.trim().isNotEmpty ? _grpcServiceCtrl.text.trim() : null,
      fingerprint: _fingerprint,
      publicKey: _publicKeyCtrl.text.trim().isNotEmpty ? _publicKeyCtrl.text.trim() : null,
      shortId: _shortIdCtrl.text.trim().isNotEmpty ? _shortIdCtrl.text.trim() : null,
      spiderX: _spiderXCtrl.text.trim().isNotEmpty ? _spiderXCtrl.text.trim() : null,
      flow: _flowCtrl.text.trim().isNotEmpty ? _flowCtrl.text.trim() : null,
      method: _protocol == VpnProtocol.shadowsocks ? _method : null,
      obfsPassword: _obfsPasswordCtrl.text.trim().isNotEmpty ? _obfsPasswordCtrl.text.trim() : null,
      pinSHA256: _pinShaCtrl.text.trim().isNotEmpty ? _pinShaCtrl.text.trim() : null,
      alpn: _alpnCtrl.text.trim().isNotEmpty ? _alpnCtrl.text.trim() : null,
      allowInsecure: _allowInsecure,
      rawUri: null,
    );
  }

  void _syncFormToJson() {
    final temp = _buildConfigFromForm();
    try {
      const options = VpnEngineOptions(
        socksPort: 10808,
        httpPort: 10809,
        socksUser: '',
        socksPassword: '',
      );
      final map = XrayConfigBuilder.build(temp, options);
      _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(map);
    } catch (_) {}
  }

  Future<void> _onSave() async {
    if (_activeTab == 1) {
      // Save from Raw JSON mode
      final text = _jsonCtrl.text.trim();
      if (text.isEmpty) {
        _showError('Конфигурация не может быть пустой');
        return;
      }

      try {
        final decoded = jsonDecode(text);
        final jsonFormatted = const JsonEncoder.withIndent('  ').convert(decoded);
        final name = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : widget.config.name;

        String? extractedAddress;
        int? extractedPort;
        if (decoded is Map<String, dynamic> && decoded['outbounds'] is List) {
          for (final ob in decoded['outbounds']) {
            if (ob is Map<String, dynamic> && ob['tag'] == 'proxy') {
              final settings = ob['settings'];
              if (settings is Map<String, dynamic> && settings['servers'] is List) {
                final srv = (settings['servers'] as List).firstOrNull;
                if (srv is Map<String, dynamic>) {
                  extractedAddress = srv['address']?.toString();
                  extractedPort = int.tryParse(srv['port']?.toString() ?? '');
                }
              } else if (settings is Map<String, dynamic> && settings['vnext'] is List) {
                final vn = (settings['vnext'] as List).firstOrNull;
                if (vn is Map<String, dynamic>) {
                  extractedAddress = vn['address']?.toString();
                  extractedPort = int.tryParse(vn['port']?.toString() ?? '');
                }
              }
              break;
            }
          }
        }

        final updated = widget.config.copyWith(
          name: name,
          rawXrayConfig: jsonFormatted,
          address: extractedAddress ?? widget.config.address,
          port: extractedPort ?? widget.config.port,
        );

        await ref.read(configProvider.notifier).updateConfig(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Конфигурация сохранена')),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        _showError('Некорректный JSON: $e');
      }
      return;
    }

    // Save from Parameters Form mode
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 0;

    if (name.isEmpty) {
      _showError('Введите имя конфигурации');
      return;
    }
    if (address.isEmpty) {
      _showError('Введите адрес сервера');
      return;
    }
    if (port <= 0 || port > 65535) {
      _showError('Неверный порт: 1–65535');
      return;
    }

    final updated = _buildConfigFromForm();

    // Generate updated rawXrayConfig so engine runs with latest parameters
    String? jsonFormatted;
    try {
      const options = VpnEngineOptions(
        socksPort: 10808,
        httpPort: 10809,
        socksUser: '',
        socksPassword: '',
      );
      final map = XrayConfigBuilder.build(updated, options);
      jsonFormatted = const JsonEncoder.withIndent('  ').convert(map);
    } catch (_) {}

    final finalConfig = updated.copyWith(
      rawXrayConfig: jsonFormatted ?? updated.rawXrayConfig,
    );

    await ref.read(configProvider.notifier).updateConfig(finalConfig);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Конфигурация сохранена')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text('Конфигурация "${widget.config.name}" будет удалена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(configProvider.notifier).removeConfig(widget.config.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _showError(String message) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTheme.mono(size: 11, color: t.danger)),
        backgroundColor: t.bgElev,
        shape: Border(top: BorderSide(color: t.danger, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'CUSTOM',
          style: AppTheme.mono(size: 16, weight: FontWeight.w600, color: t.text, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: t.danger),
            tooltip: 'Удалить',
            onPressed: _onDelete,
          ),
          IconButton(
            icon: Icon(Icons.check, color: t.accent),
            tooltip: 'Сохранить',
            onPressed: _onSave,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: t.line, height: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Outlined "Название" TextField
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _nameCtrl,
                style: AppTheme.sans(size: 14, color: t.text),
                decoration: InputDecoration(
                  labelText: 'Название',
                  labelStyle: AppTheme.sans(size: 13, color: t.textDim),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: t.line),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: t.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),

            // Tab bar: ПАРАМЕТРЫ vs ИСХОДНЫЙ КОД (JSON)
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(
                children: [
                  Expanded(
                    child: _TabButton(
                      t: t,
                      label: 'ПАРАМЕТРЫ',
                      active: _activeTab == 0,
                      onTap: () {
                        setState(() {
                          _activeTab = 0;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _TabButton(
                      t: t,
                      label: 'ИСХОДНЫЙ КОД (JSON)',
                      active: _activeTab == 1,
                      onTap: () {
                        _syncFormToJson();
                        setState(() {
                          _activeTab = 1;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Tab content
            Expanded(
              child: _activeTab == 0 ? _buildFormTab(t) : _buildJsonTab(t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormTab(TeapodTokens t) {
    final isVlessOrVmess = _protocol == VpnProtocol.vless || _protocol == VpnProtocol.vmess;
    final isPasswordAuth = _protocol == VpnProtocol.trojan ||
        _protocol == VpnProtocol.hysteria2 ||
        _protocol == VpnProtocol.shadowsocks;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(t, '0x01 // ПРОТОКОЛ'),
        _buildProtocolSelector(t),
        const SizedBox(height: 16),

        _buildSectionHeader(t, '0x02 // СЕРВЕР И ПОРТ'),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(t,
                  label: 'АДРЕС СЕРВЕРА', controller: _addressCtrl, hint: 'domain.com / IP'),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 1,
              child: _buildTextField(t,
                  label: 'ПОРТ',
                  controller: _portCtrl,
                  hint: '443',
                  keyboardType: TextInputType.number),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildSectionHeader(t, '0x03 // АВТОРИЗАЦИЯ'),
        if (isVlessOrVmess)
          _buildTextField(t, label: 'UUID', controller: _uuidCtrl, hint: 'XXXXXXXX-XXXX-XXXX...'),
        if (isPasswordAuth)
          _buildTextField(t,
              label: 'ПАРОЛЬ (PASSWORD)', controller: _passwordCtrl, hint: 'Password / Secret'),
        if (_protocol == VpnProtocol.shadowsocks) ...[
          const SizedBox(height: 10),
          _buildDropdownField<String>(
            t,
            label: 'МЕТОД ШИФРОВАНИЯ (CIPHER)',
            value: _method,
            items: _ssMethods,
            onChanged: (v) => setState(() => _method = v!),
          ),
        ],
        const SizedBox(height: 16),

        _buildSectionHeader(t, '0x04 // СЕТЬ И ТРАНСПОРТ'),
        _buildDropdownField<VpnTransport>(
          t,
          label: 'ТИП ТРАНСПОРТА',
          value: _transport,
          items: VpnTransport.values,
          itemLabel: (v) => v.name.toUpperCase(),
          onChanged: (v) => setState(() => _transport = v!),
        ),
        if (_transport == VpnTransport.ws ||
            _transport == VpnTransport.httpupgrade ||
            _transport == VpnTransport.splithttp) ...[
          const SizedBox(height: 10),
          _buildTextField(t, label: 'WS / HTTP PATH', controller: _wsPathCtrl, hint: '/path'),
          const SizedBox(height: 10),
          _buildTextField(t, label: 'WS HOST', controller: _wsHostCtrl, hint: 'host.domain.com'),
        ],
        if (_transport == VpnTransport.grpc) ...[
          const SizedBox(height: 10),
          _buildTextField(t,
              label: 'gRPC SERVICE NAME', controller: _grpcServiceCtrl, hint: 'serviceName'),
        ],
        const SizedBox(height: 16),

        _buildSectionHeader(t, '0x05 // БЕЗОПАСНОСТЬ (SECURITY)'),
        _buildDropdownField<VpnSecurity>(
          t,
          label: 'РЕЖИМ БЕЗОПАСНОСТИ',
          value: _security,
          items: VpnSecurity.values,
          itemLabel: (v) => v.name.toUpperCase(),
          onChanged: (v) => setState(() => _security = v!),
        ),
        if (_security != VpnSecurity.none) ...[
          const SizedBox(height: 10),
          _buildTextField(t, label: 'SNI / SERVER NAME', controller: _sniCtrl, hint: 'domain.com'),
          const SizedBox(height: 10),
          _buildDropdownField<String>(
            t,
            label: 'FINGERPRINT (uTLS)',
            value: _fingerprint,
            items: _fingerprints,
            onChanged: (v) => setState(() => _fingerprint = v!),
          ),
          const SizedBox(height: 10),
          _buildTextField(t, label: 'ALPN', controller: _alpnCtrl, hint: 'h2,http/1.1'),
        ],
        if (_security == VpnSecurity.reality) ...[
          const SizedBox(height: 10),
          _buildTextField(t,
              label: 'PUBLIC KEY (pbk)', controller: _publicKeyCtrl, hint: 'Public Key'),
          const SizedBox(height: 10),
          _buildTextField(t, label: 'SHORT ID (sid)', controller: _shortIdCtrl, hint: 'Short ID'),
          const SizedBox(height: 10),
          _buildTextField(t, label: 'SPIDER X (spx)', controller: _spiderXCtrl, hint: '/path'),
        ],
        if (_protocol == VpnProtocol.vless && _security != VpnSecurity.none) ...[
          const SizedBox(height: 10),
          _buildTextField(t,
              label: 'FLOW', controller: _flowCtrl, hint: 'xtls-rprx-vision / пусто'),
        ],
        if (_protocol == VpnProtocol.hysteria2) ...[
          const SizedBox(height: 10),
          _buildTextField(t,
              label: 'OBFS PASSWORD (SALAMANDER)',
              controller: _obfsPasswordCtrl,
              hint: 'Obfuscation password'),
          const SizedBox(height: 10),
          _buildTextField(t,
              label: 'PIN SHA-256', controller: _pinShaCtrl, hint: 'Certificate SHA-256 Pin'),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Разрешить небезопасный TLS (Insecure)',
                style: AppTheme.mono(size: 11, color: t.textDim)),
            Switch(
              value: _allowInsecure,
              activeTrackColor: t.accent.withAlpha(160),
              activeThumbColor: t.accent,
              onChanged: (v) => setState(() => _allowInsecure = v),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // Pure JSON Code Editor tab without line number gutter column
  Widget _buildJsonTab(TeapodTokens t) {
    return Container(
      color: t.bg,
      child: TextField(
        controller: _jsonCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: AppTheme.mono(size: 12, color: t.text, height: 1.4),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '{\n  "outbounds": [...]\n}',
          hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
          contentPadding: const EdgeInsets.all(16),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(TeapodTokens t, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
    );
  }

  Widget _buildProtocolSelector(TeapodTokens t) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _supportedProtocols.map((p) {
        final active = _protocol == p;
        return GestureDetector(
          onTap: () => setState(() => _protocol = p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? t.accent : t.bgElev,
              border: Border.all(color: active ? t.accent : t.line),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              p.name.toUpperCase(),
              style: AppTheme.mono(
                size: 10,
                color: active ? t.bg : t.text,
                weight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(
    TeapodTokens t, {
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.mono(size: 9, color: t.textDim, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: AppTheme.mono(size: 12, color: t.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppTheme.mono(size: 11, color: t.textMuted),
            filled: true,
            fillColor: t.bgElev,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.line),
              borderRadius: BorderRadius.circular(2),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>(
    TeapodTokens t, {
    required String label,
    required T value,
    required List<T> items,
    String Function(T)? itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.mono(size: 9, color: t.textDim, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: t.bgElev,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: t.bgElev,
              style: AppTheme.mono(size: 12, color: t.text),
              items: items.map((item) {
                final text = itemLabel != null ? itemLabel(item) : item.toString();
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(text, style: AppTheme.mono(size: 12, color: t.text)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.t,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? t.bgElev : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: active ? t.accent : Colors.transparent, width: 2),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.mono(
            size: 10,
            color: active ? t.accent : t.textDim,
            weight: active ? FontWeight.w600 : FontWeight.normal,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
