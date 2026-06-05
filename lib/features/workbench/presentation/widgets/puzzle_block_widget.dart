import 'package:flutter/material.dart';

class PuzzleBlockWidget extends StatelessWidget {
  const PuzzleBlockWidget({
    super.key,
    required this.label,
    required this.color,
    this.isHat = false,
    this.highlight = false,
    this.elevated = false,
    this.width = 190,
    this.height = 42,
  });

  final String label;
  final Color color;
  final bool isHat;
  final bool highlight;
  final bool elevated;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shadow = elevated
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ];

    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: elevated ? 1.03 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: shadow),
        child: CustomPaint(
          size: Size(width, height),
          painter: _PuzzleBlockPainter(
            color: color,
            isHat: isHat,
            highlight: highlight,
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PuzzleBlockPainter extends CustomPainter {
  _PuzzleBlockPainter({
    required this.color,
    required this.isHat,
    required this.highlight,
  });

  final Color color;
  final bool isHat;
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    const notchW = 24.0;
    const notchH = 7.0;
    const notchInset = 26.0;
    const radius = 12.0;

    final topY = isHat ? 6.0 : 0.0;

    path.moveTo(radius, topY);

    if (isHat) {
      path.quadraticBezierTo(size.width * 0.3, -6, size.width * 0.5, topY);
      path.quadraticBezierTo(size.width * 0.7, -6, size.width - radius, topY);
    } else {
      path.lineTo(notchInset, topY);
      path.lineTo(notchInset + 4, topY + notchH);
      path.lineTo(notchInset + notchW - 4, topY + notchH);
      path.lineTo(notchInset + notchW, topY);
      path.lineTo(size.width - radius, topY);
    }

    path.quadraticBezierTo(size.width, topY, size.width, topY + radius);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(size.width, size.height, size.width - radius, size.height);

    path.lineTo(notchInset + notchW, size.height);
    path.lineTo(notchInset + notchW - 4, size.height + notchH);
    path.lineTo(notchInset + 4, size.height + notchH);
    path.lineTo(notchInset, size.height);

    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.lineTo(0, topY + radius);
    path.quadraticBezierTo(0, topY, radius, topY);
    path.close();

    canvas.drawPath(path, paint);

    final overlay = Paint()
      ..color = (highlight ? Colors.white : Colors.black)
          .withValues(alpha: highlight ? 0.20 : 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, overlay);
  }

  @override
  bool shouldRepaint(covariant _PuzzleBlockPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isHat != isHat ||
        oldDelegate.highlight != highlight;
  }
}
