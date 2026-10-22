import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    required this.child,
    this.axis = Axis.vertical,
    this.fadeExtent = 24,
    this.overlayColor,
    super.key,
  });

  final Widget child;
  final Axis axis;
  final double fadeExtent;
  final Color? overlayColor;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  double _hiddenAbove = 0;
  double _hiddenBelow = 0;
  double _pendingAbove = 0;
  double _pendingBelow = 0;
  bool _metricsUpdateScheduled = false;

  void _updateMetrics(ScrollMetrics metrics) {
    final above = metrics.extentBefore.clamp(0.0, widget.fadeExtent);
    final below = metrics.extentAfter.clamp(0.0, widget.fadeExtent);
    _pendingAbove = above;
    _pendingBelow = below;
    if (_metricsUpdateScheduled ||
        (above == _hiddenAbove && below == _hiddenBelow)) {
      return;
    }
    _metricsUpdateScheduled = true;
    // Keyboard resizing can end an active drag during performLayout. Defer
    // rebuilding until layout/paint finishes and keep only the latest metrics.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _metricsUpdateScheduled = false;
      if (!mounted ||
          (_pendingAbove == _hiddenAbove && _pendingBelow == _hiddenBelow)) {
        return;
      }
      setState(() {
        _hiddenAbove = _pendingAbove;
        _hiddenBelow = _pendingBelow;
      });
    });
    SchedulerBinding.instance.ensureVisualUpdate();
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
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final extent = widget.axis == Axis.vertical
                    ? bounds.height
                    : bounds.width;
                final fade = extent > 0
                    ? (widget.fadeExtent / extent).clamp(0.0, 0.5)
                    : 0.0;
                return LinearGradient(
                  begin: widget.axis == Axis.vertical
                      ? Alignment.topCenter
                      : Alignment.centerLeft,
                  end: widget.axis == Axis.vertical
                      ? Alignment.bottomCenter
                      : Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(
                      alpha: 1 - _hiddenAbove / widget.fadeExtent,
                    ),
                    Colors.white,
                    Colors.white,
                    Colors.white.withValues(
                      alpha: 1 - _hiddenBelow / widget.fadeExtent,
                    ),
                  ],
                  stops: [0, fade, 1 - fade, 1],
                ).createShader(bounds);
              },
              child: widget.child,
            ),
            if (widget.overlayColor != null &&
                widget.axis == Axis.vertical) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: widget.fadeExtent,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          widget.overlayColor!.withValues(
                            alpha: _hiddenAbove / widget.fadeExtent,
                          ),
                          widget.overlayColor!.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: widget.fadeExtent,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          widget.overlayColor!.withValues(
                            alpha: _hiddenBelow / widget.fadeExtent,
                          ),
                          widget.overlayColor!.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
