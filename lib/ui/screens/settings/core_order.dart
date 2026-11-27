part of 'settings_screen.dart';

/// Cores in priority order: "↑" moves a core up, the switch excludes it
/// from selection. The last enabled core can't be turned off.
class _CoreOrderList extends ConsumerStatefulWidget {
  final TeapodTokens t;
  final AppSettings settings;
  final Map<String, String>? versions;
  final bool locked;

  /// A change to the settings current when it is written.
  final void Function(AppSettings Function(AppSettings current)) onUpdate;

  const _CoreOrderList({
    required this.t,
    required this.settings,
    required this.versions,
    required this.locked,
    required this.onUpdate,
  });

  @override
  ConsumerState<_CoreOrderList> createState() => _CoreOrderListState();
}

class _CoreOrderListState extends ConsumerState<_CoreOrderList> {
  /// The core just moved up is briefly highlighted, otherwise the reorder goes unnoticed.
  CoreKind? _moved;
  Timer? _movedTimer;

  @override
  void dispose() {
    _movedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TeapodTokens t = widget.t;
    final settings = widget.settings;
    final locked = widget.locked;
    final usable = ref.watch(coreResolverProvider).usable;
    final available = ref.watch(availableCoresProvider).value ?? CoreKind.values.toSet();
    final order = settings.coreOrder;

    void toggle(CoreKind k, bool on) {
      if (!on && usable.length == 1 && usable.first == k) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.settingsCoreLastEnabled)));
        return;
      }
      widget.onUpdate((c) {
        if (on) return c.copyWith(disabledCores: {...c.disabledCores}..remove(k));
        final disabled = {...c.disabledCores, k};
        // Checked again on the settings it writes to: taps queued before a rebuild must not disable every core.
        if (!c.coreOrder.any((o) => available.contains(o) && !disabled.contains(o))) return c;
        return c.copyWith(disabledCores: disabled);
      });
    }

    void moveUp(int i) {
      final k = order[i];
      // Moved within the order it writes to: taps queued before a rebuild each move from the previous result.
      widget.onUpdate((c) {
        final j = c.coreOrder.indexOf(k);
        if (j <= 0) return c;
        final next = [...c.coreOrder]..insert(j - 1, k);
        next.removeAt(j + 1);
        return c.copyWith(coreOrder: List.unmodifiable(next));
      });
      setState(() => _moved = k);
      _movedTimer?.cancel();
      _movedTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _moved = null);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.settingsCores, style: AppTheme.sans(size: 14, color: t.text)),
              const SizedBox(height: 3),
              Text(
                context.l10n.settingsCoresHint,
                style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
        for (final (i, k) in order.indexed)
          AnimatedContainer(
            key: ValueKey(k),
            duration: const Duration(milliseconds: 300),
            color: _moved == k ? t.accentFade : t.accentFade.withValues(alpha: 0),
            padding: const EdgeInsets.fromLTRB(4, 0, 20, 0),
            child: Row(
              children: [
                // Move the core one position up; the first one has no button.
                SizedBox(
                  width: kMinInteractiveDimension,
                  child: i == 0
                      ? null
                      : TapTarget(
                          label: context.l10n.settingsCoreMoveUp(k.displayName),
                          onTap: () => locked ? showReadonlySnack(context) : moveUp(i),
                          child: Icon(Icons.arrow_upward_rounded, size: 16, color: t.textMuted),
                        ),
                ),
                SizedBox(
                  width: 26,
                  child: Text('0${i + 1}', style: AppTheme.mono(size: 10, color: t.textMuted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.displayName,
                        style: AppTheme.sans(size: 14, color: usable.contains(k) ? t.text : t.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        !available.contains(k)
                            ? context.l10n.settingsCoreUnavailable
                            : (widget.versions?[k.versionKey] ?? '...'),
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                SetSquareSwitch(
                  t: t,
                  value: !settings.disabledCores.contains(k),
                  onChanged: locked ? null : (on) => toggle(k, on),
                ),
              ],
            ),
          ),
        Container(height: 1, color: t.lineSoft),
      ],
    );
  }
}

// ── Update channel segment ────────────────────────────────────────
