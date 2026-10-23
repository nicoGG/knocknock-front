import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_amount_input.dart';
import 'package:nocknock/features/finance/financial_entry.dart';

class FinancialInstallmentPreview extends StatelessWidget {
  const FinancialInstallmentPreview({
    required this.amount,
    required this.installments,
    required this.currency,
    required this.firstDate,
    this.paidMinor = 0,
    super.key,
  });
  final TextEditingController amount;
  final TextEditingController installments;
  final String currency;
  final DateTime firstDate;
  final int paidMinor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([amount, installments]),
    builder: (context, _) {
      final total = parseFinancialAmountInput(amount.text, currency);
      final count = int.tryParse(installments.text) ?? 0;
      if (total == null || count <= 1 || count > 120) {
        return const SizedBox.shrink();
      }
      final schedule = financialInstallmentSchedule(
        amountMinor: total,
        count: count,
        firstDate: firstDate,
        paidMinor: paidMinor,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ExpansionTile(
          key: const ValueKey('financial-installment-schedule'),
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_rounded),
          title: Text('Pago diferido · $count cuotas mensuales'),
          subtitle: Text(
            'Desde ${DateFormat('dd-MM-yyyy').format(firstDate)} · Total ${FinancialEntry.formatAmount(total, currency)}',
          ),
          children: [
            const Text(
              'Las cuotas distribuyen el total sin intereses adicionales. Los abonos se aplican desde la primera cuota pendiente.',
            ),
            for (final item in schedule)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Cuota ${item.number} de $count · ${DateFormat('dd-MM-yyyy').format(item.date)}',
                ),
                subtitle: Text(
                  item.balanceMinor == 0
                      ? 'Pagada'
                      : 'Pendiente: ${FinancialEntry.formatAmount(item.balanceMinor, currency)}',
                ),
                trailing: Text(
                  FinancialEntry.formatAmount(item.amountMinor, currency),
                ),
              ),
          ],
        ),
      );
    },
  );
}
