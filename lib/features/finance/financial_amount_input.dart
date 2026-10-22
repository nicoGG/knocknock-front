import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';

String financialAmountInput(String value, String currency) {
  if (currency != 'CLP' || value.isEmpty) return value;
  final amount = int.tryParse(value.replaceAll('.', ''));
  return amount == null
      ? value
      : NumberFormat.decimalPattern('es_CL').format(amount);
}

int? parseFinancialAmountInput(String value, String currency) =>
    FinancialEntry.parseAmount(
      currency == 'CLP' ? value.replaceAll('.', '') : value,
      currency,
    );

class ClpThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (int.tryParse(digits) == null) return oldValue;
    final formatted = financialAmountInput(digits, 'CLP');
    final cursor = newValue.selection.extentOffset.clamp(
      0,
      newValue.text.length,
    );
    final digitsRight = newValue.text
        .substring(cursor)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    var offset = formatted.length;
    var remaining = digitsRight;
    while (offset > 0 && remaining > 0) {
      offset--;
      if (RegExp(r'[0-9]').hasMatch(formatted[offset])) remaining--;
    }
    while (offset > 0 && formatted[offset - 1] == '.') {
      offset--;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
