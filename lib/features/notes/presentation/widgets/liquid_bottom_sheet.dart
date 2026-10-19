import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<T?> showLiquidBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = true,
  bool useSafeArea = false,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  constraints: constraints,
  backgroundColor: Colors.transparent,
  elevation: 0,
  showDragHandle: false,
  builder: (context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.vertical(top: Radius.circular(32));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          key: const ValueKey('liquid-bottom-sheet-surface'),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.55),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surface.withValues(alpha: isDark ? 0.78 : 0.86),
                colors.surfaceContainerHigh.withValues(
                  alpha: isDark ? 0.64 : 0.72,
                ),
                colors.surface.withValues(alpha: isDark ? 0.84 : 0.9),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDragHandle)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 22),
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              Flexible(child: builder(context)),
            ],
          ),
        ),
      ),
    );
  },
);
