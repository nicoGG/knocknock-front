import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class LiquidAlertDialog extends AlertDialog {
  const LiquidAlertDialog({
    super.key,
    super.icon,
    super.iconPadding,
    super.title,
    super.titlePadding,
    super.content,
    super.contentPadding,
    super.actions,
    super.actionsPadding,
    super.actionsAlignment,
    super.insetPadding,
    super.scrollable,
  });

  @override
  Widget build(BuildContext context) {
    final dialog = super.build(context) as Dialog;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(30);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: dialog.insetPadding,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      semanticsRole: dialog.semanticsRole,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            key: const ValueKey('liquid-alert-dialog-surface'),
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
            child: dialog.child,
          ),
        ),
      ),
    );
  }
}
