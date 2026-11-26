part of 'settings_screen.dart';

class _SetHeaderStrip extends StatelessWidget {
  final TeapodTokens t;
  final bool locked;
  const _SetHeaderStrip({required this.t, required this.locked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('teapod.stream // config', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          Text(
            'sys.state [${locked ? 'locked' : 'open'}]',
            style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

// ── Hero panel ────────────────────────────────────────────────────

class _SetHeroPanel extends StatelessWidget {
  final TeapodTokens t;
  final bool locked;
  final String profileName;
  final bool profileReadonly;
  const _SetHeroPanel({
    required this.t,
    required this.locked,
    required this.profileName,
    required this.profileReadonly,
  });

  static const Color _gold = AppColors.accentGold;

  @override
  Widget build(BuildContext context) {
    final wordColor = locked ? _gold : t.text;
    final lockColor = locked ? _gold : t.textDim;
    final borderColor = locked ? _gold : t.line;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Stack(
        children: [
          SetCornerTicks(t: t, color: locked ? _gold : t.textMuted),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.settingsTagline,
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        locked ? 'LOCKED' : 'CONFIG',
                        style: AppTheme.sans(
                          size: 30,
                          weight: FontWeight.w500,
                          color: wordColor,
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        locked ? context.l10n.settingsProfileLocked : context.l10n.settingsProfileAutosave(profileName),
                        style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Lock indicator
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(border: Border.all(color: borderColor)),
                  child: Stack(
                    children: [
                      if (locked) ...[
                        Positioned(top: -1, left: -1, child: _LockCorner(color: _gold, isTop: true)),
                        Positioned(bottom: -1, right: -1, child: _LockCorner(color: _gold, isTop: false)),
                      ],
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LockIcon(color: lockColor, open: !locked),
                            const SizedBox(height: 2),
                            Text(
                              locked ? 'ro' : 'rw',
                              style: AppTheme.mono(size: 8, color: lockColor, letterSpacing: 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LockCorner extends StatelessWidget {
  final Color color;
  final bool isTop;
  const _LockCorner({required this.color, required this.isTop});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(5, 5),
    painter: _LockCornerPainter(color: color, isTop: isTop),
  );
}

class _LockCornerPainter extends CustomPainter {
  final Color color;
  final bool isTop;
  const _LockCornerPainter({required this.color, required this.isTop});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (isTop) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), p);
      canvas.drawLine(Offset.zero, Offset(0, size.height), p);
    } else {
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_LockCornerPainter old) => old.color != color;
}

class _LockIcon extends StatelessWidget {
  final Color color;
  final bool open;
  const _LockIcon({required this.color, required this.open});

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(20, 20), painter: _LockPainter(color, open));
}

class _LockPainter extends CustomPainter {
  final Color color;
  final bool open;
  const _LockPainter(this.color, this.open);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size.width / 24.0;
    canvas.scale(s, s);
    // Body
    final body = RRect.fromLTRBR(4, 11, 20, 21, const Radius.circular(1));
    canvas.drawRRect(body, p);
    // Shackle
    if (open) {
      final path = Path()
        ..moveTo(8, 11)
        ..lineTo(8, 7)
        ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
        ..lineTo(16, 11);
      canvas.drawPath(path, p);
    } else {
      final path = Path()
        ..moveTo(8, 11)
        ..lineTo(8, 7)
        ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
        ..lineTo(16, 11);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_LockPainter old) => old.color != color || old.open != open;
}

// ── Settings body ─────────────────────────────────────────────────
