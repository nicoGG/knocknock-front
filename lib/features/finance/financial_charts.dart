import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_style.dart';

/// Small groups remain visible while long breakdowns retain their full total.
Map<String, int> compactExpenseGroups(Map<String, int> values) {
  final sorted = values.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length <= 7) return Map.fromEntries(sorted);
  final result = Map<String, int>.fromEntries(sorted.take(6));
  var other = 'Otros';
  while (result.containsKey(other)) {
    other = '$other ';
  }
  result[other] = sorted.skip(6).fold<int>(0, (sum, e) => sum + e.value);
  return result;
}

class FinancialExpenseChart extends StatefulWidget {
  const FinancialExpenseChart({
    required this.groups,
    required this.currency,
    required this.title,
    super.key,
  });
  final Map<String, int> groups;
  final String currency;
  final String title;
  @override
  State<FinancialExpenseChart> createState() => _FinancialExpenseChartState();
}

class _FinancialExpenseChartState extends State<FinancialExpenseChart> {
  String _type = 'donut';
  bool get _bars => _type == 'bars';
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final entries = compactExpenseGroups(widget.groups).entries.toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    final colors = Theme.of(context).colorScheme;
    final selected = entries.indexWhere((e) => e.key == _selected);
    final palette = [
      colors.primary,
      const Color(0xFF81B9AE),
      const Color(0xFFB8A1D9),
      const Color(0xFFDD9C83),
      const Color(0xFF8FAFD0),
      const Color(0xFFD5BD8A),
      const Color(0xFFA7ABA9),
    ];
    final maximum = entries.fold<int>(1, (v, e) => math.max(v, e.value));
    return FinancialSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: .035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in const [
                      ('donut', Icons.donut_large_rounded, 'Gráfico de dona'),
                      ('pie', Icons.pie_chart_rounded, 'Gráfico de torta'),
                      (
                        'bars',
                        Icons.horizontal_split_rounded,
                        'Gráfico de barras',
                      ),
                      (
                        'columns',
                        Icons.bar_chart_rounded,
                        'Gráfico de columnas',
                      ),
                    ])
                      Semantics(
                        selected: _type == option.$1,
                        child: AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: _type == option.$1
                                ? colors.primary.withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: IconButton(
                            tooltip: option.$3,
                            onPressed: () => setState(() => _type = option.$1),
                            icon: Icon(option.$2, size: 19),
                            style: IconButton.styleFrom(
                              foregroundColor: _type == option.$1
                                  ? colors.primary
                                  : colors.onSurface.withValues(alpha: .55),
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.all(10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Sin gastos en este período.'),
            )
          else ...[
            if (_type == 'columns')
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected == i,
                          label:
                              '${entries[i].key}: ${FinancialEntry.formatAmount(entries[i].value, widget.currency)}',
                          child: InkWell(
                            onTap: () => setState(
                              () => _selected = selected == i
                                  ? null
                                  : entries[i].key,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(entries[i].value * 100 / total).round()} %',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  TweenAnimationBuilder<double>(
                                    key: ValueKey(
                                      '${entries[i].key}-${entries[i].value}',
                                    ),
                                    tween: Tween(
                                      begin: 0,
                                      end: entries[i].value / maximum,
                                    ),
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 650),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, _) => Container(
                                      height: 130 * value + 2,
                                      width: 32,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(9),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            palette[i].withValues(
                                              alpha:
                                                  selected < 0 || selected == i
                                                  ? 1
                                                  : .35,
                                            ),
                                            palette[i].withValues(alpha: .25),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${i + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_type == 'donut' || _type == 'pie')
              SizedBox(
                height: 190,
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onTapUp: (details) {
                      final center = Offset(constraints.maxWidth / 2, 95);
                      final offset = details.localPosition - center;
                      if ((_type == 'donut' && offset.distance < 59) ||
                          offset.distance > 91) {
                        return;
                      }
                      var angle =
                          math.atan2(offset.dy, offset.dx) + math.pi / 2;
                      if (angle < 0) angle += 2 * math.pi;
                      var cumulative = 0.0;
                      for (var i = 0; i < entries.length; i++) {
                        cumulative += entries[i].value / total * 2 * math.pi;
                        if (angle <= cumulative) {
                          setState(() => _selected = entries[i].key);
                          break;
                        }
                      }
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ExpenseDonut(
                              entries.map((e) => e.value).toList(),
                              palette,
                              selected,
                              pie: _type == 'pie',
                            ),
                          ),
                        ),
                        if (_type == 'donut')
                          SizedBox(
                            width: 118,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  selected < 0
                                      ? 'Total'
                                      : '${(entries[selected].value * 100 / total).round()} %',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  FinancialEntry.formatAmount(
                                    selected < 0
                                        ? total
                                        : entries[selected].value,
                                    widget.currency,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < entries.length; i++)
              Semantics(
                selected: selected == i,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(
                    () => _selected = selected == i ? null : entries[i].key,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: selected == i
                          ? palette[i].withValues(alpha: .12)
                          : Colors.transparent,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette[i],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _type == 'columns'
                                    ? '${i + 1}. ${entries[i].key}'
                                    : entries[i].key,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(entries[i].value * 100 / total).round()} %',
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 17, top: 4),
                          child: Text(
                            FinancialEntry.formatAmount(
                              entries[i].value,
                              widget.currency,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (_bars) ...[
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: entries[i].value / maximum,
                              minHeight: 8,
                              color: palette[i],
                              backgroundColor: palette[i].withValues(
                                alpha: .12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Toca un segmento o una fila para destacar su importe.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseDonut extends CustomPainter {
  _ExpenseDonut(this.values, this.colors, this.selected, {this.pie = false});
  final bool pie;
  final List<int> values;
  final List<Color> colors;
  final int selected;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: pie ? 86 : 75,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      final paint = Paint()
        ..style = pie ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = (selected == i ? 28 : 22)
        ..color = colors[i].withValues(
          alpha: selected < 0 || selected == i ? 1 : .35,
        );
      final gap = math.min(.024, sweep * .1);
      final shifted = selected == i && pie
          ? rect.shift(
              Offset(math.cos(start + sweep / 2), math.sin(start + sweep / 2)) *
                  4,
            )
          : rect;
      canvas.drawArc(shifted, start + gap / 2, sweep - gap, pie, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _ExpenseDonut old) =>
      old.pie != pie ||
      old.selected != selected ||
      old.values.toString() != values.toString() ||
      old.colors.toString() != colors.toString();
}
