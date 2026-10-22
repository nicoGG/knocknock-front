import 'package:equatable/equatable.dart';

enum NoteListType { normal, expenses, quotations, receivables, custom }

class ListConfiguration extends Equatable {
  const ListConfiguration({
    this.type = NoteListType.normal,
    this.currency = 'CLP',
    this.customTypeName,
  });
  factory ListConfiguration.fromJson(Map<String, dynamic> json) =>
      ListConfiguration(
        type:
            NoteListType.values
                .where((value) => value.name == json['listType'])
                .firstOrNull ??
            NoteListType.normal,
        currency: currencies.contains(json['currency'])
            ? json['currency'] as String
            : 'CLP',
        customTypeName: json['customTypeName'] as String?,
      );
  static const currencies = ['CLP', 'USD', 'EUR'];
  final NoteListType type;
  final String currency;
  final String? customTypeName;
  bool get isFinancial => type != NoteListType.normal;
  String get label => switch (type) {
    NoteListType.normal => 'Normal',
    NoteListType.expenses => 'Gastos',
    NoteListType.quotations => 'Cotizaciones',
    NoteListType.receivables => 'Cuentas por cobrar',
    NoteListType.custom =>
      customTypeName?.trim().isNotEmpty == true
          ? customTypeName!
          : 'Financiera personalizada',
  };
  String get entryLabel => switch (type) {
    NoteListType.expenses => 'Nuevo gasto',
    NoteListType.quotations => 'Nueva cotización',
    NoteListType.receivables => 'Nueva cuenta por cobrar',
    _ => 'Nuevo registro',
  };
  String get counterpartyLabel => switch (type) {
    NoteListType.quotations => 'Proveedor',
    NoteListType.receivables => 'Persona que debe',
    _ => 'Persona o comercio',
  };
  List<String> get statuses => type == NoteListType.quotations
      ? ['pending', 'accepted', 'rejected']
      : ['pending', 'paid'];
  String statusLabel(String status) => switch (status) {
    'paid' => type == NoteListType.receivables ? 'Cobrado' : 'Pagado',
    'accepted' => 'Aceptada',
    'rejected' => 'Descartada',
    _ =>
      type == NoteListType.receivables
          ? 'Por cobrar'
          : type == NoteListType.expenses
          ? 'Por pagar'
          : 'Pendiente',
  };
  Map<String, dynamic> toJson() => {
    'listType': type.name,
    'currency': currency,
    if (type == NoteListType.custom && customTypeName != null)
      'customTypeName': customTypeName,
  };
  @override
  List<Object?> get props => [type, currency, customTypeName];
}
