import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_drawing.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_drawing_canvas.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';

class NoteVersionPreview extends StatelessWidget {
  const NoteVersionPreview({required this.note, super.key});
  final Note note;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final drawing = NoteDrawing.decode(note.contentDelta);
    final asset = NoteCategoryStyle.assetPath(note.category);
    final base = asset == null
        ? NotePalette.color(note.color)
        : NoteCategoryStyle.baseColor(note.category);
    final foreground = asset == null
        ? const Color(0xFF282621)
        : NoteCategoryStyle.foregroundColor(note.category);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: base,
        image: asset == null
            ? null
            : DecorationImage(
                image: AssetImage(asset),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: .20),
                  BlendMode.darken,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: foreground),
          ),
          if (note.financialEntry case final entry?) ...[
            const SizedBox(height: 10),
            Text(
              entry.formattedAmount,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            if (entry.paymentMethod != null)
              Text(entry.paymentLabel, style: TextStyle(color: foreground)),
            if (entry.counterparty.isNotEmpty)
              Text(entry.counterparty, style: TextStyle(color: foreground)),
            if (entry.payments.isNotEmpty)
              Text(
                'Abonado: ${FinancialEntry.formatAmount(entry.paidMinor, entry.currency)} · Saldo: ${FinancialEntry.formatAmount(entry.balanceMinor, entry.currency)}',
                style: TextStyle(color: foreground),
              ),
            for (final payment in entry.payments)
              Text(
                '${DateFormat('dd-MM-yyyy').format(payment.date)}: ${FinancialEntry.formatAmount(payment.amountMinor, entry.currency)}${payment.detail.isEmpty ? '' : ' · ${payment.detail}'}${payment.paymentMethod == null ? '' : ' · ${payment.paymentLabel}'}',
                style: TextStyle(color: foreground),
              ),
            if (entry.participants.isNotEmpty)
              Text(
                'Pagó: ${entry.paidBy} · ${entry.participants.join(', ')}',
                style: TextStyle(color: foreground),
              ),
            Text(entry.statusLabel, style: TextStyle(color: foreground)),
          ],
          if (drawing != null) ...[
            const SizedBox(height: 10),
            NoteDrawingView(drawing: drawing, backgroundColor: colors.surface),
          ] else if (note.content.isNotEmpty) ...[
            const SizedBox(height: 10),
            NoteLinkifiedText(
              plainText: note.content,
              deltaJson: note.contentDelta,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: foreground.withValues(alpha: .85)),
            ),
          ],
          for (final item in note.checklist)
            Padding(
              padding: EdgeInsets.only(top: 6, left: item.indent * 14.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.isCompleted
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 18,
                    color: foreground.withValues(alpha: .8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        color: foreground,
                        decoration: item.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
