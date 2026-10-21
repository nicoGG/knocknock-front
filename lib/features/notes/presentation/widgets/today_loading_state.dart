import 'package:flutter/material.dart';

/// Keeps the shape of Today visible while its lists are loading.
class TodayLoadingState extends StatefulWidget {
  const TodayLoadingState({required this.horizontalPadding, super.key});

  final double horizontalPadding;

  @override
  State<TodayLoadingState> createState() => _TodayLoadingStateState();
}

class _TodayLoadingStateState extends State<TodayLoadingState>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    lowerBound: 0.45,
    upperBound: 0.8,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.65;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    Widget line(double width, {double height = 12}) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: width,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
    return Semantics(
      label: 'Cargando tu día',
      liveRegion: true,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Opacity(
              opacity: _controller.value,
              child: ListView(
                key: const ValueKey('today-loading-state'),
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  widget.horizontalPadding,
                  12,
                  widget.horizontalPadding,
                  104,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: colors.onSurface.withValues(
                          alpha: dark ? 0.12 : 0.08,
                        ),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.surfaceContainerHigh,
                          colors.surface.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (scale < 1.4) ...[
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.wb_sunny_rounded,
                                  color: colors.primary.withValues(alpha: 0.55),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  line(0.8),
                                  const SizedBox(height: 12),
                                  line(
                                    0.95,
                                    height: 22 * scale.clamp(1.0, 2.0),
                                  ),
                                  const SizedBox(height: 10),
                                  line(0.85),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        line(0.7),
                        const SizedBox(height: 10),
                        line(1, height: 5),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final width in [72.0, 100.0, 120.0])
                        Container(
                          width: width,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  line(0.42, height: 16),
                  const SizedBox(height: 18),
                  for (final tint in [
                    colors.primary,
                    colors.tertiary,
                    colors.secondary,
                  ]) ...[
                    Container(
                      height: 88 + 100 * (scale - 1).clamp(0.0, 1.0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          tint.withValues(alpha: dark ? 0.18 : 0.12),
                          colors.surfaceContainerHigh,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                line(0.78, height: 15),
                                const SizedBox(height: 10),
                                line(0.95),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
