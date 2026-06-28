import 'package:flutter/material.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_syntax.dart';

class BlockShape extends StatelessWidget {
  const BlockShape({
    super.key,
    required this.node,
    required this.color,
    required this.width,
    required this.height,
    required this.label,
    this.pluginShape,
    this.isHighlighted = false,
    this.isErrorHighlighted = false,
    this.isSelected = false,
    this.showInnerHighlight = false,
    this.showLabel = true,
  });

  final BlockNode node;
  final Color color;
  final double width;
  final double height;
  final String label;
  final String? pluginShape;
  final bool isHighlighted;
  final bool isErrorHighlighted;
  final bool isSelected;
  final bool showInnerHighlight;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final kind = blockVisualKind(node, pluginShape: pluginShape);
    final isTrigger = kind == BlockVisualKind.trigger;
    final isJoin = kind == BlockVisualKind.join;
    final isPlugin = switch (kind) {
      BlockVisualKind.pluginStatement ||
      BlockVisualKind.pluginValue ||
      BlockVisualKind.pluginContainer => true,
      _ => false,
    };
    return CustomPaint(
      size: Size(width, height),
      painter: _ScratchBlockPainter(
        color: color,
        node: node,
        isHighlighted: isHighlighted,
        isErrorHighlighted: isErrorHighlighted,
        isSelected: isSelected,
        showInnerHighlight: showInnerHighlight,
        pluginShape: pluginShape,
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: Padding(
            padding: EdgeInsets.only(
              left: isTrigger ? 16 : (isJoin ? 26 : (isPlugin ? 28 : 14)),
              top: isTrigger ? 12 : (isJoin ? 9 : 10),
              right: 12,
            ),
            child: SizedBox(
              width:
                  width -
                  (isTrigger ? 28 : (isJoin ? 38 : (isPlugin ? 42 : 26))),
              child: !showLabel
                  ? const SizedBox.shrink()
                  : isTrigger
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(child: _BlockLabel(label: label)),
                      ],
                    )
                  : _BlockLabel(label: label, isJoin: isJoin),
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
    required this.isErrorHighlighted,
    required this.isSelected,
    required this.showInnerHighlight,
    required this.pluginShape,
  });

  final Color color;
  final BlockNode node;
  final bool isHighlighted;
  final bool isErrorHighlighted;
  final bool isSelected;
  final bool showInnerHighlight;
  final String? pluginShape;

