import 'package:flutter/material.dart';

class MelodiScanBackground extends StatelessWidget {
  const MelodiScanBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _MelodiScanBackgroundPainter()),
          child,
        ],
      );
}

class _MelodiScanBackgroundPainter extends CustomPainter {
  const _MelodiScanBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF11182A),
            Color(0xFF0B111D),
            Color(0xFF080D17),
          ],
          stops: [0, 0.52, 1],
        ).createShader(bounds),
    );

    _drawGlow(
      canvas,
      Offset(size.width * 0.97, size.height * 0.08),
      size.shortestSide * 0.72,
      const Color(0xFF7956D9),
      0.22,
    );
    _drawGlow(
      canvas,
      Offset(size.width * 0.02, size.height * 0.72),
      size.shortestSide * 0.68,
      const Color(0xFF20B8A7),
      0.14,
    );
    _drawGlow(
      canvas,
      Offset(size.width * 0.68, size.height * 0.56),
      size.shortestSide * 0.52,
      const Color(0xFF3154A5),
      0.08,
    );

    final contourPaint = Paint()
      ..color = const Color(0xFFB69CFF).withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var band = 0; band < 4; band++) {
      final path = Path()
        ..moveTo(size.width * 0.52, size.height * (0.25 + band * 0.035))
        ..cubicTo(
          size.width * 0.78,
          size.height * (0.10 + band * 0.025),
          size.width * 0.76,
          size.height * (0.44 + band * 0.03),
          size.width * 1.08,
          size.height * (0.31 + band * 0.035),
        );
      canvas.drawPath(path, contourPaint);
    }

    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style = PaintingStyle.fill;
    final staffRect = Rect.fromLTWH(
      size.width * 0.51,
      size.height * 0.09,
      size.width * 0.6,
      size.height * 0.12,
    );
    for (var line = 0; line < 5; line++) {
      final y = staffRect.top + line * staffRect.height / 4;
      final path = Path()
        ..moveTo(staffRect.left, y)
        ..cubicTo(
          size.width * 0.70,
          y - size.height * 0.025,
          size.width * 0.86,
          y + size.height * 0.025,
          size.width * 1.08,
          y - size.height * 0.005,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.035)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    _drawNote(
        canvas, Offset(size.width * 0.69, size.height * 0.14), staffPaint);
    _drawNote(
        canvas, Offset(size.width * 0.88, size.height * 0.105), staffPaint);
  }

  void _drawGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double opacity,
  ) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.42),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.38, 1],
        ).createShader(bounds),
    );
  }

  void _drawNote(Canvas canvas, Offset position, Paint paint) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(-0.32);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 13, height: 8),
      paint,
    );
    canvas.drawLine(
      const Offset(5, 0),
      const Offset(5, -38),
      Paint()
        ..color = paint.color
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MelodiScanBackgroundPainter oldDelegate) =>
      false;
}
