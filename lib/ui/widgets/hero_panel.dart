import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Стандартная hero-панель: tagline · title · subtitle + trailing виджет.
/// Используется на всех экранах вместо дублирующихся Container+Stack+Corner ticks.
class HeroPanel extends StatelessWidget {
  final TeapodTokens t;

  /// Маленькая строка-подпись над заголовком (e.g. 'ЖУРНАЛ · XRAY · TUN2SOCKS').
  final String tagline;

  /// Крупный заголовок (e.g. 'LOGS').
  final String title;

  /// Цвет заголовка. По умолчанию [TeapodTokens.text].
  final Color? titleColor;

  /// Содержимое под заголовком (Text, Row с PulseDot и т.д.).
  final Widget? subtitle;

  /// Виджет справа (кнопки, бейдж, summary-блок).
  final Widget? trailing;

  const HeroPanel({
    super.key,
    required this.t,
    required this.tagline,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Stack(
        children: [
          // Corner ticks
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  Positioned(top: 6, left: 6,    child: _Tick(color: t.textMuted, tl: true)),
                  Positioned(top: 6, right: 6,   child: _Tick(color: t.textMuted, tr: true)),
                  Positioned(bottom: 6, left: 6,  child: _Tick(color: t.textMuted, bl: true)),
                  Positioned(bottom: 6, right: 6, child: _Tick(color: t.textMuted, br: true)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tagline,
                          style: AppTheme.mono(
                              size: 10, color: t.textMuted, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text(title,
                          style: AppTheme.sans(
                              size: 30,
                              weight: FontWeight.w500,
                              color: titleColor ?? t.text,
                              letterSpacing: -1,
                              height: 1)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        subtitle!,
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Corner tick painter ───────────────────────────────────────────

class _Tick extends StatelessWidget {
  final Color color;
  final bool tl, tr, bl, br;
  const _Tick({required this.color, this.tl = false, this.tr = false, this.bl = false, this.br = false});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(8, 8), painter: _TickPainter(color, tl, tr, bl, br));
}

class _TickPainter extends CustomPainter {
  final Color color;
  final bool tl, tr, bl, br;
  const _TickPainter(this.color, this.tl, this.tr, this.bl, this.br);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    final w = size.width; final h = size.height;
    if (tl) { canvas.drawLine(Offset.zero, Offset(w, 0), p); canvas.drawLine(Offset.zero, Offset(0, h), p); }
    if (tr) { canvas.drawLine(const Offset(0, 0), Offset(w, 0), p); canvas.drawLine(Offset(w, 0), Offset(w, h), p); }
    if (bl) { canvas.drawLine(Offset(0, h), Offset(w, h), p); canvas.drawLine(const Offset(0, 0), Offset(0, h), p); }
    if (br) { canvas.drawLine(Offset(0, h), Offset(w, h), p); canvas.drawLine(Offset(w, 0), Offset(w, h), p); }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
