import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_style.dart';

class FinancialPaymentMethodField extends StatelessWidget {
  const FinancialPaymentMethodField({
    required this.method,
    required this.installments,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final String? method;
  final TextEditingController installments;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Medio de pago', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in financialPaymentMethods)
            FinancialLiquidFilter(
              label: m == 'credit' ? 'Crédito' : financialPaymentLabel(m, null),
              icon: switch (m) {
                'credit' => Icons.credit_card_rounded,
                'debit' => Icons.payment_rounded,
                'transfer' => Icons.swap_horiz_rounded,
                _ => Icons.payments_rounded,
              },
              selected: method == m,
              onPressed: enabled
                  ? () => onChanged(method == m ? null : m)
                  : null,
            ),
        ],
      ),
      if (method == 'credit') ...[
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('payment-installments'),
          controller: installments,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Número de cuotas',
            prefixIcon: Icon(Icons.calendar_month_rounded),
            helperMaxLines: 3,
            helperText: 'De 1 a 120 cuotas. El total se distribuye mensualmente, sin marcarlo como pagado.',
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return n == null || n < 1 || n > 120
                ? 'Ingresa entre 1 y 120 cuotas'
                : null;
          },
        ),
      ],
      const SizedBox(height: 14),
    ],
  );
}
