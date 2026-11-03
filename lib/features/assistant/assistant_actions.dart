import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:uuid/uuid.dart';

class AssistantExpense {
  AssistantExpense({
    required this.title,
    required this.merchant,
    required this.detail,
    required this.amountMinor,
    required this.currency,
    required this.date,
    required this.status,
    required this.suggestedList,
  });
  final String title, merchant, detail, currency, status, suggestedList;
  final int amountMinor;
  final DateTime? date;
  final createListAction = Object();
  final noteId = const Uuid().v4();
  final mutationId = const Uuid().v4();

  static AssistantExpense? parse(Object? raw) {
    if (raw case {
      'title': final String title,
      'merchant': final String merchant,
      'detail': final String detail,
      'amountMinor': final int amount,
      'currency': final String currency,
      'date': final String date,
      'status': final String status,
      'suggestedList': final String name,
    }) {
      final parsed = DateTime.tryParse(date);
      if (amount < 1 ||
          amount > FinancialEntry.maxAmountMinor ||
          !ListConfiguration.currencies.contains(currency) ||
          !{'pending', 'paid'}.contains(status) ||
          title.trim().isEmpty ||
          title.length > 80 ||
          name.trim().isEmpty ||
          name.length > 50 ||
          merchant.length > 100 ||
          detail.length > 700 ||
          (date.isNotEmpty &&
              parsed?.toIso8601String().split('T').first != date)) {
        return null;
      }
      return AssistantExpense(
        title: title,
        merchant: merchant,
        detail: detail,
        amountMinor: amount,
        currency: currency,
        date: parsed,
        status: status,
        suggestedList: name,
      );
    }
    return null;
  }

  FinancialEntry get entry => FinancialEntry(
    amountMinor: amountMinor,
    currency: currency,
    counterparty: merchant,
    date: date ?? DateTime.now(),
    status: status,
  );
  String get summary => [
    title,
    FinancialEntry.formatAmount(amountMinor, currency),
    currency,
    if (merchant.isNotEmpty &&
        !title.toLowerCase().contains(merchant.toLowerCase()))
      merchant,
    if (date != null) date!.toIso8601String().split('T').first,
    status == 'paid' ? 'Pagado' : 'Pendiente',
  ].join(' · ');
}

class AssistantEdit {
  AssistantEdit(
    this.targetTitle,
    this.title,
    this.replace,
    this.append,
    this.addTasks,
    this.completeTasks,
    this.completed,
  );
  final String targetTitle;
  final mutationId = const Uuid().v4();
  final String? title, replace, append;
  final List<String> addTasks, completeTasks;
  final bool? completed;

  static AssistantEdit? parse(Object? raw) {
    if (raw is! Map || raw['targetTitle'] is! String) return null;
    bool validText(String key, int limit) =>
        raw[key] == null ||
        (raw[key] is String &&
            (raw[key] as String).trim().isNotEmpty &&
            (raw[key] as String).length <= limit);
    bool validTasks(String key) =>
        raw[key] == null ||
        (raw[key] is List &&
            (raw[key] as List).length <= 12 &&
            (raw[key] as List).every(
              (t) => t is String && t.trim().isNotEmpty && t.length <= 120,
            ));
    if ((raw['targetTitle'] as String).length > 120 ||
        !validText('newTitle', 80) ||
        !validText('replaceContent', 700) ||
        !validText('appendContent', 700) ||
        (raw['replaceContent'] != null && raw['appendContent'] != null) ||
        !validTasks('addTasks') ||
        !validTasks('completeTasks') ||
        (raw['completed'] != null && raw['completed'] is! bool)) {
      return null;
    }
    final edit = AssistantEdit(
      raw['targetTitle'],
      raw['newTitle'],
      raw['replaceContent'],
      raw['appendContent'],
      List<String>.from(raw['addTasks'] ?? []),
      List<String>.from(raw['completeTasks'] ?? []),
      raw['completed'],
    );
    return edit.descriptions.isEmpty ? null : edit;
  }

  List<String> get descriptions => [
    if (title != null) 'Nuevo título: $title',
    if (replace != null) 'Reemplazar descripción por: $replace',
    if (append != null) 'Añadir a la descripción: $append',
    for (final task in addTasks) 'Añadir subtarea: $task',
    for (final task in completeTasks) 'Completar subtarea: $task',
    if (completed != null)
      completed! ? 'Marcar la nota como completada' : 'Reabrir la nota',
  ];
}