  static const double upperBar = 40;
  static const double lowerBar = 20;
  static const double notchX = 34;
  static const double notchW = 22;
  static const double notchH = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final kind = blockVisualKind(node, pluginShape: pluginShape);
    final path = switch (kind) {
      BlockVisualKind.trigger => _buildHatPath(size),
      BlockVisualKind.statement => _buildStatementPath(size),
      BlockVisualKind.join => _buildJoinPath(size),
      BlockVisualKind.setOperator => _buildSetOperatorPath(size),
      BlockVisualKind.expression => _buildExpressionPath(size),
      BlockVisualKind.container => _buildCBlockPath(size),
      BlockVisualKind.terminal => _buildTerminalPath(size),
      BlockVisualKind.clause => _buildSimplePath(size),
      BlockVisualKind.pluginStatement => _buildPluginStatementPath(size),
      BlockVisualKind.pluginValue => _buildPluginValuePath(size),
      BlockVisualKind.pluginContainer => _buildCBlockPath(size),
    };

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.28), 8, false);
    canvas.drawPath(path, Paint()..color = color);
    _paintBlockBoundary(canvas, path);

    if (kind == BlockVisualKind.join) {
      final separatorPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.58)
        ..strokeWidth = 2;
      canvas.drawLine(
        const Offset(20, 9),
        Offset(20, size.height - 9),
        separatorPaint,
      );
      canvas.drawCircle(
        const Offset(20, 9),
        2.4,
        Paint()..color = Colors.white.withValues(alpha: 0.72),
      );
      canvas.drawCircle(
        Offset(20, size.height - 9),
        2.4,
        Paint()..color = Colors.white.withValues(alpha: 0.72),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 8, 8, size.height - 16),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.24),
      );
      if (joinUsesCondition(node)) {
        canvas.drawLine(
          Offset(22, size.height / 2),
          Offset(size.width - 10, size.height / 2),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.18)
            ..strokeWidth = 1,
        );
      }
    }

    if (kind == BlockVisualKind.setOperator) {
      canvas.drawLine(
        const Offset(18, 8),
        Offset(size.width - 18, 8),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..strokeWidth = 2,
      );
    }

    if (kind == BlockVisualKind.pluginStatement ||
        kind == BlockVisualKind.pluginValue ||
        kind == BlockVisualKind.pluginContainer) {
      _paintPluginRail(canvas, size, kind);
    }

    if ((kind == BlockVisualKind.container ||
            kind == BlockVisualKind.pluginContainer) &&
        showInnerHighlight) {
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

    if (isHighlighted || isSelected || isErrorHighlighted) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isErrorHighlighted ? 4 : 3
          ..color = isErrorHighlighted
              ? const Color(0xFFF87171)
              : isSelected
              ? const Color(0xFFFFF176)
              : Colors.white.withValues(alpha: 0.65),
      );
    }
  }

  void _paintBlockBoundary(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.32),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.34),
    );
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

  Path _buildHatPath(Size size) {
    const r = 11.0;
    final p = Path()..moveTo(r, 0);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.lineTo(size.width, size.height - r);
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    _addBottomTab(p, size);
    p.lineTo(r, size.height);
    p.quadraticBezierTo(0, size.height, 0, size.height - r);
    p.lineTo(0, r);
    p.quadraticBezierTo(0, 0, r, 0);
    p.close();
    return p;
  }

  Path _buildStatementPath(Size size) {
    const r = 10.0;
    final p = Path()..moveTo(r, 0);
    _addTopNotch(p);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.lineTo(size.width, size.height - r);
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    _addBottomTab(p, size);
    p.lineTo(r, size.height);
    p.quadraticBezierTo(0, size.height, 0, size.height - r);
    p.lineTo(0, r);
    p.quadraticBezierTo(0, 0, r, 0);
    p.close();
    return p;
  }

  Path _buildJoinPath(Size size) {
    const r = 10.0;
    final p = Path()..moveTo(r + 8, 0);
    _addTopNotch(p);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.lineTo(size.width, size.height - r);
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    _addBottomTab(p, size);
    p.lineTo(r + 8, size.height);
    p.lineTo(0, size.height / 2);
    p.lineTo(r + 8, 0);
    p.close();
    return p;
  }

  Path _buildSetOperatorPath(Size size) {
    const r = 10.0;
    final p = Path()..moveTo(r, 0);
    _addTopNotch(p);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.quadraticBezierTo(
      size.width - 12,
      size.height / 2,
      size.width,
      size.height - r,
    );
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    _addBottomTab(p, size);
    p.lineTo(r, size.height);
    p.quadraticBezierTo(0, size.height, 0, size.height - r);
    p.quadraticBezierTo(12, size.height / 2, 0, r);
    p.quadraticBezierTo(0, 0, r, 0);
    p.close();
    return p;
  }

  Path _buildExpressionPath(Size size) {
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
    );
  }

  Path _buildTerminalPath(Size size) {
    const r = 10.0;
    final p = Path()..moveTo(r, 0);
    _addTopNotch(p);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.lineTo(size.width, size.height - r);
    p.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    p.lineTo(r, size.height);
    p.quadraticBezierTo(0, size.height, 0, size.height - r);
    p.lineTo(0, r);
    p.quadraticBezierTo(0, 0, r, 0);
    p.close();
    return p;
  }

  Path _buildPluginStatementPath(Size size) {
    const r = 10.0;
    const cut = 12.0;
    final p = Path()..moveTo(cut, 0);
    _addTopNotch(p);
    p.lineTo(size.width - r, 0);
    p.quadraticBezierTo(size.width, 0, size.width, r);
    p.lineTo(size.width, size.height - cut);
    p.lineTo(size.width - cut, size.height);
    _addBottomTab(p, size);
    p.lineTo(cut, size.height);
    p.lineTo(0, size.height - cut);
    p.lineTo(0, cut);
    p.close();
    return p;
  }

  Path _buildPluginValuePath(Size size) {
    const cut = 13.0;
    final p = Path()..moveTo(cut, 0);
    p.lineTo(size.width - cut, 0);
    p.lineTo(size.width, size.height / 2);
    p.lineTo(size.width - cut, size.height);
    p.lineTo(cut, size.height);
    p.lineTo(0, size.height / 2);
    p.close();
    return p;
  }

  void _paintPluginRail(Canvas canvas, Size size, BlockVisualKind kind) {
    final railHeight = kind == BlockVisualKind.pluginContainer
        ? upperBar - 14
        : size.height - 16;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, 9, railHeight),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      const Offset(12.5, 15),
      2.2,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  void _addTopNotch(Path p) {
    p.lineTo(notchX, 0);
    p.lineTo(notchX + 4, notchH);
    p.lineTo(notchX + notchW - 4, notchH);
    p.lineTo(notchX + notchW, 0);
  }

  void _addBottomTab(Path p, Size size) {
    p.lineTo(notchX + notchW, size.height);
    p.lineTo(notchX + notchW - 4, size.height + notchH);
    p.lineTo(notchX + 4, size.height + notchH);
    p.lineTo(notchX, size.height);
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
        oldDelegate.isErrorHighlighted != isErrorHighlighted ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.showInnerHighlight != showInnerHighlight ||
        oldDelegate.pluginShape != pluginShape ||
        oldDelegate.node.id != node.id;
  }
}

class _BlockLabel extends StatelessWidget {
  const _BlockLabel({required this.label, this.isJoin = false});

  final String label;
  final bool isJoin;

  @override
  Widget build(BuildContext context) {
    final usesMultipleLines = label.contains('\n');
    return Text(
      label,
      maxLines: usesMultipleLines ? 3 : (isJoin ? 2 : 1),
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ).copyWith(height: usesMultipleLines || isJoin ? 1.65 : 1),
    );
  }
}
