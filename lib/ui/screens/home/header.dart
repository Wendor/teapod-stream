part of 'home_screen.dart';

class _HeaderStrip extends StatelessWidget {
  final TeapodTokens t;
  final String version;
  const _HeaderStrip({required this.t, required this.version});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // The caption gives way: the 48 dp logs target keeps its width on a narrow screen.
          Flexible(
            child: Text(
              'teapod.stream // $version',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
            ),
          ),
          const SizedBox(width: 12),
          TapTarget(
            label: context.l10n.homeLogs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const LogsScreen(breadcrumbParent: 'home')),
            ),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: t.line)),
              child: Icon(Icons.receipt_long_outlined, size: 14, color: t.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero panel ────────────────────────────────────────────────────

class _HeroPanel extends StatelessWidget {
  final TeapodTokens t;
  final VpnStatus vpnState;
  final String protoLabel;
  final Duration connectedFor;
  final bool canToggle;
  final String disabledLabel;
  final VoidCallback onToggle;
  final VoidCallback onDisabledTap;
  final Widget? coreLine;

  const _HeroPanel({
    required this.t,
    required this.vpnState,
    required this.protoLabel,
    required this.connectedFor,
    required this.canToggle,
    required this.disabledLabel,
    required this.onToggle,
    required this.onDisabledTap,
    this.coreLine,
  });

  @override
  Widget build(BuildContext context) {
    final isConn = vpnState.isConnected;
    final isBusy = vpnState.isBusy;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line, width: 1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _CornerTicks(t: t),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              children: [
                Text(
                  context.l10n.homeTunnel(protoLabel),
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5),
                ),
                const SizedBox(height: 20),
                _PowerCore(
                  t: t,
                  isConnected: isConn,
                  isBusy: isBusy,
                  isBlocked: vpnState.isBlocked,
                  enabled: canToggle,
                  disabledLabel: disabledLabel,
                  onTap: canToggle ? onToggle : onDisabledTap,
                ),
                const SizedBox(height: 16),
                _StateInfo(t: t, vpnState: vpnState, connectedFor: connectedFor),
                ?coreLine,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── State info ────────────────────────────────────────────────────

class _StateInfo extends ConsumerWidget {
  final TeapodTokens t;
  final VpnStatus vpnState;
  final Duration connectedFor;

  const _StateInfo({required this.t, required this.vpnState, required this.connectedFor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConn = vpnState.isConnected;
    final isConnecting = vpnState.isConnecting;
    final isDisconnecting = vpnState.isDisconnecting;
    final isBlocked = vpnState.isBlocked;
    final isError = vpnState.isError;
    final l = context.l10n;
    final error = vpnState.error?.localize(l);
    final ipAsync = ref.watch(ipInfoProvider);
    final hasConfig = ref.watch(effectiveConfigProvider) != null;

    final stateWord = isBlocked
        ? l.homeStateBlocked
        : isConn
        ? l.homeStateConnected
        : isError
        ? l.homeStateFailed
        : (isConnecting ? l.homeStateConnecting : (isDisconnecting ? l.homeStateDisconnecting : l.homeStateOff));
    final stateColor = isBlocked || isError ? t.danger : (isConn ? t.accent : t.textDim);

    String subtitle;
    if (isBlocked) {
      subtitle = '${l.homeKillSwitchBlocked}${error != null ? '\n$error' : ''}';
    } else if (isError) {
      subtitle = [?error, l.homeTapToRetry].join('\n');
    } else if (isConn) {
      // Loading: placeholders; the chain gave up: say so; no country from the service: the IP alone.
      final ipText = switch (ipAsync) {
        AsyncData(value: final info?) => [?info.countryCode?.toLowerCase(), info.ip].join(' · '),
        AsyncData() || AsyncError() => l.homeIpUnknown,
        _ => '— · —',
      };
      subtitle = '${VpnStats.formatDuration(connectedFor)} · $ipText';
    } else if (isConnecting) {
      subtitle = l.homeConnecting;
    } else if (isDisconnecting) {
      subtitle = l.homeDisconnecting;
    } else if (!hasConfig) {
      subtitle = l.homeNoConfigAdd;
    } else {
      subtitle = l.homeTapToConnect;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            stateWord,
            style: AppTheme.sans(size: 28, weight: FontWeight.w500, color: stateColor, letterSpacing: -1, height: 1),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5),
        ),
        if (isBlocked) ...[
          const SizedBox(height: 10),
          TapTarget(
            onTap: () => ref.read(vpnProvider.notifier).disconnect(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(border: Border.all(color: t.danger)),
              child: Text(l.homeDisconnectButton, style: AppTheme.mono(size: 9, color: t.danger, letterSpacing: 1.5)),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Power core ────────────────────────────────────────────────────
