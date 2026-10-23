import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/receipt_total.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_download.dart';
import 'package:pdfrx/pdfrx.dart';

const _receiptChannel = MethodChannel('cl.nocknock/receipt_scanner');
bool get receiptImageScanningSupported =>
    !kIsWeb &&
    [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ].contains(defaultTargetPlatform);

Future<String> _recognize(Uint8List bytes) async =>
    await _receiptChannel.invokeMethod<String>('recognize', bytes) ?? '';

Future<int?> scanReceiptTotal(
  NoteAttachment attachment,
  String currency,
) async {
  final bytes = decodeNoteAttachmentBytes(attachment);
  if (!attachment.isPdf) {
    if (!receiptImageScanningSupported) return null;
    return receiptTotalMinor(await _recognize(bytes), currency);
  }
  final document = await PdfDocument.openData(bytes);
  try {
    final texts = <String>[];
    for (final page in document.pages.take(5)) {
      var text = (await page.loadText())?.fullText ?? '';
      if (text.trim().isEmpty && receiptImageScanningSupported) {
        final scale = 1600 / page.width;
        final rendered = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );
        if (rendered == null) continue;
        try {
          final image = await rendered.createImage();
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            if (png != null) text = await _recognize(png.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        } finally {
          rendered.dispose();
        }
      }
      texts.add(text);
    }
    return receiptTotalMinor(texts.join('\n'), currency);
  } finally {
    await document.dispose();
  }
}

/// Detection never silently replaces an amount the user already entered.
Future<int?> suggestReceiptTotal(
  BuildContext context,
  NoteAttachment attachment,
  String currency,
) async {
  int? total;
  try {
    total = await scanReceiptTotal(attachment, currency);
  } catch (_) {
    /* Attachment remains available even when recognition fails. */
  }
  if (!context.mounted) return null;
  if (total == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Comprobante adjunto. No se pudo identificar un total único; ingresa el monto manualmente.',
        ),
      ),
    );
    return null;
  }
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Total detectado'),
      content: Text(
        '${FinancialEntry.formatAmount(total!, currency)}\nRevisa que coincida con el total de la boleta.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Conservar monto'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, total),
          child: const Text('Usar total'),
        ),
      ],
    ),
  );
}
