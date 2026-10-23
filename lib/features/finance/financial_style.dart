import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';
import 'package:nocknock/core/widgets/animated_card_backdrop.dart';

import 'dart:ui' as ui;

import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';

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
    this.backgroundIcon,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final IconData? backgroundIcon;
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
              child: backgroundIcon == null
                  ? Padding(padding: padding, child: child)
                  : AnimatedCardBackdrop(
                      icon: backgroundIcon!,
                      color: colors.primary,
                      child: Padding(padding: padding, child: child),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bounded, scrollable dialog using the same glass surfaces as finance boards.
/// Actions stay visible when the software keyboard reduces the available height.
class FinancialDialog extends StatelessWidget {
  const FinancialDialog({
    required this.title,
    required this.icon,
    required this.content,
    required this.actions,
    super.key,
  });
  final String title;
  final IconData icon;
  final Widget content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: FinancialSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FinancialIconBadge(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ScrollEdgeFade(
                child: SingleChildScrollView(
                  key: const ValueKey('financial-dialog-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: content,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Financial records retain the same paper backgrounds and shape as board notes.
class FinancialNoteSurface extends StatelessWidget {
  const FinancialNoteSurface({
    required this.note,
    required this.child,
    super.key,
  });
  final Note note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = note.category;
    final color = category == NoteCategory.general
        ? NotePalette.color(note.color)
        : NoteCategoryStyle.baseColor(category);
    final foreground = NoteCategoryStyle.foregroundColor(category);
    final asset = NoteCategoryStyle.assetPath(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            onSurface: foreground,
            onSurfaceVariant: foreground.withValues(alpha: .86),
          ),
          listTileTheme: theme.listTileTheme.copyWith(
            textColor: foreground,
            iconColor: foreground,
          ),
        ),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              image: asset == null
                  ? null
                  : DecorationImage(
                      image: AssetImage(asset),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: .32),
                        BlendMode.darken,
                      ),
                    ),
            ),
            child: AnimatedCardBackdrop(
              icon: NoteCategoryStyle.icon(category),
              color: foreground,
              animate: !note.isCompleted,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme-tinted action with the same glass language as the board controls.
class FinancialActionButton extends StatefulWidget {
  const FinancialActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.width,
    this.busy = false,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  final bool busy;
  @override
  State<FinancialActionButton> createState() => _FinancialActionButtonState();
}

class _FinancialActionButtonState extends State<FinancialActionButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final enabled = widget.onPressed != null;
    return AnimatedScale(
      scale: _pressed && enabled ? .97 : 1,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: SizedBox(
        width: widget.width,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.primary.withValues(alpha: .24)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary.withValues(alpha: .18),
                  colors.primary.withValues(alpha: .07),
                ],
              ),
            ),
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: duration,
                      child: widget.busy
                          ? SizedBox(
                              key: const ValueKey('busy'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary,
                              ),
                            )
                          : Icon(
                              widget.icon,
                              key: ValueKey(widget.icon),
                              size: 21,
                              color: colors.primary,
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: enabled
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinancialLiquidControl extends StatelessWidget {
  const FinancialLiquidControl({
    required this.child,
    this.selected = false,
    super.key,
  });
  final Widget child;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final radius = BorderRadius.circular(28);
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .10 : .04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          if (selected)
            BoxShadow(
              color: colors.primary.withValues(alpha: .12),
              blurRadius: 16,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: selected
                      ? .46
                      : dark
                      ? .22
                      : .6,
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: dark ? .12 : .40),
                    selected
                        ? colors.primary.withValues(alpha: .26)
                        : colors.surface.withValues(alpha: .32),
                  ),
                  selected
                      ? colors.primary.withValues(alpha: .14)
                      : colors.surface.withValues(alpha: .18),
                  Colors.white.withValues(alpha: dark ? .04 : .16),
                ],
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

class FinancialLiquidFilter extends StatelessWidget {
  const FinancialLiquidFilter({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    selected: selected,
    child: FinancialLiquidControl(
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FinancialEntryEntrance extends StatelessWidget {
  const FinancialEntryEntrance({
    required this.child,
    required this.index,
    super.key,
  });
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 560),
      curve: Interval(
        (index * .045).clamp(0, .27),
        1,
        curve: Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class FinancialPaymentProgress extends StatelessWidget {
  const FinancialPaymentProgress({required this.value, super.key});
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => Semantics(
        label: 'Proporción pagada',
        value: '${(progress * 100).round()} %',
        child: SizedBox(
          height: 12,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  if (progress > 0)
                    Container(
                      width: constraints.maxWidth * progress,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: [
                            colors.primary.withValues(alpha: .8),
                            colors.primary,
                            Color.lerp(colors.primary, Colors.white, .25)!,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: .32),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: colors.primary.withValues(alpha: .13),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinancialParticipantOption extends StatelessWidget {
  const FinancialParticipantOption({
    required this.name,
    required this.selected,
    required this.onPressed,
    this.photoUrl,
    super.key,
  });
  final String name;
  final String? photoUrl;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      child: FinancialLiquidControl(
        selected: selected,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: colors.primary.withValues(alpha: .14),
                  child: ClipOval(
                    child: photoUrl?.trim().isNotEmpty == true
                        ? Image.network(
                            photoUrl!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stack) =>
                                Center(child: Text(initial)),
                          )
                        : Text(initial),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
