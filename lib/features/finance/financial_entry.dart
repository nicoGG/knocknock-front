import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/list_configuration.dart';

const financialPaymentMethods = ['credit', 'debit', 'transfer', 'cash'];
bool validFinancialPaymentMethod(String? method, int? installments) =>
    method == null
    ? installments == null
    : financialPaymentMethods.contains(method) &&
          (method == 'credit'
              ? installments != null && installments >= 1 && installments <= 120
              : installments == null);
String financialPaymentLabel(String? method, int? installments) =>
    switch (method) {
      'credit' =>
        'Crédito · $installments ${installments == 1 ? 'cuota' : 'cuotas'}',
      'debit' => 'Débito',
      'transfer' => 'Transferencia',
      'cash' => 'Efectivo',
      _ => 'Sin especificar',
    };

/// Monthly installments retain integer minor units, including the remainder.
class FinancialInstallment {
  const FinancialInstallment(
    this.number,
    this.date,
    this.amountMinor,
    this.paidMinor,
  );
  final int number;
  final DateTime date;
  final int amountMinor;
  final int paidMinor;
  int get balanceMinor => amountMinor - paidMinor;
}

DateTime financialMonthOffset(DateTime date, int offset) {
  final last = DateTime(date.year, date.month + offset + 1, 0).day;
  return DateTime(
    date.year,
    date.month + offset,
    date.day > last ? last : date.day,
  );
}

List<FinancialInstallment> financialInstallmentSchedule({
  required int amountMinor,
  required int count,
  required DateTime firstDate,
  int paidMinor = 0,
}) {
  if (amountMinor <= 0 || count < 1 || count > 120) return const [];
  var remainingPaid = paidMinor.clamp(0, amountMinor);
  return List.generate(count, (i) {
    final amount = amountMinor ~/ count + (i < amountMinor % count ? 1 : 0);
    final paid = remainingPaid.clamp(0, amount);
    remainingPaid -= paid;
    return FinancialInstallment(
      i + 1,
      financialMonthOffset(firstDate, i),
      amount,
      paid,
    );
  });
}

class FinancialEntry extends Equatable {
  const FinancialEntry({
    required this.amountMinor,
    required this.currency,
    required this.counterparty,
    required this.date,
    this.status = 'pending',
    this.kind = 'entry',
    this.period = 'all',
    this.payments = const [],
    this.paidBy = '',
    this.participants = const [],
    this.dueDate,
    this.deliveryDays,
    this.validUntil,
    this.legacyDateAsDue = false,
    this.paymentMethod,
    this.installments,
  });
  final String? paymentMethod;
  final int? installments;
  String get paymentLabel => financialPaymentLabel(paymentMethod, installments);
  final int amountMinor;
  final String currency;
  final String counterparty;
  final DateTime date;
  final String status;
  final String kind;
  final String period;
  final List<FinancialPayment> payments;
  final String paidBy;
  final List<String> participants;
  final DateTime? dueDate;
  final int? deliveryDays;
  final DateTime? validUntil;
  final bool legacyDateAsDue;
  bool get isBudget => kind == 'budget';
  bool get isSettlement => kind == 'settlement';
  bool get isClosed => ['paid', 'accepted', 'rejected'].contains(status);
  int get paidMinor => status == 'paid'
      ? amountMinor
      : payments.fold(0, (sum, p) => sum + p.amountMinor);
  int get balanceMinor => status == 'rejected' ? 0 : amountMinor - paidMinor;
  bool get isDeferred =>
      !isBudget &&
      !isSettlement &&
      paymentMethod == 'credit' &&
      (installments ?? 0) > 1;
  DateTime get firstInstallmentDate => dueDate ?? financialMonthOffset(date, 1);
  List<FinancialInstallment> get installmentSchedule => isDeferred
      ? financialInstallmentSchedule(
          amountMinor: amountMinor,
          count: installments!,
          firstDate: firstInstallmentDate,
          paidMinor: paidMinor,
        )
      : const [];
  Iterable<DateTime> get periodDates =>
      isDeferred ? installmentSchedule.map((i) => i.date) : [date];
  bool occursInMonth(String month) =>
      periodDates.any((d) => DateFormat('yyyy-MM').format(d) == month);
  int amountInMonth(String? month) => month == null
      ? amountMinor
      : isDeferred
      ? installmentSchedule
            .where((i) => DateFormat('yyyy-MM').format(i.date) == month)
            .fold(0, (sum, i) => sum + i.amountMinor)
      : occursInMonth(month)
      ? amountMinor
      : 0;
  int paidInMonth(String? month) => month == null
      ? paidMinor
      : isDeferred
      ? installmentSchedule
            .where((i) => DateFormat('yyyy-MM').format(i.date) == month)
            .fold(0, (sum, i) => sum + i.paidMinor)
      : occursInMonth(month)
      ? paidMinor
      : 0;
  int balanceInMonth(String? month) =>
      status == 'rejected' ? 0 : amountInMonth(month) - paidInMonth(month);
  DateTime? effectiveDueDate({bool receivable = false}) => isDeferred
      ? installmentSchedule.where((i) => i.balanceMinor > 0).firstOrNull?.date
      : dueDate ?? (receivable && legacyDateAsDue ? date : null);
  bool isOverdue(DateTime now, {bool receivable = false}) {
    final due = effectiveDueDate(receivable: receivable);
    return !isBudget &&
        !isClosed &&
        balanceMinor > 0 &&
        due != null &&
        due.isBefore(DateTime(now.year, now.month, now.day));
  }

