import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.qrTitle),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt, size: 48, color: AppColors.textDisabled),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.logError)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() { _error = null; _scanned = false; });
                      _initCamera();
                    },
                    child: Text(context.l10n.commonRetry),
                  ),
                ],
              ),
            )
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    MobileScanner(
                      controller: _controller!,
                      onDetect: _onDetect,
                    ),
                    CustomPaint(
                      painter: _ScanOverlayPainter(),
                      child: const SizedBox.expand(),
                    ),
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.bg.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            context.l10n.qrHint,
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54..style = PaintingStyle.fill;
    final scanSize = size.width * 0.65;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final cutoutPath = Path()
      ..addRect(Rect.fromLTWH(left, top, scanSize, scanSize))
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    cutoutPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(cutoutPath, paint);

    final cornerPaint = Paint()..color = Colors.white..strokeWidth = 3..style = PaintingStyle.stroke;
    const cornerLen = 20.0;
    final corners = [
      Offset(left, top),
      Offset(left + scanSize, top),
      Offset(left, top + scanSize),
      Offset(left + scanSize, top + scanSize),
    ];
    const dx = [1.0, -1.0, 1.0, -1.0];
    const dy = [1.0, 1.0, -1.0, -1.0];
    for (int i = 0; i < 4; i++) {
      final p = corners[i];
      canvas.drawLine(p, p + Offset(dx[i] * cornerLen, 0), cornerPaint);
      canvas.drawLine(p, p + Offset(0, dy[i] * cornerLen), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
