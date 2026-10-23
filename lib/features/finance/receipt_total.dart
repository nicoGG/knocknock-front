import 'package:nocknock/features/finance/financial_entry.dart';

/// Only totals explicitly labelled by the receipt are candidates. Ambiguous
/// totals are left for manual entry instead of guessing from the largest number.
int? receiptTotalMinor(String text, String currency) {
  final lines = text
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .split(RegExp(r'[\r\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final candidates = <(int, int)>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!RegExp(r'\bTOTAL\b').hasMatch(line) ||
        RegExp(
          r'\b(SUBTOTAL|SUB TOTAL|NETO|IVA|IMPUESTO|DESCUENTO|AHORRO|VUELTO|PROPINA|ARTICULOS|ITEMS|PRODUCTOS)\b',
        ).hasMatch(line)) {
      continue;
    }
    final priority =
        RegExp(
          r'\b(TOTAL A PAGAR|MONTO TOTAL|TOTAL FINAL|TOTAL VENTA|TOTAL COMPRA)\b',
        ).hasMatch(line)
        ? 2
        : 1;
    var amounts = _amounts(line, currency);
    if (amounts.isEmpty &&
        i + 1 < lines.length &&
        RegExp(r'^(?:CLP|USD|EUR|\$|€|\s|[\d.,])+$').hasMatch(lines[i + 1])) {
      amounts = _amounts(lines[i + 1], currency);
    }
    if (amounts.length == 1) candidates.add((priority, amounts.single));
  }
  if (candidates.isEmpty) return null;
  final priority = candidates.map((c) => c.$1).reduce((a, b) => a > b ? a : b);
  final totals = candidates
      .where((c) => c.$1 == priority)
      .map((c) => c.$2)
      .toSet();
  return totals.length == 1 ? totals.single : null;
}

List<int> _amounts(String line, String currency) {
  // Do not reinterpret a total explicitly printed in another currency.
  if (RegExp(r'\b(CLP|USD|EUR)\b')
      .allMatches(line)
      .any((m) => m.group(0) != currency)) {
    return [];
  }
  final result = <int>[];
  for (final match in RegExp(
    r'(?<![\w.,-])\d+(?:[.,]\d+)*(?![\w.,])',
  ).allMatches(line)) {
    final raw = match.group(0)!;
    String? normalized;
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      normalized = raw;
    } else {
      final last = raw.lastIndexOf(RegExp(r'[.,]'));
      final separator = raw[last];
      final tail = raw.substring(last + 1);
      if (tail.length == 2) {
        final whole = raw.substring(0, last);
        final grouping = separator == ',' ? '.' : ',';
        if (!RegExp('^\\d{1,3}(?:\\$grouping\\d{3})+\$').hasMatch(whole) &&
            !RegExp(r'^\d+$').hasMatch(whole)) {
          continue;
        }
        if (currency == 'CLP' && tail != '00') continue;
        normalized =
            whole.replaceAll(grouping, '') +
            (currency == 'CLP' ? '' : '.$tail');
      } else if (RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(raw) ||
          RegExp(r'^\d{1,3}(?:,\d{3})+$').hasMatch(raw)) {
        normalized = raw.replaceAll(RegExp(r'[.,]'), '');
      }
    }
    final amount = normalized == null
        ? null
        : FinancialEntry.parseAmount(normalized, currency);
    if (amount != null) result.add(amount);
  }
  return result;
}
