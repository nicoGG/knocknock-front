import 'package:flutter/material.dart';

/// A soft golden reflection behind the content, with a pause between passes.
class GoldenSweep extends StatefulWidget {
  const GoldenSweep({required this.child, super.key});

  final Widget child;

  @override
  State<GoldenSweep> createState() => _GoldenSweepState();
}

class _GoldenSweepState extends State<GoldenSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _GoldenSweepPainter(_controller)),
          ),
        ),
      ),
      widget.child,
    ],
  );
}

class _GoldenSweepPainter extends CustomPainter {
  _GoldenSweepPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value;
    if (phase < .08 || phase > .67 || size.isEmpty) return;
    final progress = Curves.easeInOutSine.transform((phase - .08) / .59);
    final bandWidth = size.width * .45;
    final center = -bandWidth + (size.width + bandWidth * 2) * progress;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(22)));
    canvas.drawRect(
      rect,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0x00FFD56A),
                Color(0x18FFD56A),
                Color(0x48FFE5A0),
                Color(0x18FFD56A),
                Color(0x00FFD56A),
              ],
              stops: const [0, .3, .5, .7, 1],
            ).createShader(
              Rect.fromLTWH(center - bandWidth / 2, 0, bandWidth, size.height),
            ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoldenSweepPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
