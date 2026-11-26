part of 'home_screen.dart';

class _PowerCore extends StatefulWidget {
  final TeapodTokens t;
  final bool isConnected;
  final bool isBusy;
  final bool isBlocked;
  final bool enabled;
  final String disabledLabel;
  final VoidCallback onTap;

  const _PowerCore({
    required this.t,
    required this.isConnected,
    required this.isBusy,
    required this.isBlocked,
    required this.enabled,
    required this.disabledLabel,
    required this.onTap,
  });

  @override
  State<_PowerCore> createState() => _PowerCoreState();
}

class _PowerCoreState extends State<_PowerCore> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final conn = widget.isConnected;
    final busy = widget.isBusy;
    final blocked = widget.isBlocked;
    final actionLabel = !widget.enabled
        ? widget.disabledLabel
        : blocked
        ? context.l10n.homeActionReconnect
        : conn
        ? context.l10n.homeActionDisconnect
        : (busy ? context.l10n.homeActionWait : context.l10n.homeActionConnect);

    const coreSize = 220.0;
    const outerSize = coreSize + 32.0;
    const innerSize = coreSize - 44.0;

    return Semantics(
      label: actionLabel,
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: outerSize,
          height: outerSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outermost faint ring
              Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: blocked ? t.danger : (conn ? t.accentSoft : t.line), width: 1),
                ),
              ),
              // Spinning arc when connecting/disconnecting
              if (busy)
                SizedBox(
                  width: coreSize + 10,
                  height: coreSize + 10,
                  child: RotationTransition(
                    turns: _spin,
                    child: CustomPaint(painter: _SpinArcPainter(t.accent)),
                  ),
                ),
              // Main ring
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: coreSize,
                height: coreSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: blocked ? t.danger : (conn ? t.accent : t.line), width: 1),
                  boxShadow: conn ? [BoxShadow(color: t.accentSoft, blurRadius: 60, spreadRadius: 4)] : null,
                ),
              ),
              // Inner disk
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: innerSize,
                height: innerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: conn ? t.accent : t.bgElev,
                  border: Border.all(color: conn ? t.accent : t.line, width: 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PowerIcon(color: conn ? t.bg : t.text, size: 40),
                    const SizedBox(height: 6),
                    Text(
                      actionLabel.toUpperCase(),
                      style: AppTheme.mono(size: 9, color: conn ? t.bg : t.textDim, letterSpacing: 2),
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

class _SpinArcPainter extends CustomPainter {
  final Color color;
  const _SpinArcPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height), -math.pi / 2, math.pi * 1.5, false, paint);
  }

  @override
  bool shouldRepaint(_SpinArcPainter old) => old.color != color;
}

// ── Power icon ────────────────────────────────────────────────────

class _PowerIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _PowerIcon({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _PowerPainter(color));
}

class _PowerPainter extends CustomPainter {
  final Color color;
  const _PowerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final s = size.width / 24.0;
    canvas.scale(s, s);

    canvas.drawLine(const Offset(12, 2), const Offset(12, 9), paint);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 13), radius: 8),
      -math.pi / 3,
      math.pi * 5 / 3,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.color != color;
}

// ── Corner ticks ──────────────────────────────────────────────────
