part of 'configs_screen.dart';

class _PinnedGroup extends StatelessWidget {
  final TeapodTokens t;
  final List<(PinnedRef, VpnConfig?)> pins;
  final String? activeConfigId;
  final void Function(VpnConfig) onSelectConfig;
  final void Function(VpnConfig) onConfigMenu;
  final void Function(PinnedRef) onUnpin;

  const _PinnedGroup({
    super.key,
    required this.t,
    required this.pins,
    required this.activeConfigId,
    required this.onSelectConfig,
    required this.onConfigMenu,
    required this.onUnpin,
  });

  void _showLostMenu(BuildContext context, PinnedRef pin) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pin.name,
                      style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
                    ),
                  ),
                  Text(context.l10n.configsNotInSub, style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(
              t: t,
              label: context.l10n.configsUnpin,
              color: t.danger,
              onTap: () {
                Navigator.pop(ctx);
                onUnpin(pin);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('[★]', style: AppTheme.mono(size: 10, color: t.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[pinned]',
                      style: AppTheme.sans(size: 13, weight: FontWeight.w500, color: t.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'cnt=${pins.length} · ${context.l10n.configsPinned}',
                      style: AppTheme.mono(size: 10, color: t.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          color: t.bgSunken,
          child: Column(
            children: [
              for (var i = 0; i < pins.length; i++)
                if (pins[i].$2 != null)
                  _ConfigRow(
                    key: ValueKey('pin_${pins[i].$1.subscriptionId}_${pins[i].$1.name}'),
                    t: t,
                    config: pins[i].$2!,
                    addr: i + 1,
                    isActive: pins[i].$2!.id == activeConfigId,
                    pinned: true,
                    onTap: () => onSelectConfig(pins[i].$2!),
                    onLongPress: () => onConfigMenu(pins[i].$2!),
                  )
                else
                  _LostPinRow(
                    key: ValueKey('lost_${pins[i].$1.subscriptionId}_${pins[i].$1.name}'),
                    t: t,
                    pin: pins[i].$1,
                    addr: i + 1,
                    onTap: () => _showLostMenu(context, pins[i].$1),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LostPinRow extends StatelessWidget {
  final TeapodTokens t;
  final PinnedRef pin;
  final int addr;
  final VoidCallback onTap;

  const _LostPinRow({super.key, required this.t, required this.pin, required this.addr, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      onLongPress: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(hexAddr, style: AppTheme.mono(size: 10, color: t.textMuted)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(border: Border.all(color: t.lineSoft)),
                constraints: const BoxConstraints(minWidth: 44),
                child: Text(
                  'LOST',
                  textAlign: TextAlign.center,
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pin.name,
                      style: AppTheme.sans(size: 13, weight: FontWeight.w500, color: t.textMuted, letterSpacing: -0.2),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.configsPinUnavailable,
                      style: AppTheme.mono(size: 10, color: t.textMuted),
                      overflow: TextOverflow.ellipsis,
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

// ── Shared helpers ────────────────────────────────────────────────
