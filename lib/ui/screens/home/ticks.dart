part of 'home_screen.dart';

class _CornerTicks extends StatelessWidget {
  final TeapodTokens t;
  const _CornerTicks({required this.t});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: 6,
              left: 6,
              child: _Tick(color: t.textMuted, corner: _TickCorner.tl),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _Tick(color: t.textMuted, corner: _TickCorner.tr),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: _Tick(color: t.textMuted, corner: _TickCorner.bl),
            ),
            Positioned(
              bottom: 6,
              right: 6,
              child: _Tick(color: t.textMuted, corner: _TickCorner.br),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TickCorner { tl, tr, bl, br }

class _Tick extends StatelessWidget {
  final Color color;
  final _TickCorner corner;
  const _Tick({required this.color, required this.corner});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 8, height: 8, child: CustomPaint(painter: _TickPainter(color, corner)));
  }
}

class _TickPainter extends CustomPainter {
  final Color color;
  final _TickCorner corner;
  const _TickPainter(this.color, this.corner);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    switch (corner) {
      case _TickCorner.tl:
        canvas.drawLine(Offset.zero, Offset(w, 0), p);
        canvas.drawLine(Offset.zero, Offset(0, h), p);
      case _TickCorner.tr:
        canvas.drawLine(Offset(0, 0), Offset(w, 0), p);
        canvas.drawLine(Offset(w, 0), Offset(w, h), p);
      case _TickCorner.bl:
        canvas.drawLine(Offset(0, h), Offset(w, h), p);
        canvas.drawLine(Offset(0, 0), Offset(0, h), p);
      case _TickCorner.br:
        canvas.drawLine(Offset(0, h), Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(w, h), p);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

// ── Metrics grid ──────────────────────────────────────────────────
