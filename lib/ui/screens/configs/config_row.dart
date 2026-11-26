part of 'configs_screen.dart';

class _ConfigRow extends StatelessWidget {
  final TeapodTokens t;
  final VpnConfig config;
  final int addr;
  final bool isActive;
  final bool indent;
  final bool pinned;

  /// In sort mode — the index for the ≡ handle; otherwise "⋮" is shown.
  final int? draggableIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConfigRow({
    super.key,
    required this.t,
    required this.config,
    required this.addr,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
    this.indent = false,
    this.pinned = false,
    this.draggableIndex,
  });

  String get _protoTag => config.protoTag;

  @override
  Widget build(BuildContext context) => CoreSupportGate(config: config, child: _buildRow(context));

  Widget _buildRow(BuildContext context) {
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';
    final ping = config.latencyMs;
    final tagColor = isActive ? t.accent : t.textDim;
    final tagBorder = isActive ? t.accent : t.line;
    final leftPad = indent ? 52.0 : 20.0;
    final isDraggable = draggableIndex != null;

    final trailing = isDraggable
        ? ReorderableDragStartListener(
            index: draggableIndex!,
            child: SizedBox(width: 36, height: 40, child: Icon(Icons.drag_handle_rounded, size: 18, color: t.accent)),
          )
        : Semantics(
            label: context.l10n.configsConfigMenu,
            button: true,
            child: GestureDetector(
              onTap: onLongPress,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(width: 36, height: 40, child: Icon(Icons.more_vert, size: 16, color: t.textMuted)),
            ),
          );

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? t.accentFade : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Stack(
          children: [
            if (isActive) Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 2, color: t.accent)),
            Padding(
              padding: EdgeInsets.fromLTRB(leftPad, 6, 10, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(hexAddr, style: AppTheme.mono(size: 10, color: t.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(border: Border.all(color: tagBorder)),
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(
                      _protoTag,
                      textAlign: TextAlign.center,
                      style: AppTheme.mono(size: 10, color: tagColor, letterSpacing: 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.name,
                          style: AppTheme.sans(size: 13, weight: FontWeight.w500, color: t.text, letterSpacing: -0.2),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Consumer(
                          builder: (_, ref, _) {
                            // Core — only if the profile landed on a non-primary one.
                            final core = coreNote(ref, config);
                            return Text(
                              '${config.address}:${config.port}${core == null ? '' : ' · $core'}',
                              style: AppTheme.mono(size: 10, color: t.textMuted),
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (pinned) ...[Text('★', style: AppTheme.mono(size: 10, color: t.accent)), const SizedBox(width: 6)],
                  if (ping != null) Text('${ping}ms', style: AppTheme.mono(size: 11, color: t.accent)),
                  trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pinned group ──────────────────────────────────────────────────
