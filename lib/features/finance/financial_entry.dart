import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/list_configuration.dart';

class FinancialEntry extends Equatable {
  const FinancialEntry({
    required this.amountMinor,
    required this.currency,
    required this.counterparty,
    required this.date,
    this.status = 'pending',
  });
  final int amountMinor;
  final String currency;
  final String counterparty;
  final DateTime date;
  final String status;
  static const maxAmountMinor = 100000000000000;
  static int decimals(String currency) => currency == 'CLP' ? 0 : 2;
  static int? parseAmount(String text, String currency) {
    final value = text.trim();
    final pattern = currency == 'CLP' ? r'^\d+$' : r'^\d+(?:[,.]\d{1,2})?$';
    if (!RegExp(pattern).hasMatch(value)) return null;
    final parts = value.replaceAll(',', '.').split('.');
    final major = int.tryParse(parts.first);
    if (major == null || major > maxAmountMinor) return null;
    final amount = decimals(currency) == 0
        ? major
        : major * 100 +
              int.parse((parts.length == 1 ? '' : parts.last).padRight(2, '0'));
    return amount > 0 && amount <= maxAmountMinor ? amount : null;
  }

  String get editableAmount => decimals(currency) == 0
      ? '$amountMinor'
      : '${amountMinor ~/ 100},${(amountMinor % 100).toString().padLeft(2, '0')}';
  static String formatAmount(int minor, String currency) =>
      NumberFormat.currency(
        locale: 'es_CL',
        symbol: currency,
        decimalDigits: decimals(currency),
      ).format(minor / (decimals(currency) == 0 ? 1 : 100));
  String get statusLabel => switch (status) {
    'paid' => 'Pagado / cobrado',
    'accepted' => 'Aceptada',
    'rejected' => 'Descartada',
    _ => 'Pendiente',
  };
  String get formattedAmount => formatAmount(amountMinor, currency);
  String get encoded => jsonEncode({
    'version': 1,
    'amountMinor': amountMinor,
    'currency': currency,
    'counterparty': counterparty,
    'date': DateFormat('yyyy-MM-dd').format(date),
    'status': status,
  });
  static FinancialEntry? tryDecode(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final amount = data['amountMinor'];
      final dateText = data['date'] as String;
      final date = DateTime.tryParse(dateText);
      final party = data['counterparty'];
      if (data['version'] != 1 ||
          amount is! int ||
          amount <= 0 ||
          amount > maxAmountMinor ||
          !ListConfiguration.currencies.contains(data['currency']) ||
          party is! String ||
          party.length > 120 ||
          date == null ||
          DateFormat('yyyy-MM-dd').format(date) != dateText ||
          ![
            'pending',
            'paid',
            'accepted',
            'rejected',
          ].contains(data['status'])) {
        return null;
      }
      return FinancialEntry(
        amountMinor: amount,
        currency: data['currency'] as String,
        counterparty: party,
        date: date,
        status: data['status'] as String,
      );
    } on Object {
      return null;
    }
  }

  @override
  List<Object?> get props => [
    amountMinor,
    currency,
    counterparty,
    date,
    status,
  ];
}
