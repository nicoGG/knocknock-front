import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nocknock/features/finance/list_configuration.dart';

abstract final class FinancialStyle {
  static IconData typeIcon(NoteListType type) => switch (type) {
    NoteListType.normal => Icons.sticky_note_2_outlined,
    NoteListType.expenses => Icons.receipt_long_rounded,
    NoteListType.quotations => Icons.request_quote_rounded,
    NoteListType.receivables => Icons.person_add_alt_1_rounded,
    NoteListType.custom => Icons.tune_rounded,
  };
  static IconData currencyIcon(String currency) => switch (currency) {
    'USD' => Icons.attach_money_rounded,
    'EUR' => Icons.euro_rounded,
    _ => Icons.monetization_on_outlined,
  };
  static String currencyLabel(String currency) => switch (currency) {
    'USD' => 'USD · Dólar estadounidense',
    'EUR' => 'EUR · Euro',
    _ => 'CLP · Peso chileno',
  };
  static IconData statusIcon(String status) => switch (status) {
    'paid' => Icons.check_circle_outline_rounded,
    'accepted' => Icons.task_alt_rounded,
    'rejected' => Icons.cancel_outlined,
    _ => Icons.schedule_rounded,
  };
}

class FinancialOptionLabel extends StatelessWidget {
  const FinancialOptionLabel({
    required this.icon,
    required this.label,
    super.key,
  });
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class FinancialIconBadge extends StatelessWidget {
  const FinancialIconBadge({required this.icon, this.size = 44, super.key});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(size * .32),
        border: Border.all(color: colors.primary.withValues(alpha: .14)),
      ),
      child: Icon(icon, size: size * .52, color: colors.primary),
    );
  }
}

/// Uses the same translucent surfaces, theme colors and rounded corners as
/// the board's sheets, menus and settings cards.
class FinancialSurface extends StatelessWidget {
  const FinancialSurface({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? .16 : .56),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surface.withValues(alpha: dark ? .76 : .84),
                  colors.surfaceContainerHigh.withValues(
                    alpha: dark ? .60 : .66,
                  ),
                ],
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
