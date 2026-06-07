import 'package:flutter/material.dart';
import 'package:nodeql/engine/block/block_node.dart';

class BlockShape extends StatelessWidget {
  const BlockShape({
    super.key,
    required this.node,
    required this.color,
    required this.width,
    required this.height,
    required this.label,
    this.isHighlighted = false,
    this.isSelected = false,
    this.showInnerHighlight = false,
  });

  final BlockNode node;
  final Color color;
  final double width;
  final double height;
  final String label;
  final bool isHighlighted;
  final bool isSelected;
  final bool showInnerHighlight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ScratchBlockPainter(
        color: color,
        node: node,
        isHighlighted: isHighlighted,
        isSelected: isSelected,
        showInnerHighlight: showInnerHighlight,
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: Padding(
            padding: const EdgeInsets.only(left: 14, top: 10, right: 12),
            child: SizedBox(
              width: width - 26,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScratchBlockPainter extends CustomPainter {
  _ScratchBlockPainter({
    required this.color,
    required this.node,
    required this.isHighlighted,
    required this.isSelected,
    required this.showInnerHighlight,
  });

  final Color color;
  final BlockNode node;
  final bool isHighlighted;
  final bool isSelected;
  final bool showInnerHighlight;

  static const double upperBar = 40;
  static const double lowerBar = 20;
  static const double notchX = 34;
  static const double notchW = 22;
  static const double notchH = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final path = node is ControlBlock
        ? _buildCBlockPath(size)
        : _buildSimplePath(size);

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.28), 8, false);
    canvas.drawPath(path, Paint()..color = color);

    if (node is ControlBlock && showInnerHighlight) {
      final mouthRect = Rect.fromLTWH(
        15,
        upperBar,
        size.width - 22,
        size.height - (upperBar + lowerBar),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(mouthRect, const Radius.circular(8)),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }

    if (isHighlighted || isSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = isSelected
              ? const Color(0xFFFFF176)
              : Colors.white.withValues(alpha: 0.65),
      );
    }
  }

  Path _buildSimplePath(Size size) {
    const r = 10.0;

    final p = Path()..moveTo(r, 0);
    p.lineTo(notchX, 0);
    p.lineTo(notchX + 4, notchH);
    p.lineTo(notchX + notchW - 4, notchH);
    p.lineTo(notchX + notchW, 0);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.lineTo(size.width, size.height - r);
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    p.lineTo(notchX + notchW, size.height);
    p.lineTo(notchX + notchW - 4, size.height + notchH);
    p.lineTo(notchX + 4, size.height + notchH);
    p.lineTo(notchX, size.height);
    p.lineTo(r, size.height);
    p.quadraticBezierTo(0, size.height, 0, size.height - r);
    p.lineTo(0, r);
    p.quadraticBezierTo(0, 0, r, 0);
    p.close();
    return p;
  }

  Path _buildCBlockPath(Size size) {
    const r = 10.0;
    final innerTop = upperBar;
    final innerBottom = size.height - lowerBar;

    final p = Path()..moveTo(r, 0);

    // Upper bar with top notch.
    p.lineTo(notchX, 0);
    p.lineTo(notchX + 4, notchH);
    p.lineTo(notchX + notchW - 4, notchH);
    p.lineTo(notchX + notchW, 0);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);

    // Right edge down to mouth top.
    p.lineTo(size.width, innerTop - r);
    p.quadraticBezierTo(size.width, innerTop, size.width - r, innerTop);

    // Inner mouth start notch and spine.
    p.lineTo(30, innerTop);
    p.lineTo(22, innerTop + 8);
    p.lineTo(22, innerBottom - 8);
    p.lineTo(30, innerBottom);

    // Lower bar and outer bottom tab.
    p.lineTo(size.width - r, innerBottom);
    p.quadraticBezierTo(size.width, innerBottom, size.width, innerBottom + r);
    p.lineTo(size.width, size.height - r);
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    p.lineTo(notchX + notchW, size.height);
    p.lineTo(notchX + notchW - 4, size.height + notchH);
    p.lineTo(notchX + 4, size.height + notchH);
    p.lineTo(notchX, size.height);

    // Left vertical spine closure.
    p.lineTo(r, size.height);
    p.quadraticBezierTo(0, size.height, 0, size.height - r);
    p.lineTo(0, r);
    p.quadraticBezierTo(0, 0, r, 0);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _ScratchBlockPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isHighlighted != isHighlighted ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.showInnerHighlight != showInnerHighlight ||
        oldDelegate.node.id != node.id;
  }
}
