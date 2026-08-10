import 'dart:math' as math;

import 'package:flutter/material.dart';

class AmbientPageBackground extends StatelessWidget {
  const AmbientPageBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPageBackgroundPainter(
            colorScheme: Theme.of(context).colorScheme,
            brightness: Theme.of(context).brightness,
          ),
        ),
      ),
    );
  }
}

class _AmbientPageBackgroundPainter extends CustomPainter {
  const _AmbientPageBackgroundPainter({
    required this.colorScheme,
    required this.brightness,
  });

  final ColorScheme colorScheme;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final isDark = brightness == Brightness.dark;
    final baseTop = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.09 : 0.06),
      colorScheme.surface,
    );
    final baseBottom = Color.alphaBlend(
      colorScheme.tertiary.withValues(alpha: isDark ? 0.065 : 0.04),
      colorScheme.surface,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseTop, colorScheme.surface, baseBottom],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );

    _paintGlow(
      canvas,
      center: Offset(size.width * 0.12, size.height * 0.13),
      radius: math.min(size.width * 0.82, 430),
      color: colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
    );
    _paintGlow(
      canvas,
      center: Offset(size.width * 0.94, size.height * 0.48),
      radius: math.min(size.width * 0.72, 390),
      color: colorScheme.tertiary.withValues(alpha: isDark ? 0.14 : 0.1),
    );
    _paintGlow(
      canvas,
      center: Offset(size.width * 0.28, size.height * 0.92),
      radius: math.min(size.width * 0.76, 410),
      color: colorScheme.secondary.withValues(alpha: isDark ? 0.1 : 0.075),
    );

    final ribbon = Path()
      ..moveTo(-size.width * 0.2, size.height * 0.27)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.19,
        size.width * 0.66,
        size.height * 0.38,
        size.width * 1.18,
        size.height * 0.27,
      );
    canvas.drawPath(
      ribbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = colorScheme.primary.withValues(alpha: isDark ? 0.12 : 0.08),
    );
  }

  void _paintGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientPageBackgroundPainter oldDelegate) =>
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.brightness != brightness;
}
