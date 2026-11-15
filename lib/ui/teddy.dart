/// A cute teddy bear face drawn in code (no image files needed).
///
/// Usage: `const TeddyBear(size: 80)`
library;

import 'package:flutter/material.dart';

class TeddyBear extends StatelessWidget {
  const TeddyBear({super.key, this.size = 64, this.dark = false});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TeddyPainter(dark: dark)),
    );
  }
}

class _TeddyPainter extends CustomPainter {
  _TeddyPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    Paint fill(Color c) => Paint()..color = c;

    final fur = dark ? const Color(0xFFC49A78) : const Color(0xFFD2A67F);
    final inner = dark ? const Color(0xFFE0BFA0) : const Color(0xFFF0CFB0);
    const cream = Color(0xFFF6E7CF);
    const brown = Color(0xFF5B4034);
    const blush = Color(0x66F0A08A);

    // Ears
    for (final x in [0.22, 0.78]) {
      canvas.drawCircle(Offset(w * x, h * 0.24), w * 0.17, fill(fur));
      canvas.drawCircle(Offset(w * x, h * 0.24), w * 0.09, fill(inner));
    }

    // Head
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.55), width: w * 0.84, height: h * 0.74),
      fill(fur),
    );

    // Cheeks
    for (final x in [0.25, 0.75]) {
      canvas.drawCircle(Offset(w * x, h * 0.64), w * 0.07, fill(blush));
    }

    // Muzzle
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.66), width: w * 0.38, height: h * 0.28),
      fill(cream),
    );

    // Eyes
    for (final x in [0.34, 0.66]) {
      canvas.drawCircle(Offset(w * x, h * 0.5), w * 0.045, fill(brown));
    }

    // Nose
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.6), width: w * 0.14, height: h * 0.09),
      fill(brown),
    );

    // Smile
    final smile = Paint()
      ..color = brown
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.022
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.645)
      ..lineTo(w * 0.5, h * 0.68)
      ..moveTo(w * 0.5, h * 0.68)
      ..quadraticBezierTo(w * 0.45, h * 0.73, w * 0.41, h * 0.69)
      ..moveTo(w * 0.5, h * 0.68)
      ..quadraticBezierTo(w * 0.55, h * 0.73, w * 0.59, h * 0.69);
    canvas.drawPath(path, smile);
  }

  @override
  bool shouldRepaint(covariant _TeddyPainter old) => old.dark != dark;
}
