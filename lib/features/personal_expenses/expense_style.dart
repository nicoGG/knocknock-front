import 'package:flutter/material.dart';

import '../notes/presentation/widgets/scroll_edge_fade.dart';

class ExpenseSurface extends StatelessWidget {
  const ExpenseSurface({
    super.key,
    required this.child,
    this.highlighted = false,
    this.padding,
    this.margin,
  });
  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding ?? EdgeInsets.all(highlighted ? 24 : 18),
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: highlighted
              ? colors.primary.withValues(alpha: .22)
              : colors.outlineVariant.withValues(alpha: .35),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              colors.primary.withValues(alpha: highlighted ? .10 : .025),
              colors.surface,
            ),
            colors.surfaceContainerLow.withValues(alpha: dark ? .8 : .9),
          ],
        ),
      ),
      child: child,
    );
  }
}

class ExpenseBackground extends StatelessWidget {
  const ExpenseBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: colors.outlineVariant.withValues(alpha: .5),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .08, .65, 1],
          colors: [
            colors.surface,
            Color.alphaBlend(
              colors.primary.withValues(alpha: .07),
              colors.surface,
            ),
            colors.surface,
            Color.alphaBlend(
              colors.secondary.withValues(alpha: .04),
              colors.surface,
            ),
          ],
        ),
      ),
      child: Theme(
        data: theme.copyWith(
          dividerColor: Colors.transparent,
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: colors.surfaceContainerLow,
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: colors.primary, width: 1.5),
            ),
          ),
          chipTheme: theme.chipTheme.copyWith(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .4),
            ),
            backgroundColor: colors.surfaceContainerLow,
            selectedColor: colors.primary.withValues(alpha: .16),
          ),
          expansionTileTheme: theme.expansionTileTheme.copyWith(
            shape: const Border(),
            collapsedShape: const Border(),
          ),
        ),
        child: ScrollEdgeFade(
          fadeExtent: 44,
          overlayColor: colors.surface,
          child: child,
        ),
      ),
    );
  }
}

class ExpenseEyebrow extends StatelessWidget {
  const ExpenseEyebrow({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class ExpenseNotice extends StatelessWidget {
  const ExpenseNotice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
  });
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 17,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ),
    ],
  );
}

class ExpenseMetricGrid extends StatelessWidget {
  const ExpenseMetricGrid({super.key, required this.values});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth < 320 ||
              MediaQuery.textScalerOf(context).scale(14) > 19
          ? 1
          : 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final entry in values.entries)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 10) / columns,
              child: ExpenseSurface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      entry.value,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
