import 'package:flutter/material.dart';
import 'package:nodeql/core/theme/theme_controller.dart';

/// Adds the physical hover/press behavior that Material button themes cannot
/// express: a crisp zero-blur shadow grows on hover and collapses as the
/// control moves into it on press.
///
/// The wrapper is visually inert for non-brutalist themes, so it can be used
/// around high-value desktop actions without branching at every call site.
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
    if (!style.isBrutalist) return widget.child;

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
              borderRadius: BorderRadius.circular(
                widget.radius ?? style.radiusMedium,
              ),
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
