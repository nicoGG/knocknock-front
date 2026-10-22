import 'package:flutter/material.dart';
import 'package:nocknock/features/finance/list_configuration.dart';

class FinancialListTemplate {
  const FinancialListTemplate(
    this.name,
    this.description,
    this.type,
    this.icon,
  );
  final String name;
  final String description;
  final NoteListType type;
  final IconData icon;
  static const values = [
    FinancialListTemplate(
      'Gastos del hogar',
      'Servicios, compras y presupuesto mensual compartido.',
      NoteListType.expenses,
      Icons.home_outlined,
    ),
    FinancialListTemplate(
      'Viaje compartido',
      'Registra quién pagó y divide los gastos del viaje.',
      NoteListType.expenses,
      Icons.flight_outlined,
    ),
    FinancialListTemplate(
      'Remodelación',
      'Controla materiales, mano de obra y presupuesto.',
      NoteListType.expenses,
      Icons.construction_outlined,
    ),
    FinancialListTemplate(
      'Cobros pendientes',
      'Personas, vencimientos, comprobantes y abonos.',
      NoteListType.receivables,
      Icons.account_balance_wallet_outlined,
    ),
    FinancialListTemplate(
      'Comparar proveedores',
      'Compara precios, entrega y validez de propuestas.',
      NoteListType.quotations,
      Icons.compare_arrows,
    ),
  ];
}
