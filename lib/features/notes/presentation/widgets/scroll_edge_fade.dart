import 'package:flutter/material.dart';

class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({required this.child, super.key});

  final Widget child;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  double _hiddenAbove = 0;
  double _hiddenBelow = 0;

  void _updateMetrics(ScrollMetrics metrics) {
    final above = metrics.extentBefore.clamp(0.0, 24.0);
    final below = metrics.extentAfter.clamp(0.0, 24.0);
    if (above == _hiddenAbove && below == _hiddenBelow) return;
    setState(() {
      _hiddenAbove = above;
      _hiddenBelow = below;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _updateMetrics(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _updateMetrics(notification.metrics);
          return false;
        },
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final fade = bounds.height > 0
                ? (24 / bounds.height).clamp(0.0, 0.5)
                : 0.0;
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 1 - _hiddenAbove / 24),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 1 - _hiddenBelow / 24),
              ],
              stops: [0, fade, 1 - fade, 1],
            ).createShader(bounds);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
