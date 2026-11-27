// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/tap_target.dart';
import '../../l10n/l10n.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _controller;
  bool _scanned = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _controller = MobileScannerController(
        facing: CameraFacing.back,
        detectionSpeed: DetectionSpeed.unrestricted,
        formats: const [BarcodeFormat.qrCode],
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.qrCameraError('$e'));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;

    _scanned = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BreadcrumbBar(t: t, parent: 'add', current: 'qr'),
            Expanded(
              child: _error != null
                  ? _CameraError(
                      t: t,
                      message: _error!,
                      onRetry: () {
                        setState(() {
                          _error = null;
                          _scanned = false;
                        });
                        _initCamera();
                      },
                    )
                  : _controller == null
                  ? Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5))
                  : Stack(
                      children: [
                        MobileScanner(controller: _controller!, onDetect: _onDetect),
                        CustomPaint(
                          painter: ScanOverlayPainter(shade: t.bg.withValues(alpha: 0.6), corner: t.accent),
                          child: const SizedBox.expand(),
                        ),
                        Positioned(
                          bottom: 40,
                          left: 20,
                          right: 20,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: t.bg.withValues(alpha: 0.85),
                                border: Border.all(color: t.line),
                              ),
                              child: Text(
                                context.l10n.qrHint,
                                textAlign: TextAlign.center,
                                style: AppTheme.mono(size: 11, color: t.text, letterSpacing: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final TeapodTokens t;
  final String message;
  final VoidCallback onRetry;

  const _CameraError({required this.t, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, size: 40, color: t.textMuted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.mono(size: 11, color: t.danger, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            TapTarget(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: t.line)),
                child: Text(
                  context.l10n.commonRetryUpper,
                  style: AppTheme.mono(size: 10, color: t.accent, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shades the camera preview outside the square scan window and marks its corners.
@visibleForTesting
class ScanOverlayPainter extends CustomPainter {
  final Color shade;
  final Color corner;

  ScanOverlayPainter({required this.shade, required this.corner});

  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = size.shortestSide * 0.65;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2;

    // Everything but the window: the window stays clear.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(left, top, scanSize, scanSize));
    canvas.drawPath(outside, Paint()..color = shade);

    final cornerPaint = Paint()
      ..color = corner
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const cornerLen = 20.0;
    final corners = [
      Offset(left, top),
      Offset(left + scanSize, top),
      Offset(left, top + scanSize),
      Offset(left + scanSize, top + scanSize),
    ];
    const dx = [1.0, -1.0, 1.0, -1.0];
    const dy = [1.0, 1.0, -1.0, -1.0];
    for (var i = 0; i < 4; i++) {
      final p = corners[i];
      canvas.drawLine(p, p + Offset(dx[i] * cornerLen, 0), cornerPaint);
      canvas.drawLine(p, p + Offset(0, dy[i] * cornerLen), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(ScanOverlayPainter old) => old.shade != shade || old.corner != corner;
}
