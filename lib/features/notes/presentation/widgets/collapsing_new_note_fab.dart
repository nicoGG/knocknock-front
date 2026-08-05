import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CollapsingNewNoteFab extends StatelessWidget {
  const CollapsingNewNoteFab({
    required this.scrollProgress,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final ValueListenable<double> scrollProgress;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: scrollProgress,
    builder: (context, rawProgress, _) {
      final normalized = rawProgress.clamp(0.0, 1.0);
      final progress = MediaQuery.disableAnimationsOf(context)
          ? (normalized < 0.5 ? 0.0 : 1.0)
          : Curves.easeInOutCubic.transform(normalized);
      final expandedProgress = 1 - progress;

      return FloatingActionButton.extended(
        tooltip: 'Nueva nota',
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16 + (12 * progress)),
        ),
        extendedPadding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16 + (4 * expandedProgress),
        ),
        extendedIconLabelSpacing: 8 * expandedProgress,
        icon: Transform.rotate(
          angle: 0.12 * progress,
          child: Transform.scale(
            scale: 1 + (0.08 * progress),
            child: const Icon(Icons.add_rounded),
          ),
        ),
        label: ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: expandedProgress,
            child: Opacity(
              opacity: expandedProgress,
              child: Transform.translate(
                offset: Offset(8 * progress, 0),
                child: const Text('Nueva nota'),
              ),
            ),
          ),
        ),
      );
    },
  );
}
