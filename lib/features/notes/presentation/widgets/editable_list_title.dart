import 'package:flutter/material.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';

class EditableListTitle extends StatefulWidget {
  const EditableListTitle({
    required this.title,
    required this.onSave,
    this.onEditingChanged,
    super.key,
  });

  final ValueChanged<bool>? onEditingChanged;
  final String title;
  final Future<bool> Function(String)? onSave;

  @override
  State<EditableListTitle> createState() => _EditableListTitleState();
}

class _EditableListTitleState extends State<EditableListTitle> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.title);
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        widget.onSave == null ||
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    final saved = await widget.onSave!(
      capitalizeInitialLetter(_controller.text.trim()),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _editing = false;
    });
    if (saved) {
      widget.onEditingChanged?.call(false);
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (!_editing) {
      return Semantics(
        button: widget.onSave != null,
        child: GestureDetector(
          key: const ValueKey('editable-list-title'),
          onTap: widget.onSave == null
              ? null
              : () {
                  _controller.text = widget.title;
                  _controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _controller.text.length,
                  );
                  setState(() => _editing = true);
                  widget.onEditingChanged?.call(true);
                },
          child: Text(widget.title, style: theme.textTheme.displaySmall),
        ),
      );
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const ValueKey('inline-list-name-field'),
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            maxLength: 50,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [InitialUppercaseTextFormatter()],
            textInputAction: TextInputAction.done,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: 'Nombre de la lista',
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('cancel-inline-list-name'),
                      tooltip: 'Cancelar',
                      onPressed: _saving
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              setState(() => _editing = false);
                              widget.onEditingChanged?.call(false);
                            },
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                    IconButton(
                      key: const ValueKey('save-inline-list-name'),
                      tooltip: 'Guardar',
                      color: colors.primary,
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 21),
                    ),
                  ],
                ),
              ),
              filled: true,
              fillColor: colors.surfaceContainerHigh.withValues(alpha: 0.85),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Escribe un nombre para la lista'
                : null,
            onFieldSubmitted: (_) => _save(),
          ),
        ],
      ),
    );
  }
}
