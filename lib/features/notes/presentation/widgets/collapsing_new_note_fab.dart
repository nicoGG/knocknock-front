import 'dart:ui' as ui;

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
      final colorScheme = Theme.of(context).colorScheme;
      final normalized = rawProgress.clamp(0.0, 1.0);
      final progress = MediaQuery.disableAnimationsOf(context)
          ? (normalized < 0.5 ? 0.0 : 1.0)
          : Curves.easeInOutCubic.transform(normalized);
      final expandedProgress = 1 - progress;
      final radius = BorderRadius.circular(22 + (8 * progress));

      return Semantics(
        button: true,
        enabled: onPressed != null,
        label: 'Nueva nota',
        child: Tooltip(
          message: 'Nueva nota',
          excludeFromSemantics: true,
          child: _GlassNewNoteSurface(
            keyPrefix: 'new-note-fab',
            backgroundColor: backgroundColor ?? colorScheme.primary,
            foregroundColor: foregroundColor ?? colorScheme.onPrimary,
            borderRadius: radius,
            onPressed: onPressed,
            padding: EdgeInsetsDirectional.only(
              start: 16,
              end: 16 + (4 * expandedProgress),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: 0.12 * progress,
                  child: Transform.scale(
                    scale: 1 + (0.08 * progress),
                    child: const Icon(Icons.add_rounded),
                  ),
                ),
                SizedBox(width: 8 * expandedProgress),
                ClipRect(
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
              ],
            ),
          ),
        ),
      );
    },
  );
}

class GlassNewNoteButton extends StatelessWidget {
  const GlassNewNoteButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    super.key,
  });

  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: 'Nueva nota',
    child: Tooltip(
      message: 'Nueva nota',
      excludeFromSemantics: true,
      child: _GlassNewNoteSurface(
        keyPrefix: 'new-note-button',
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        borderRadius: BorderRadius.circular(22),
        onPressed: onPressed,
        minHeight: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded),
            SizedBox(width: 8),
            Text('Nueva nota'),
          ],
        ),
      ),
    ),
  );
}

class _GlassNewNoteSurface extends StatelessWidget {
  const _GlassNewNoteSurface({
    required this.keyPrefix,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderRadius,
    required this.onPressed,
    required this.padding,
    required this.child,
    this.minHeight = 56,
  });

  final String keyPrefix;
  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;
    final contentColor = enabled
        ? foregroundColor
        : foregroundColor.withValues(alpha: 0.55);
    final strongTint = backgroundColor.withValues(
      alpha: enabled ? (isDark ? 0.66 : 0.72) : 0.34,
    );
    final softTint = backgroundColor.withValues(
      alpha: enabled ? (isDark ? 0.44 : 0.5) : 0.24,
    );
    final useBackdropBlur =
        Theme.of(context).platform != TargetPlatform.android;
    final surface = Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          SizedBox(
            height: minHeight,
            child: Ink(
              key: ValueKey('$keyPrefix-glass-surface'),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: isDark ? 0.1 : 0.2),
                      strongTint,
                    ),
                    softTint,
                  ],
                ),
              ),
              child: InkWell(
                onTap: onPressed,
                enableFeedback: false,
                borderRadius: borderRadius,
                child: Padding(
                  padding: padding,
                  child: IconTheme(
                    data: IconThemeData(color: contentColor),
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: contentColor,
                        fontWeight: FontWeight.w700,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: enabled
                          ? (isDark ? 0.28 : 0.46)
                          : (isDark ? 0.14 : 0.24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(
              alpha: enabled ? (isDark ? 0.26 : 0.3) : 0.12,
            ),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.2),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: useBackdropBlur
            ? BackdropFilter(
                key: ValueKey('$keyPrefix-glass-blur'),
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: surface,
              )
            : KeyedSubtree(
                key: ValueKey('$keyPrefix-glass-blur'),
                child: surface,
              ),
      ),
    );
  }
}
