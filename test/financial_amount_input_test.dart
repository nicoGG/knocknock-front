import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/finance/financial_amount_input.dart';

void main() {
  test('CLP separates thousands and preserves the stored integer amount', () {
    final formatter = ClpThousandsInputFormatter();
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '4520000',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    expect(result.text, '4.520.000');
    expect(result.selection.baseOffset, 9);
    expect(parseFinancialAmountInput(result.text, 'CLP'), 4520000);
    expect(financialAmountInput('200000', 'CLP'), '200.000');
  });
  test('editing in the middle keeps cursor beside the inserted digit', () {
    final formatter = ClpThousandsInputFormatter();
    final result = formatter.formatEditUpdate(
      const TextEditingValue(text: '12.345'),
      const TextEditingValue(
        text: '129.345',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(result.text, '129.345');
    expect(result.selection.baseOffset, 3);
    expect(
      formatter.formatEditUpdate(result, TextEditingValue.empty).text,
      isEmpty,
    );
  });
  test('decimal currencies keep their decimals', () {
    expect(financialAmountInput('10,50', 'USD'), '10,50');
    expect(parseFinancialAmountInput('10,50', 'USD'), 1050);
    expect(parseFinancialAmountInput('10.50', 'EUR'), 1050);
  });
}
