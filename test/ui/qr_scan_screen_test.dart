import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/ui/screens/qr_scan_screen.dart';

void main() {
  test('the overlay shades only outside the scan window', () async {
    const size = Size(200, 400);
    final recorder = ui.PictureRecorder();
    ScanOverlayPainter(shade: const Color(0x99000000), corner: const Color(0xFF00FF00)).paint(Canvas(recorder), size);
    final image = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alphaAt(int x, int y) => bytes.getUint8((y * size.width.toInt() + x) * 4 + 3);

    expect(alphaAt(100, 200), 0, reason: 'the window stays clear');
    expect(alphaAt(5, 5), 0x99, reason: 'outside is shaded once');
    expect(alphaAt(100, 20), 0x99);
  });
}
