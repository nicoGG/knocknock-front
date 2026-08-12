import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats a CLP amount while it is typed, for example `5000` as `$5.000`.
class MoneyTextInputFormatter extends TextInputFormatter {
  MoneyTextInputFormatter();

  static final _formatter = NumberFormat.decimalPattern('es_CL');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final limited = digits.length > 12 ? digits.substring(0, 12) : digits;
    final amount = int.tryParse(limited) ?? 0;
    final formatted = '\$${_formatter.format(amount)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