  Map<String, int> get shares {
    if (participants.isEmpty) return const {};
    return {
      for (var i = 0; i < participants.length; i++)
        participants[i]:
            amountMinor ~/ participants.length +
            (i < amountMinor % participants.length ? 1 : 0),
    };
  }

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
      '${currency == 'EUR' ? '€' : r'$'} ${NumberFormat.currency(locale: 'es_CL', symbol: currency, decimalDigits: decimals(currency)).format(minor / (decimals(currency) == 0 ? 1 : 100))}';
  String get statusLabel => switch (status) {
    'paid' => 'Pagado / cobrado',
    'accepted' => 'Aceptada',
    'rejected' => 'Descartada',
    _ => 'Pendiente',
  };
  String get formattedAmount => formatAmount(amountMinor, currency);
  String get encoded => jsonEncode({
    'version': 2,
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
    if (installments != null) 'installments': installments,
    'kind': kind,
    'period': period,
    'payments': payments.map((p) => p.toJson()).toList(),
    'paidBy': paidBy,
    'participants': participants,
    if (dueDate != null) 'dueDate': DateFormat('yyyy-MM-dd').format(dueDate!),
    if (deliveryDays != null) 'deliveryDays': deliveryDays,
    if (validUntil != null)
      'validUntil': DateFormat('yyyy-MM-dd').format(validUntil!),
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
      if (![1, 2].contains(data['version']) ||
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
      final method = data['paymentMethod'] as String?;
      final installments = data['installments'] as int?;
      if (!validFinancialPaymentMethod(method, installments)) return null;
      final payments = (data['payments'] as List? ?? const [])
          .map(
            (p) =>
                FinancialPayment.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList();
      final participants = (data['participants'] as List? ?? const [])
          .cast<String>();
      final kind = data['kind'] as String? ?? 'entry';
      final period = data['period'] as String? ?? 'all';
      final paidBy = data['paidBy'] as String? ?? '';
      final delivery = data['deliveryDays'] as int?;
      DateTime? optionalDate(String key) {
        if (data[key] == null) return null;
        final rawDate = data[key] as String;
        final parsed = DateTime.parse(rawDate);
        if (DateFormat('yyyy-MM-dd').format(parsed) != rawDate) {
          throw const FormatException();
        }
        return parsed;
      }

      if (!['entry', 'budget', 'settlement'].contains(kind) ||
          !(period == 'all' ||
              RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) ||
          paidBy.length > 120 ||
          (data['version'] == 2 &&
              (data['kind'] == null ||
                  data['period'] == null ||
                  data['payments'] is! List ||
                  data['participants'] is! List ||
                  data['paidBy'] is! String)) ||
          (data['status'] == 'paid' &&
              payments.isNotEmpty &&
              payments.fold<int>(0, (sum, p) => sum + p.amountMinor) !=
                  amount) ||
          (kind == 'settlement' &&
              (data['status'] != 'paid' ||
                  payments.isNotEmpty ||
                  participants.isNotEmpty ||
                  paidBy.trim().isEmpty ||
                  party.trim().isEmpty ||
                  paidBy == party)) ||
          payments.length > 50 ||
          payments.map((p) => p.id).toSet().length != payments.length ||
          payments.fold<int>(0, (sum, p) => sum + p.amountMinor) > amount ||
          participants.length > 30 ||
          participants.toSet().length != participants.length ||
          participants.any((p) => p.trim().isEmpty || p.length > 120) ||
          (participants.isNotEmpty &&
              (!participants.contains(paidBy) ||
                  amount < participants.length)) ||
          (delivery != null && (delivery < 0 || delivery > 3650)) ||
          (kind == 'budget' &&
              (payments.isNotEmpty ||
                  participants.isNotEmpty ||
                  data['status'] != 'pending'))) {
        return null;
      }
      return FinancialEntry(
        paymentMethod: method,
        installments: installments,
        legacyDateAsDue: data['version'] == 1,
        kind: kind,
        period: period,
        payments: payments,
        paidBy: paidBy,
        participants: participants,
        dueDate: optionalDate('dueDate'),
        deliveryDays: delivery,
        validUntil: optionalDate('validUntil'),
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
    paymentMethod,
    installments,
    amountMinor,
    currency,
    counterparty,
    date,
    status,
    kind,
    period,
    payments,
    paidBy,
    participants,
    dueDate,
    deliveryDays,
    validUntil,
  ];
}

class FinancialPayment extends Equatable {
  const FinancialPayment({
    required this.id,
    required this.amountMinor,
    required this.date,
    this.detail = '',
    this.receiptId,
    this.paymentMethod,
    this.installments,
  });
  final String? paymentMethod;
  final int? installments;
  String get paymentLabel => financialPaymentLabel(paymentMethod, installments);
  final String id;
  final int amountMinor;
  final DateTime date;
  final String detail;
  final String? receiptId;
  factory FinancialPayment.fromJson(Map<String, dynamic> json) {
    final method = json['paymentMethod'] as String?;
    final installments = json['installments'] as int?;
    if (!validFinancialPaymentMethod(method, installments)) {
      throw const FormatException('Medio de pago inválido');
    }
    final id = json['id'] as String;
    final amount = json['amountMinor'] as int;
    final dateText = json['date'] as String;
    final date = DateTime.parse(dateText);
    final detail = json['detail'] as String? ?? '';
    final receipt = json['receiptId'] as String?;
    if (id.isEmpty ||
        id.length > 80 ||
        amount <= 0 ||
        amount > FinancialEntry.maxAmountMinor ||
        DateFormat('yyyy-MM-dd').format(date) != dateText ||
        detail.length > 160 ||
        (receipt?.length ?? 0) > 120) {
      throw const FormatException('Abono inválido');
    }
    return FinancialPayment(
      paymentMethod: method,
      installments: installments,
      id: id,
      amountMinor: amount,
      date: date,
      detail: detail,
      receiptId: receipt,
    );
  }
  Map<String, dynamic> toJson() => {
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
    if (installments != null) 'installments': installments,
    'id': id,
    'amountMinor': amountMinor,
    'date': DateFormat('yyyy-MM-dd').format(date),
    'detail': detail,
    if (receiptId != null) 'receiptId': receiptId,
  };
  @override
  List<Object?> get props => [
    id,
    amountMinor,
    date,
    detail,
    receiptId,
    paymentMethod,
    installments,
  ];
}
