import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedNoteCheckbox extends StatefulWidget {
  const AnimatedNoteCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.checkColor,
    this.visualDensity,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final Color activeColor;
  final Color checkColor;
  final VisualDensity? visualDensity;

  @override
  State<AnimatedNoteCheckbox> createState() => _AnimatedNoteCheckboxState();
}

class _AnimatedNoteCheckboxState extends State<AnimatedNoteCheckbox>
    with SingleTickerProviderStateMixin {
  static final _celebrations = Expando<OverlayEntry>();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _toggle(bool? value) {
    if (!widget.value && value == true) {
      HapticFeedback.lightImpact();
      if (!MediaQuery.disableAnimationsOf(context)) {
        _pulse.forward(from: 0);
        final overlay = Overlay.of(context, rootOverlay: true);
        final previous = _celebrations[overlay];
        if (previous != null) {
          previous.remove();
          previous.dispose();
        }
        late final OverlayEntry entry;
        entry = OverlayEntry(
          builder: (_) => _CompletionCelebration(
            onFinished: () {
              _celebrations[overlay] = null;
              entry.remove();
              entry.dispose();
            },
          ),
        );
        _celebrations[overlay] = entry;
        overlay.insert(entry);
      }
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, child) {
      final progress = _pulse.value;
      final wave = math.sin(progress * math.pi);
      return Transform.scale(
        scale: 1 + wave * .18,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              if (_pulse.isAnimating)
                BoxShadow(
                  color: widget.activeColor.withValues(alpha: wave * .24),
                  blurRadius: 12 * wave,
                  spreadRadius: 3 * wave,
                ),
            ],
          ),
          child: child,
        ),
      );
    },
    child: SizedBox.square(
      dimension: widget.visualDensity == null ? 48 : 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.value
                      ? null
                      : widget.activeColor.withValues(alpha: .07),
                  gradient: widget.value
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: widget.activeColor.computeLuminance() > .5
                              ? [
                                  const Color(0xFFD2F4E5),
                                  const Color(0xFF91D6B7),
                                ]
                              : [
                                  const Color(0xFF398568),
                                  const Color(0xFF235C48),
                                ],
                        )
                      : null,
                  border: Border.all(
                    color: widget.value
                        ? widget.activeColor.withValues(alpha: .3)
                        : widget.activeColor.withValues(alpha: .65),
                    width: 1.5,
                  ),
                  boxShadow: widget.value
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF235C48,
                            ).withValues(alpha: .22),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: widget.value
                      ? Icon(
                          Icons.check_rounded,
                          key: const ValueKey('completed-check'),
                          size: 19,
                          color: widget.activeColor.computeLuminance() > .5
                              ? const Color(0xFF194A38)
                              : const Color(0xFFF1FFF8),
                        )
                      : const SizedBox.shrink(key: ValueKey('pending-check')),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Checkbox(
              value: widget.value,
              onChanged: _toggle,
              fillColor: const WidgetStatePropertyAll(Colors.transparent),
              checkColor: Colors.transparent,
              side: BorderSide.none,
              shape: const CircleBorder(),
              visualDensity: widget.visualDensity,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CompletionCelebration extends StatefulWidget {
  const _CompletionCelebration({required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<_CompletionCelebration> createState() => _CompletionCelebrationState();
}

class _CompletionCelebrationState extends State<_CompletionCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3000),
        )
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onFinished();
        })
        ..forward();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('note-completion-celebration'),
            painter: _FloatingCompletionPainter(_animation),
          ),
        ),
      ),
    ),
  );
}

class _FloatingCompletionPainter extends CustomPainter {
  _FloatingCompletionPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;
  final List<_CompletionParticle> _particles = _createParticles();
  final Paint _paint = Paint();
  static const colors = [
    Color(0xFFFFC078),
    Color(0xFFB5E6D3),
    Color(0xFFE7BBFF),
    Color(0xFFFFA9BB),
    Color(0xFFAFD8FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in _particles) {
      final x = particle.x * size.width;
      final delay = particle.delay;
      final speed = particle.speed;
      final phase = particle.phase;
      final sway = particle.sway;
      final frequency = particle.frequency;
      final direction = particle.direction;
      final spin = particle.spin;
      final acceleration = particle.acceleration;
      final bob = particle.bob;
      final progress = ((animation.value - delay) / (1 - delay)).clamp(
        0.0,
        1.0,
      );
      if (progress <= 0) continue;
      final opacity = (math.sin(math.pi * progress) * .85).clamp(0.0, 1.0);
      final rise = math.pow(progress, acceleration).toDouble();
      final y =
          size.height * (1.06 - rise * speed * 1.25) +
          math.sin(progress * math.pi * frequency * 2 + phase) * bob;
      final drift =
          math.sin(progress * math.pi * frequency * 2 + phase) * sway +
          direction * progress * sway * .5;
      canvas.save();
      canvas.translate(x + drift, y);
      canvas.rotate(phase + progress * spin);
      _paint.color = particle.color.withValues(alpha: opacity);
      canvas.drawPath(particle.shape, _paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FloatingCompletionPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _CompletionParticle {
  _CompletionParticle(math.Random random, int index)
    : x = random.nextDouble(),
      delay = random.nextDouble() * .22,
      speed = .65 + random.nextDouble() * .6,
      phase = random.nextDouble() * math.pi * 2,
      sway = 24 + random.nextDouble() * 64,
      frequency = .7 + random.nextDouble() * 1.8,
      direction = random.nextBool() ? 1 : -1,
      spin = (random.nextBool() ? 1 : -1) * (1 + random.nextDouble() * 4),
      acceleration = .85 + random.nextDouble() * .45,
      bob = 6 + random.nextDouble() * 14,
      color = _FloatingCompletionPainter.colors[index % 5] {
    final radius = 10 + random.nextDouble() * 10;
    if (index % 3 == 0) {
      for (var point = 0; point < 10; point++) {
        final angle = point * math.pi / 5 - math.pi / 2;
        final length = point.isEven ? radius : radius * .45;
        final dx = math.cos(angle) * length;
        final dy = math.sin(angle) * length;
        if (point == 0) {
          shape.moveTo(dx, dy);
        } else {
          shape.lineTo(dx, dy);
        }
      }
      shape.close();
    } else if (index % 3 == 1) {
      shape.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius,
            height: radius * 1.6,
          ),
          const Radius.circular(2),
        ),
      );
    } else {
      shape.addOval(Rect.fromCircle(center: Offset.zero, radius: radius * .6));
    }
  }
  final double x, delay, speed, phase, sway, frequency, spin, acceleration, bob;
  final int direction;
  final Color color;
  final Path shape = Path();
}

List<_CompletionParticle> _createParticles() {
  final random = math.Random();
  return List.generate(42, (index) => _CompletionParticle(random, index));
}
