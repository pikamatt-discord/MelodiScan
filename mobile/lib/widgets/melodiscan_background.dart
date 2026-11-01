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
          colors: [Color(0xFF101628), Color(0xFF0B101B), Color(0xFF0A0D16)],
        ).createShader(bounds),
    );

    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);
    glowPaint.color = const Color(0xFF7757C8).withValues(alpha: 0.18);
    canvas.drawCircle(
        Offset(size.width * 0.92, size.height * 0.07), 150, glowPaint);
    glowPaint.color = const Color(0xFF1F8A8B).withValues(alpha: 0.10);
    canvas.drawCircle(
        Offset(size.width * 0.02, size.height * 0.72), 130, glowPaint);

    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final staffPath = Path();
    final startX = size.width * 0.52;
    final endX = size.width + 20;
    for (var line = 0; line < 5; line++) {
      final y = size.height * 0.12 + line * 14.0;
      staffPath
        ..moveTo(startX, y)
        ..cubicTo(
            size.width * 0.7, y - 28, size.width * 0.84, y + 28, endX, y - 5);
    }
    canvas.drawPath(staffPath, staffPaint);

    final notePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;
    for (final note in [
      Offset(size.width * 0.71, size.height * 0.105),
      Offset(size.width * 0.88, size.height * 0.075),
    ]) {
      canvas.save();
      canvas.translate(note.dx, note.dy);
      canvas.rotate(-0.3);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 13, height: 8),
          notePaint);
      canvas.restore();
      canvas.drawLine(
        note,
        note.translate(0, -42),
        Paint()
          ..color = notePaint.color
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MelodiScanBackgroundPainter oldDelegate) =>
      false;
}
