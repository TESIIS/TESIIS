import 'package:flutter/material.dart';

enum FadeSide { left, right }

/// A gradient mask that fades a horizontally-scrolling list's edge into the
/// surrounding surface colour, hinting that there's more to scroll to.
///
/// Must be used inside a `Stack`. Replaces two near-identical `Positioned` +
/// `Container` blocks that used to be duplicated for the left and right
/// edges of the filter chip bar.
class EdgeFadeOverlay extends StatelessWidget {
  const EdgeFadeOverlay({super.key, required this.side, this.width = 20});

  final FadeSide side;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isLeft = side == FadeSide.left;
    final color = Theme.of(context).colorScheme.surface;
    final rounded = const Radius.circular(12);

    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          width: width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [color, color.withValues(alpha: 0)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: isLeft ? rounded : Radius.zero,
              bottomLeft: isLeft ? rounded : Radius.zero,
              topRight: isLeft ? Radius.zero : rounded,
              bottomRight: isLeft ? Radius.zero : rounded,
            ),
          ),
        ),
      ),
    );
  }
}
