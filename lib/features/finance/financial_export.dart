import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_download.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String _xml(Object? value) =>
    const HtmlEscape(HtmlEscapeMode.element)
        .convert('$value')
        .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');
String _day(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year.toString().padLeft(4, '0')}';
String financialExportName(String name) {
  final safe = name.replaceAll(RegExp(r'[/\\\x00-\x1f<>:"|?*]'), '_').trim();
  return safe.isEmpty
      ? 'NockNock'
      : safe.substring(0, safe.length > 70 ? 70 : safe.length);
}

/// Minimal Office Open XML workbook. Text is always an inline string, never a
/// formula; amounts are numeric cells in major units with a currency column.
Uint8List financialExcel(List<Note> notes, {List<Note>? balanceNotes}) {
  final records = financialRecords(notes)
      .where((n) => n.financialEntry != null)
      .toList();
  num amount(int value, String currency) =>
      currency == 'CLP' ? value : value / 100;
  final sheets = <String, List<List<Object?>>>{
    'Registros': [
      [
        'Concepto',
        'Persona / proveedor',
        'Fecha',
        'Moneda',
        'Monto',
        'Abonado',
        'Saldo',
        'Estado',
        'Vencimiento',
        'Entrega (días)',
        'Válida hasta',
        'Comprobantes',
        'Detalle',
        'ID del registro',
        'Medio de pago',
        'Cuotas',
      ],
      for (final n in records)
        [
          n.title,
          n.financialEntry!.counterparty,
          _day(n.financialEntry!.date),
          n.financialEntry!.currency,
          amount(n.financialEntry!.amountMinor, n.financialEntry!.currency),
          amount(n.financialEntry!.paidMinor, n.financialEntry!.currency),
          amount(n.financialEntry!.balanceMinor, n.financialEntry!.currency),
          n.financialEntry!.statusLabel,
          n.financialEntry!.dueDate == null
              ? ''
              : _day(n.financialEntry!.dueDate!),
          n.financialEntry!.deliveryDays ?? '',
          n.financialEntry!.validUntil == null
              ? ''
              : _day(n.financialEntry!.validUntil!),
          n.photoAttachments.map((a) => a.name).join('; '),
          n.content,
          n.id,
          n.financialEntry!.paymentMethod == null
              ? ''
              : n.financialEntry!.paymentLabel,
          n.financialEntry!.installments ?? '',
        ],
    ],
    'Abonos': [
      [
        'Concepto',
        'Fecha',
        'Moneda',
        'Monto',
        'Referencia',
        'Comprobante',
        'Medio de pago',
        'Cuotas',
      ],
      for (final n in records)
        for (final p in n.financialEntry!.payments)
          [
            n.title,
            _day(p.date),
            n.financialEntry!.currency,
            amount(p.amountMinor, n.financialEntry!.currency),
            p.detail,
            n.photoAttachments
                    .where((a) => a.id == p.receiptId)
                    .firstOrNull
                    ?.name ??
                (p.receiptId == null ? '' : 'Adjunto retirado'),
            p.paymentMethod == null ? '' : p.paymentLabel,
            p.installments ?? '',
          ],
    ],
    'Reparto acumulado': [
      ['Debe pagar', 'Debe recibir', 'Moneda', 'Monto'],
      for (final t in sharedTransfers(balanceNotes ?? records))
        [t.from, t.to, t.currency, amount(t.amountMinor, t.currency)],
    ],
  };
  final zip = Archive();
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.keys.indexed.map((s) => '<sheet name="${_xml(s.$2)}" sheetId="${s.$1 + 1}" r:id="rId${s.$1 + 1}"/>').join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>',
  );
  for (final indexed in sheets.values.indexed) {
    final rows = indexed.$2.indexed
        .map(
          (row) =>
              '<row r="${row.$1 + 1}">${row.$2.map((cell) => cell is num ? '<c><v>$cell</v></c>' : '<c t="inlineStr"><is><t xml:space="preserve">${_xml(cell)}</t></is></c>').join()}</row>',
        )
        .join();
    add(
      'xl/worksheets/sheet${indexed.$1 + 1}.xml',
      '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>$rows</sheetData></worksheet>',
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

Future<Uint8List> financialPdf(
  NoteList list,
  List<Note> notes, {
  String? month,
  List<Note>? balanceNotes,
}) async {
  final records = financialRecords(notes)
      .where((n) => n.financialEntry != null)
      .toList();
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Lato-Regular.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final currencies = records.map((n) => n.financialEntry!.currency).toSet();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 1000,
      header: (_) => pw.Text(
        'NockNock · ${list.name} · ${month ?? 'Todos los meses'}',
        style: const pw.TextStyle(fontSize: 16),
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${c.pageNumber} / ${c.pagesCount}'),
      ),
      build: (_) => [
        pw.SizedBox(height: 12),
        pw.Text(
          'Resumen de registros. Los importes se mantienen separados por moneda. Los comprobantes originales se incluyen al exportar la rendición ZIP.',
        ),
        for (final c in currencies)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Text(
              '$c · Registrado: ${FinancialEntry.formatAmount(records.where((n) => n.financialEntry!.currency == c).fold(0, (sum, n) => sum + (n.financialEntry!.isSettlement ? 0 : n.financialEntry!.amountMinor)), c)} · Abonado: ${FinancialEntry.formatAmount(records.where((n) => n.financialEntry!.currency == c).fold(0, (sum, n) => sum + (n.financialEntry!.isSettlement ? 0 : n.financialEntry!.paidMinor)), c)}',
            ),
          ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [
            'Concepto / proveedor',
            'Fecha',
            'Monto',
            'Abonado',
            'Saldo',
            'Estado / vencimiento',
            'Comprobantes',
          ],
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: const pw.TextStyle(fontSize: 8),
          data: [
            for (final n in records)
              [
                '${n.title}\n${n.financialEntry!.counterparty}',
                _day(n.financialEntry!.date),
                n.financialEntry!.formattedAmount,
                FinancialEntry.formatAmount(
                  n.financialEntry!.paidMinor,
                  n.financialEntry!.currency,
                ),
                FinancialEntry.formatAmount(
                  n.financialEntry!.balanceMinor,
                  n.financialEntry!.currency,
                ),
                '${n.financialEntry!.statusLabel}${n.financialEntry!.paymentMethod == null ? '' : '\n${n.financialEntry!.paymentLabel}'}\n${n.financialEntry!.dueDate == null ? '' : _day(n.financialEntry!.dueDate!)}',
                n.photoAttachments.map((a) => a.name).join('\n'),
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        if (sharedTransfers(balanceNotes ?? records).isNotEmpty)
          pw.Text('Saldos compartidos acumulados de toda la lista'),
        if (sharedTransfers(balanceNotes ?? records).isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: ['Debe pagar', 'Debe recibir', 'Monto'],
            data: [
              for (final t in sharedTransfers(balanceNotes ?? records))
                [
                  t.from,
                  t.to,
                  FinancialEntry.formatAmount(t.amountMinor, t.currency),
                ],
            ],
          ),
      ],
    ),
  );
  return doc.save();
}

Future<String?> saveFinancialExport({
  required NoteList list,
  required List<Note> notes,
  required String format,
  String? month,
  Future<NoteAttachment> Function(Note, String)? loadAttachment,
}) async {
  final selected = financialRecords(notes, month: month);
  final name = '${financialExportName(list.name)}-${month ?? 'todos'}';
  Uint8List bytes;
  String mime;
  if (format == 'xlsx') {
    bytes = financialExcel(selected, balanceNotes: notes);
    mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  } else if (format == 'pdf') {
    bytes = await financialPdf(
      list,
      selected,
      month: month,
      balanceNotes: notes,
    );
    mime = 'application/pdf';
  } else {
    final zip = Archive();
    void add(String name, Uint8List data) =>
        zip.addFile(ArchiveFile(name, data.length, data));
    add(
      '$name.pdf',
      await financialPdf(list, selected, month: month, balanceNotes: notes),
    );
    add('$name.xlsx', financialExcel(selected, balanceNotes: notes));
    for (final note in selected) {
      for (final attachment in note.photoAttachments) {
        final source = attachment.dataBase64 != null
            ? attachment
            : await loadAttachment?.call(note, attachment.id);
        if (source == null) {
          throw const FormatException('No se pudo cargar un comprobante');
        }
        add(
          'comprobantes/${financialExportName(note.id)}/${financialExportName(attachment.id)}-${noteAttachmentDownloadName(attachment)}',
          decodeNoteAttachmentBytes(source),
        );
      }
    }
    bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    mime = 'application/zip';
  }
  return FileSaver.instance.saveAs(
    name: '$name.$format',
    bytes: bytes,
    includeExtension: false,
    mimeType: MimeType.custom,
    customMimeType: mime,
  );
}
