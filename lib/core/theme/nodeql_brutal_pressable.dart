import 'package:flutter/material.dart';
import 'package:nodeql/core/theme/theme_controller.dart';

/// Adds the physical hover/press behavior that Material button themes cannot
/// express: a crisp zero-blur shadow grows on hover and collapses as the
/// control moves into it on press.
///
/// In non-brutalist themes the wrapper only clips the child to the configured
/// radius. This keeps custom button fills inside the rounded Material shape.
class NodeQlBrutalPressable extends StatefulWidget {
  const NodeQlBrutalPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.radius,
  });

  final Widget child;
  final bool enabled;
  final double? radius;

  @override
  State<NodeQlBrutalPressable> createState() => _NodeQlBrutalPressableState();
}

class _NodeQlBrutalPressableState extends State<NodeQlBrutalPressable> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value && (!_pressed || value)) return;
    setState(() {
      _hovered = value;
      if (!value) _pressed = false;
    });
  }

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final style = NodeQlSurfaceStyle.of(context);
    final radius = widget.radius ?? style.radiusMedium;
    if (!style.isBrutalist) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      );
    }

    final translation = style.translationFor(
      hovered: _hovered,
      pressed: _pressed,
    );
    final reserveX = style.shadowOffset.dx.clamp(0, double.infinity);
    final reserveY = style.shadowOffset.dy.clamp(0, double.infinity);

    return Padding(
      padding: EdgeInsets.only(right: reserveX + 1, bottom: reserveY + 1),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(widget.enabled),
        onExit: (_) => _setHovered(false),
        child: Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: AnimatedContainer(
            duration: NodeQlNeoBrutalism.interactionDuration,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(
              translation.dx,
              translation.dy,
              0,
            ),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: style.hardShadowFor(
                hovered: _hovered,
                pressed: _pressed,
                disabled: !widget.enabled,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
