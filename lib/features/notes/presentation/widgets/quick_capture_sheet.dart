import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';

NoteDraft quickCaptureDraft(String text, String author) {
  final value = text.trim();
  final lines = value.split('\n');
  final first = lines.first.trim();
  final uri = Uri.tryParse(value);
  final isLink =
      uri != null &&
      ['http', 'https'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      !value.contains(RegExp(r'\s'));
  final title = isLink
      ? uri.host.replaceFirst(RegExp(r'^www\.'), '')
      : first.characters.take(120).toString();
  return NoteDraft(
    title: title,
    content: isLink || first.characters.length > 120
        ? value
        : lines.skip(1).join('\n').trim(),
    color: NoteColor.none,
    authorName: author,
  );
}

Future<bool?> showQuickCaptureSheet({
  required BuildContext context,
  required List<NoteList> lists,
  required String selectedListId,
  required String authorName,
  required Future<void> Function(String listId, NoteDraft draft) onSave,
  required Future<bool> Function(String listId, NoteDraft draft) onMoreOptions,
  String initialText = '',
}) => showLiquidBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _QuickCaptureSheet(
    lists: lists,
    selectedListId: selectedListId,
    authorName: authorName,
    initialText: initialText,
    onSave: onSave,
    onMoreOptions: onMoreOptions,
  ),
);

class _QuickCaptureSheet extends StatefulWidget {
  const _QuickCaptureSheet({
    required this.lists,
    required this.selectedListId,
    required this.authorName,
    required this.initialText,
    required this.onSave,
    required this.onMoreOptions,
  });
  final List<NoteList> lists;
  final String selectedListId;
  final String authorName;
  final String initialText;
  final Future<void> Function(String, NoteDraft) onSave;
  final Future<bool> Function(String, NoteDraft) onMoreOptions;
  @override
  State<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<_QuickCaptureSheet> {
  late final _text = TextEditingController(text: widget.initialText);
  late String _listId =
      widget.lists.any((list) => list.id == widget.selectedListId)
      ? widget.selectedListId
      : widget.lists.first.id;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save({bool moreOptions = false}) async {
    final draft = quickCaptureDraft(_text.text, widget.authorName);
    if (draft.title.isEmpty) {
      setState(() => _error = 'Escribe algo para guardar.');
      return;
    }
    if (draft.content.length > 2048) {
      setState(
        () => _error = 'El texto es demasiado largo. Reduce el contenido a 2048 caracteres.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = moreOptions
          ? await widget.onMoreOptions(_listId, draft)
          : await widget.onSave(_listId, draft).then((_) => true);
      if (mounted && saved) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = notesErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: Padding(
        key: const ValueKey('quick-capture-sheet'),
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Captura rápida',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('quick-capture-text'),
                controller: _text,
                autofocus: true,
                enabled: !_saving,
                minLines: 3,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Escribe una idea, tarea o pega un enlace…',
                  filled: true,
                  fillColor: theme.colorScheme.surface.withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: const ValueKey('quick-capture-list'),
                initialValue: _listId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Guardar en',
                  prefixIcon: Icon(Icons.folder_rounded),
                ),
                items: widget.lists
                    .map(
                      (list) => DropdownMenuItem(
                        value: list.id,
                        child: Text(
                          list.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _listId = value!),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('quick-capture-save'),
                onPressed: _saving ? null : () => _save(),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? 'Guardando…' : 'Guardar'),
              ),
              TextButton(
                key: const ValueKey('quick-capture-more-options'),
                onPressed: _saving ? null : () => _save(moreOptions: true),
                child: const Text('Más opciones'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
