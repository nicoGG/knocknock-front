import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';

Future<T?> showLiquidSelection<T>({
  required BuildContext context,
  required String title,
  required List<DropdownMenuItem<T>> items,
  T? value,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog<T>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return LiquidAlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(100, MediaQuery.sizeOf(context).height * .55),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = item.value == value;
                return Semantics(
                  button: true,
                  enabled: item.enabled,
                  selected: selected,
                  child: Material(
                    color: selected
                        ? colors.primary.withValues(alpha: .16)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: selected
                            ? colors.primary.withValues(alpha: .38)
                            : colors.outline.withValues(alpha: .12),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: item.enabled
                          ? () => Navigator.pop(context, item.value)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: DefaultTextStyle.merge(
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                child: item.child,
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 10),
                              Icon(
                                Icons.check_circle_rounded,
                                color: colors.primary,
                                size: 21,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
  );
}

/// Form selector with the app's glass dialog, rounded options and solid icons.
class LiquidDropdownFormField<T> extends StatelessWidget {
  const LiquidDropdownFormField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = true,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(20);
    return FormField<T>(
      key: ValueKey(initialValue),
      initialValue: initialValue,
      enabled: onChanged != null,
      builder: (field) {
        final selected = items
            .where((item) => item.value == field.value)
            .firstOrNull;
        return Semantics(
          button: true,
          enabled: onChanged != null,
          child: InkWell(
            borderRadius: radius,
            onTap: onChanged == null
                ? null
                : () async {
                    final result = await showLiquidSelection<T>(
                      context: context,
                      title: decoration.labelText ?? 'Seleccionar',
                      items: items,
                      value: field.value,
                    );
                    if (!field.mounted || result == null) return;
                    field.didChange(result);
                    onChanged!(result);
                  },
            child: InputDecorator(
              isEmpty: selected == null,
              decoration: decoration.copyWith(
                enabled: onChanged != null,
                filled: true,
                fillColor: colors.surface.withValues(alpha: dark ? .28 : .34),
                border: OutlineInputBorder(borderRadius: radius),
                enabledBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: dark ? .22 : .48),
                  ),
                ),
                suffixIcon: const Icon(Icons.expand_more_rounded),
              ),
              child: selected?.child ?? const SizedBox(height: 24),
            ),
          ),
        );
      },
    );
  }
}
