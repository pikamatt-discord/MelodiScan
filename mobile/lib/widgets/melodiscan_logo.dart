import 'package:flutter/material.dart';

class MelodiScanLogo extends StatelessWidget {
  final double size;

  const MelodiScanLogo({
    super.key,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MelodiScanLogoPainter(),
      ),
    );
  }
}

class _MelodiScanLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512.0;

    // Background squircle rect
    final bgPaint = Paint()
      ..color = const Color(0xFF0D0E15)
      ..style = PaintingStyle.fill;
    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(115 * scale),
    );
    canvas.drawRRect(bgRRect, bgPaint);

    // Cyan Viewfinder corners
    final cyanPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * scale
      ..strokeCap = StrokeCap.round;

    final pathTL = Path()
      ..moveTo(116 * scale, 176 * scale)
      ..lineTo(116 * scale, 136 * scale)
      ..quadraticBezierTo(116 * scale, 116 * scale, 136 * scale, 116 * scale)
      ..lineTo(176 * scale, 116 * scale);
    canvas.drawPath(pathTL, cyanPaint);

    final pathTR = Path()
      ..moveTo(336 * scale, 116 * scale)
      ..lineTo(376 * scale, 116 * scale)
      ..quadraticBezierTo(396 * scale, 116 * scale, 396 * scale, 136 * scale)
      ..lineTo(396 * scale, 176 * scale);
    canvas.drawPath(pathTR, cyanPaint);

    final pathBL = Path()
      ..moveTo(116 * scale, 336 * scale)
      ..lineTo(116 * scale, 376 * scale)
      ..quadraticBezierTo(116 * scale, 396 * scale, 136 * scale, 396 * scale)
      ..lineTo(176 * scale, 396 * scale);
    canvas.drawPath(pathBL, cyanPaint);

    final pathBR = Path()
      ..moveTo(336 * scale, 396 * scale)
      ..lineTo(376 * scale, 396 * scale)
      ..quadraticBezierTo(396 * scale, 396 * scale, 396 * scale, 376 * scale)
      ..lineTo(396 * scale, 336 * scale);
    canvas.drawPath(pathBR, cyanPaint);

    // Equalizer bars gradient
    final purpleShader = const LinearGradient(
      colors: [Color(0xFF9D4EDD), Color(0xFF4A00E0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final cyanShader = const LinearGradient(
      colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final barPaintPurple = Paint()..shader = purpleShader;
    final barPaintCyan = Paint()..shader = cyanShader;

    void drawBar(double x, double y, double w, double h, double rx, Paint paint) {
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * scale, y * scale, w * scale, h * scale),
        Radius.circular(rx * scale),
      );
      canvas.drawRRect(rrect, paint);
    }

    drawBar(160, 226, 18, 60, 9, barPaintPurple);
    drawBar(196, 186, 18, 140, 9, barPaintPurple);
    drawBar(232, 156, 18, 200, 9, barPaintPurple);
    drawBar(268, 136, 18, 240, 9, barPaintCyan); // Central cyan bar
    drawBar(304, 176, 18, 160, 9, barPaintPurple);
    drawBar(340, 206, 18, 100, 9, barPaintPurple);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
