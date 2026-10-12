import 'package:flutter/material.dart';
import '../../core/models/vpn_config.dart';
import '../theme/app_colors.dart';

class ConfigCard extends StatelessWidget {
  final VpnConfig config;
  final bool isActive;
  final bool isConnected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ConfigCard({
    super.key,
    required this.config,
    this.isActive = false,
    this.isConnected = false,
    this.onTap,
    this.onLongPress,
  });

  Color get _protocolColor => switch (config.protocol) {
        VpnProtocol.vless => AppColors.protoVless,
        VpnProtocol.vmess => AppColors.protoVmess,
        VpnProtocol.trojan => AppColors.protoTrojan,
        VpnProtocol.shadowsocks => AppColors.protoShadowsocks,
        VpnProtocol.hysteria2 => AppColors.protoHysteria2,
      };

  String get _protocolLabel => switch (config.protocol) {
        VpnProtocol.vless => 'VLESS',
        VpnProtocol.vmess => 'VMess',
        VpnProtocol.trojan => 'Trojan',
        VpnProtocol.shadowsocks => 'SS',
        VpnProtocol.hysteria2 => 'HY2',
      };

  String get _securityLabel => switch (config.security) {
        VpnSecurity.tls => 'TLS',
        VpnSecurity.reality => 'Reality',
        VpnSecurity.none => 'None',
      };

  String get _transportLabel => switch (config.transport) {
        VpnTransport.ws => 'WS',
        VpnTransport.grpc => 'gRPC',
        VpnTransport.http2 => 'H2',
        VpnTransport.quic => 'QUIC',
        VpnTransport.tcp => 'TCP',
        VpnTransport.xhttp => 'XHTTP',
        VpnTransport.httpupgrade => 'HTTPUpgrade',
        VpnTransport.splithttp => 'SplitHTTP',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryDim.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Protocol badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _protocolColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _protocolColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _protocolLabel,
                  style: TextStyle(
                    color: _protocolColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            config.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (config.latencyMs != null) ...[
                          const SizedBox(width: 8),
                          _LatencyBadge(config.latencyMs!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${config.address}:${config.port}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Tag(_securityLabel),
                        const SizedBox(width: 4),
                        _Tag(_transportLabel),
                      ],
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  final int ms;
  const _LatencyBadge(this.ms);

  Color get _color {
    if (ms < 0) return AppColors.error;
    if (ms < 100) return AppColors.connected;
    if (ms < 300) return AppColors.connecting;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      ms < 0 ? 'н/д' : '${ms}ms',
      style: TextStyle(
        color: _color,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
