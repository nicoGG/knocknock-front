import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decorative motion stays behind content and never intercepts card gestures.
/// It settles after entry instead of keeping every card's ticker running.
class AnimatedCardBackdrop extends StatelessWidget {
  const AnimatedCardBackdrop({
    required this.icon,
    required this.color,
    required this.child,
    this.animate = true,
    super.key,
  });
  final IconData icon;
  final Color color;
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context) || !animate;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: ClipRect(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 1800),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, _) => Stack(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Align(
                            alignment: [
                              const Alignment(.95, -.85),
                              const Alignment(-.9, .8),
                              const Alignment(.75, .95),
                            ][i],
                            child: Transform.translate(
                              offset: Offset(
                                reduced
                                    ? 0
                                    : math.sin(progress * math.pi) *
                                          (i.isEven ? 10 : -8),
                                reduced ? 0 : (1 - progress) * (12 + i * 4),
                              ),
                              child: Transform.rotate(
                                angle:
                                    (i.isEven ? -.18 : .16) +
                                    (reduced ? 0 : (1 - progress) * .12),
                                child: Icon(
                                  icon,
                                  size: i == 0 ? 62 : 34,
                                  color: color.withValues(
                                    alpha: i == 0 ? .09 : .055,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
