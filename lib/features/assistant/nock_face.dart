import 'package:flutter/material.dart';

enum NockExpression { wink, curious, delighted, surprised }

/// A little paper companion with the coral pin from the NockNock app icon.
class NockFace extends StatelessWidget {
  const NockFace({
    super.key,
    this.size = 36,
    this.expression = NockExpression.wink,
    this.amount = 0,
  });
  final NockExpression expression;
  final double amount;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _NockPainter(Theme.of(context).brightness, expression, amount),
  );
}

class _NockPainter extends CustomPainter {
  const _NockPainter(this.brightness, this.expression, this.amount);
  final NockExpression expression;
  final double amount;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);

    // A slightly bowed sheet and a turned-up corner give Nock a silhouette
    // that remains recognizable even on a busy board.
    final paper = Path()
      ..moveTo(12, 14)
      ..cubicTo(18, 10, 31, 12, 42, 9)
      ..cubicTo(50, 7, 54, 12, 53, 19)
      ..cubicTo(52, 30, 53, 42, 57, 48)
      ..cubicTo(59, 51, 55, 54, 51, 55)
      ..cubicTo(38, 57, 24, 60, 12, 56)
      ..cubicTo(8, 55, 7, 53, 9, 49)
      ..cubicTo(13, 41, 8, 28, 8, 21)
      ..quadraticBezierTo(8, 16, 12, 14)
      ..close();
    final brush = Paint()..isAntiAlias = true;
    canvas.drawShadow(paper, const Color(0x99362457), 3, false);
    canvas.drawPath(
      paper,
      brush
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeJoin = StrokeJoin.round
        ..color = brightness == Brightness.dark
            ? const Color(0xFFDBCEFC)
            : const Color(0xFF716184),
    );
    canvas.drawPath(
      paper,
      brush
        ..style = PaintingStyle.fill
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF1), Color(0xFFFFEFE9), Color(0xFFD7BDF7)],
          stops: [0, .55, 1],
        ).createShader(const Rect.fromLTRB(8, 9, 56, 57)),
    );
    brush.shader = null;
    canvas.drawPath(
      Path()
        ..moveTo(9, 51)
        ..quadraticBezierTo(12, 46, 12, 42)
        ..quadraticBezierTo(13, 49, 20, 54)
        ..quadraticBezierTo(12, 55, 9, 53)
        ..close(),
      brush..color = const Color(0xFFE2C9E9),
    );

    // Face in the same deep indigo as the two notes in the brand mark.
    canvas.save();
    canvas.translate(30, 34);
    canvas.rotate(-.07);
    brush.color = const Color(0xFF332061);
    for (final x in [-8.0, 8.0]) {
      final blink = switch (expression) {
        NockExpression.wink when x < 0 => amount,
        NockExpression.delighted => amount,
        _ => 0.0,
      };
      final look = expression == NockExpression.curious ? amount : 0.0;
      final center = Offset(x + 1.8 * look, -2 - (x > 0 ? 2.8 : .3) * look);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: 5.8 + blink,
          height: 8.2 - 6.4 * blink,
        ),
        brush,
      );
      if (blink > 0) {
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - 2.8, center.dy)
            ..quadraticBezierTo(
              center.dx,
              center.dy - 3 * blink,
              center.dx + 2.8,
              center.dy,
            ),
          Paint()
            ..color = brush.color
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8 * blink,
        );
      }
    }
    canvas.save();
    if (expression == NockExpression.surprised) {
      // Morph the smile into an open "o" using the same outline.
      canvas.translate(0, 8);
      canvas.scale(1 - .45 * amount, 1 + .48 * amount);
      canvas.translate(0, -8);
    }
    final grin = expression == NockExpression.delighted ? amount * 2 : 0.0;
    canvas.drawPath(
      Path()
        ..moveTo(-4.5 - grin, 5)
        ..quadraticBezierTo(0, 8, 4.7 + grin, 4.8)
        ..cubicTo(5.7 + grin, 4.1, 6.1 + grin, 5.3, 5.4 + grin, 6.9)
        ..cubicTo(3.3, 12.2 + grin, -3.4, 12.6 + grin, -5.4 - grin, 7)
        ..quadraticBezierTo(-6 - grin, 4.9, -4.5 - grin, 5)
        ..close(),
      brush,
    );
    canvas.restore();
    brush.color = const Color(0xFFFFB7A6);
    for (final x in [-12.5, 12.5]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 3), width: 5.8, height: 2.8),
        brush,
      );
    }
    canvas.restore();

    // A short pin and a round coral head remain distinct at chat-avatar size.
    canvas.drawLine(
      const Offset(49, 12),
      const Offset(45.5, 18),
      brush
        ..color = const Color(0xFF6D4C85)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
    const pin = Offset(51, 9);
    canvas.drawCircle(
      pin,
      6.9,
      brush
        ..color = brightness == Brightness.dark
            ? const Color(0xFFFFDFBD)
            : const Color(0xFFA84342),
    );
    canvas.drawCircle(
      pin,
      5.9,
      brush
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.5),
          radius: .95,
          colors: [Color(0xFFFFDE97), Color(0xFFFF914F), Color(0xFFF15C42)],
          stops: [0, .48, 1],
        ).createShader(Rect.fromCircle(center: pin, radius: 5.9)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NockPainter old) =>
      old.brightness != brightness ||
      old.expression != expression ||
      old.amount != amount;
}
