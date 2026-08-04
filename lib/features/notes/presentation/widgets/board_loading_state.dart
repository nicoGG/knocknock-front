import 'package:flutter/material.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';

class BoardLoadingState extends StatefulWidget {
  const BoardLoadingState({super.key});

  @override
  State<BoardLoadingState> createState() => _BoardLoadingStateState();
}

class _BoardLoadingStateState extends State<BoardLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.42;
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
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando tus notas',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Stack(
          key: const ValueKey('board-loading-state'),
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 720;
                  final itemCount = isCompact ? 4 : 6;
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 92),
                    gridDelegate: isCompact
                        ? const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.86,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          )
                        : const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 330,
                            mainAxisExtent: 270,
                            crossAxisSpacing: 22,
                            mainAxisSpacing: 22,
                          ),
                    itemCount: itemCount,
                    itemBuilder: (context, index) => _LoadingPostIt(
                      index: index,
                      progress: _controller.value,
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) =>
                      _LoadingLabel(progress: _controller.value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingPostIt extends StatelessWidget {
  const _LoadingPostIt({required this.index, required this.progress});

  static const _colors = [
    NoteColor.yellow,
    NoteColor.pink,
    NoteColor.blue,
    NoteColor.green,
    NoteColor.purple,
  ];

  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final baseColor = NotePalette.color(_colors[index % _colors.length]);
    final phase = (progress + (index * 0.11)) % 1;
    final shimmerStart = -2.2 + (phase * 4.4);
    final entrance = Curves.easeOutCubic.transform(
      ((progress * 4.2) - (index * 0.14)).clamp(0, 1),
    );
    final lineColor = AppTheme.ink.withValues(alpha: 0.12);

    return Opacity(
      opacity: 0.38 + (entrance * 0.62),
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - entrance)),
        child: Transform.scale(
          scale: 0.97 + (entrance * 0.03),
          alignment: Alignment.bottomCenter,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: DecoratedBox(
                  key: ValueKey('loading-note-$index'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment(shimmerStart, -1),
                      end: Alignment(shimmerStart + 1.15, 1),
                      colors: [
                        baseColor.withValues(alpha: 0.76),
                        Color.lerp(baseColor, Colors.white, 0.3)!,
                        baseColor.withValues(alpha: 0.82),
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.ink.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final dense = constraints.maxHeight < 170;
                      return Padding(
                        padding: dense
                            ? const EdgeInsets.fromLTRB(14, 14, 12, 11)
                            : const EdgeInsets.fromLTRB(20, 20, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LoadingLine(
                              widthFactor: index.isEven ? 0.7 : 0.84,
                              height: dense ? 11 : 15,
                              color: lineColor,
                            ),
                            SizedBox(height: dense ? 7 : 10),
                            _LoadingLine(
                              widthFactor: index.isEven ? 0.46 : 0.58,
                              height: dense ? 11 : 15,
                              color: lineColor,
                            ),
                            SizedBox(height: dense ? 14 : 25),
                            _LoadingLine(
                              widthFactor: 0.94,
                              height: dense ? 7 : 9,
                              color: lineColor,
                            ),
                            SizedBox(height: dense ? 7 : 9),
                            _LoadingLine(
                              widthFactor: index.isEven ? 0.78 : 0.88,
                              height: dense ? 7 : 9,
                              color: lineColor,
                            ),
                            if (!dense) ...[
                              const SizedBox(height: 9),
                              _LoadingLine(
                                widthFactor: 0.56,
                                height: 9,
                                color: lineColor,
                              ),
                            ],
                            const Spacer(),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: dense ? 8 : 11,
                                  backgroundColor: lineColor,
                                ),
                                SizedBox(width: dense ? 6 : 8),
                                Expanded(
                                  child: _LoadingLine(
                                    widthFactor: 0.5,
                                    height: dense ? 7 : 8,
                                    color: lineColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: baseColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: lineColor),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.ink.withValues(alpha: 0.12),
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.push_pin_outlined,
                    size: 15,
                    color: AppTheme.ink.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({
    required this.widthFactor,
    required this.height,
    required this.color,
  });

  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulse = 1 - (((progress * 2) - 1).abs());
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.ink.withValues(alpha: 0.1),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.88 + (pulse * 0.12),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.accent.withValues(alpha: 0.72 + (pulse * 0.28)),
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                'Preparando tus notas…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.76),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
