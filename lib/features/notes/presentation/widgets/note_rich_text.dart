import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';

const noteContentMaxLength = 500;

final RegExp _visibleNoteUrlPattern = RegExp(
  r'(?:(?:https?://)|(?:www\.))[^\s<>()]+',
  caseSensitive: false,
);

class NoteRichContent {
  const NoteRichContent({required this.plainText, required this.deltaJson});

  final String plainText;
  final String deltaJson;
}

Document noteDocumentFromContent({
  required String plainText,
  String? deltaJson,
}) {
  if (deltaJson != null && deltaJson.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(deltaJson);
      if (decoded is List) {
        return _documentWithDetectedLinks(Document.fromJson(decoded));
      }
    } catch (_) {
      // Fall back to the compatible plain-text description below.
    }
  }
  return _documentWithDetectedLinks(
    Document.fromJson([
      if (plainText.isNotEmpty) {'insert': plainText},
      {'insert': '\n'},
    ]),
  );
}

Document _documentWithDetectedLinks(Document document) {
  final linkedOperations = <Map<String, dynamic>>[];

  for (final rawOperation in document.toDelta().toJson()) {
    final operation = Map<String, dynamic>.from(rawOperation);
    final insertion = operation['insert'];
    final attributes = operation['attributes'] is Map
        ? Map<String, dynamic>.from(operation['attributes'] as Map)
        : <String, dynamic>{};
    if (insertion is! String || attributes.containsKey(Attribute.link.key)) {
      linkedOperations.add(operation);
      continue;
    }

    var cursor = 0;
    for (final match in _visibleNoteUrlPattern.allMatches(insertion)) {
      var linkEnd = match.end;
      while (linkEnd > match.start &&
          '.,;:!?'.contains(insertion.substring(linkEnd - 1, linkEnd))) {
        linkEnd--;
      }
      if (linkEnd == match.start) continue;

      if (cursor < match.start) {
        linkedOperations.add(
          _textOperation(insertion.substring(cursor, match.start), attributes),
        );
      }
      final visibleLink = insertion.substring(match.start, linkEnd);
      linkedOperations.add(
        _textOperation(visibleLink, {
          ...attributes,
          Attribute.link.key: _launchableNoteLink(visibleLink),
        }),
      );
      cursor = linkEnd;
    }

    if (cursor < insertion.length) {
      linkedOperations.add(
        _textOperation(insertion.substring(cursor), attributes),
      );
    }
  }

  return Document.fromJson(linkedOperations);
}

Map<String, dynamic> _textOperation(
  String text,
  Map<String, dynamic> attributes,
) => {'insert': text, if (attributes.isNotEmpty) 'attributes': attributes};

String _launchableNoteLink(String link) {
  final trimmedLink = link.trim();
  return trimmedLink.toLowerCase().startsWith('www.')
      ? 'https://$trimmedLink'
      : trimmedLink;
}

bool _isSupportedNoteLink(String input) {
  final link = input.trim();
  if (link.isEmpty || link.contains(RegExp(r'\s'))) return false;

  final parsed = Uri.tryParse(link);
  if (parsed == null) return false;
  if (parsed.hasScheme) {
    switch (parsed.scheme.toLowerCase()) {
      case 'http':
      case 'https':
        return parsed.host.isNotEmpty;
      case 'mailto':
      case 'tel':
        return parsed.path.isNotEmpty;
      default:
        return false;
    }
  }

  final webLink = Uri.tryParse('https://$link');
  return webLink != null &&
      webLink.host.contains('.') &&
      !webLink.host.startsWith('.') &&
      !webLink.host.endsWith('.');
}

NoteRichContent noteRichContentFromDocument(Document document) {
  return NoteRichContent(
    plainText: document.toPlainText().trim(),
    deltaJson: jsonEncode(document.toDelta().toJson()),
  );
}

NoteRichContent normalizeNoteRichContent(NoteRichContent content) {
  final document = noteDocumentFromContent(
    plainText: content.plainText,
    deltaJson: content.deltaJson,
  );
  final operations = document.toDelta().toJson();
  final firstLetterPattern = RegExp(r'[a-záéíóúüñ]', caseSensitive: false);
  for (final operation in operations) {
    final insertion = operation['insert'];
    if (insertion is! String) continue;
    final firstLetter = firstLetterPattern.firstMatch(insertion);
    if (firstLetter == null) continue;
    final letter = firstLetter.group(0)!;
    final uppercaseLetter = letter.toUpperCase();
    if (letter != uppercaseLetter) {
      operation['insert'] = insertion.replaceRange(
        firstLetter.start,
        firstLetter.end,
        uppercaseLetter,
      );
    }
    break;
  }
  return noteRichContentFromDocument(Document.fromJson(operations));
}

class NoteRichTextEditor extends StatefulWidget {
  const NoteRichTextEditor({
    required this.initialPlainText,
    required this.onChanged,
    this.initialDeltaJson,
    this.autoFocus = false,
    this.minEditorHeight = 118,
    this.maxEditorHeight = 170,
    this.editorKey,
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  });

  final String initialPlainText;
  final String? initialDeltaJson;
  final ValueChanged<NoteRichContent> onChanged;
  final bool autoFocus;
  final double minEditorHeight;
  final double maxEditorHeight;
  final Key? editorKey;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  State<NoteRichTextEditor> createState() => _NoteRichTextEditorState();
}

class _NoteRichTextEditorState extends State<NoteRichTextEditor> {
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode(debugLabel: 'note-detail-editor');
  final ScrollController _scrollController = ScrollController();
  late int _characterCount;
  bool _isCapitalizingInitialLetter = false;

  @override
  void initState() {
    super.initState();
    final initialContent = normalizeNoteRichContent(
      NoteRichContent(
        plainText: widget.initialPlainText,
        deltaJson:
            widget.initialDeltaJson ??
            noteRichContentFromDocument(
              noteDocumentFromContent(plainText: widget.initialPlainText),
            ).deltaJson,
      ),
    );
    final document = noteDocumentFromContent(
      plainText: initialContent.plainText,
      deltaJson: initialContent.deltaJson,
    );
    _controller = QuillController(
      document: document,
      selection: TextSelection.collapsed(
        offset: document.length > 0 ? document.length - 1 : 0,
      ),
    )..addListener(_handleDocumentChanged);
    _characterCount = _plainCharacterCount(document);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleDocumentChanged)
      ..dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDocumentChanged() {
    if (_isCapitalizingInitialLetter) return;
    _capitalizeDocumentInitialLetter();
    final content = noteRichContentFromDocument(_controller.document);
    final nextCount = content.plainText.length;
    if (mounted && nextCount != _characterCount) {
      setState(() => _characterCount = nextCount);
    }
    widget.onChanged(content);
  }

  void _capitalizeDocumentInitialLetter() {
    final plainText = _controller.document.toPlainText();
    final capitalizedText = capitalizeInitialLetter(plainText);
    if (plainText == capitalizedText) return;

    var changedIndex = 0;
    while (changedIndex < plainText.length &&
        plainText.codeUnitAt(changedIndex) ==
            capitalizedText.codeUnitAt(changedIndex)) {
      changedIndex++;
    }
    if (changedIndex >= plainText.length) return;

    final selection = _controller.selection;
    final style = _controller.document.collectStyle(changedIndex, 1);
    _isCapitalizingInitialLetter = true;
    try {
      _controller.replaceText(
        changedIndex,
        1,
        capitalizedText.substring(changedIndex, changedIndex + 1),
        selection,
        ignoreFocus: true,
      );
      if (style.isNotEmpty) {
        _controller.formatTextStyle(changedIndex, 1, style);
      }
    } finally {
      _isCapitalizingInitialLetter = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = widget.foregroundColor ?? colorScheme.onSurface;
    final backgroundColor =
        widget.backgroundColor ??
        Theme.of(context).inputDecorationTheme.fillColor ??
        colorScheme.surfaceContainerHighest;
    final isOverLimit = _characterCount > noteContentMaxLength;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: isOverLimit
                ? Border.all(color: colorScheme.error, width: 1.5)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(color: foregroundColor),
                child: QuillEditor.basic(
                  key: widget.editorKey,
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: QuillEditorConfig(
                    autoFocus: widget.autoFocus,
                    minHeight: widget.minEditorHeight,
                    maxHeight: widget.maxEditorHeight,
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
                    placeholder: 'Agrega contexto, pasos o una lista breve…',
                    textCapitalization: TextCapitalization.sentences,
                    scrollBottomInset: 24,
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: foregroundColor.withValues(alpha: 0.14),
              ),
              _NoteFormatToolbar(
                controller: _controller,
                foregroundColor: foregroundColor,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 10),
          child: Text(
            '$_characterCount/$noteContentMaxLength',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isOverLimit
                  ? colorScheme.error
                  : foregroundColor.withValues(alpha: 0.64),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteFormatToolbar extends StatelessWidget {
  const _NoteFormatToolbar({
    required this.controller,
    required this.foregroundColor,
  });

  final QuillController controller;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final attributes = controller.getSelectionStyle().attributes;
        final headerValue = attributes[Attribute.header.key]?.value;
        return SizedBox(
          height: 52,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                _FormatButton(
                  tooltip: 'Título grande',
                  label: 'H1',
                  foregroundColor: foregroundColor,
                  isSelected: headerValue == Attribute.h1.value,
                  onPressed: () => _formatBlock(Attribute.h1),
                ),
                _FormatButton(
                  tooltip: 'Título mediano',
                  label: 'H2',
                  foregroundColor: foregroundColor,
                  isSelected: headerValue == Attribute.h2.value,
                  onPressed: () => _formatBlock(Attribute.h2),
                ),
                _FormatButton(
                  tooltip: 'Texto normal',
                  label: 'Aa',
                  foregroundColor: foregroundColor,
                  isSelected: headerValue == null,
                  onPressed: () => _formatBlock(Attribute.header),
                ),
                Container(
                  width: 1,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: foregroundColor.withValues(alpha: 0.18),
                ),
                _FormatButton(
                  tooltip: 'Negrita',
                  icon: Icons.format_bold_rounded,
                  foregroundColor: foregroundColor,
                  isSelected: attributes.containsKey(Attribute.bold.key),
                  onPressed: () => _toggleInline(Attribute.bold),
                ),
                _FormatButton(
                  tooltip: 'Cursiva',
                  icon: Icons.format_italic_rounded,
                  foregroundColor: foregroundColor,
                  isSelected: attributes.containsKey(Attribute.italic.key),
                  onPressed: () => _toggleInline(Attribute.italic),
                ),
                _FormatButton(
                  tooltip: 'Subrayado',
                  icon: Icons.format_underlined_rounded,
                  foregroundColor: foregroundColor,
                  isSelected: attributes.containsKey(Attribute.underline.key),
                  onPressed: () => _toggleInline(Attribute.underline),
                ),
                _FormatButton(
                  tooltip: 'Tachado',
                  icon: Icons.format_strikethrough_rounded,
                  foregroundColor: foregroundColor,
                  isSelected: attributes.containsKey(
                    Attribute.strikeThrough.key,
                  ),
                  onPressed: () => _toggleInline(Attribute.strikeThrough),
                ),
                Container(
                  width: 1,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: foregroundColor.withValues(alpha: 0.18),
                ),
                QuillToolbarLinkStyleButton(
                  key: const ValueKey('note-hyperlink-button'),
                  controller: controller,
                  options: QuillToolbarLinkStyleButtonOptions(
                    tooltip: 'Agregar o editar hipervínculo',
                    iconData: Icons.link_rounded,
                    validateLink: _isSupportedNoteLink,
                    childBuilder:
                        (dynamic rawOptions, dynamic rawExtraOptions) {
                          final options =
                              rawOptions as QuillToolbarLinkStyleButtonOptions;
                          final extraOptions =
                              rawExtraOptions
                                  as QuillToolbarLinkStyleButtonExtraOptions;
                          return _FormatButton(
                            tooltip:
                                options.tooltip ??
                                'Agregar o editar hipervínculo',
                            icon: options.iconData ?? Icons.link_rounded,
                            foregroundColor: foregroundColor,
                            isSelected: attributes.containsKey(
                              Attribute.link.key,
                            ),
                            onPressed: extraOptions.onPressed!,
                          );
                        },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _formatBlock(Attribute attribute) {
    controller
      ..skipRequestKeyboard = true
      ..formatSelection(attribute);
  }

  void _toggleInline(Attribute attribute) {
    final isSelected = controller.getSelectionStyle().attributes.containsKey(
      attribute.key,
    );
    final nextAttribute = isSelected
        ? Attribute.clone(attribute, null)
        : attribute;
    final selection = controller.selection;
    controller.skipRequestKeyboard = false;

    if (!selection.isCollapsed) {
      controller.formatSelection(nextAttribute);
      return;
    }

    final lineRange = _currentLineRange(selection.extentOffset);
    if (lineRange.isValid && !lineRange.isCollapsed) {
      controller.formatText(
        lineRange.start,
        lineRange.end - lineRange.start,
        nextAttribute,
      );
      return;
    }

    controller.formatSelection(nextAttribute);
  }

  TextRange _currentLineRange(int caretOffset) {
    final plainText = controller.document.toPlainText();
    final contentLength = plainText.endsWith('\n')
        ? plainText.length - 1
        : plainText.length;
    if (contentLength <= 0) return TextRange.empty;

    final caret = caretOffset.clamp(0, contentLength);
    final previousBreak = caret == 0
        ? -1
        : plainText.lastIndexOf('\n', caret - 1);
    final nextBreak = plainText.indexOf('\n', caret);
    final lineEnd = nextBreak == -1 ? contentLength : nextBreak;
    return TextRange(start: previousBreak + 1, end: lineEnd);
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.tooltip,
    required this.isSelected,
    required this.onPressed,
    required this.foregroundColor,
    this.label,
    this.icon,
  }) : assert(label != null || icon != null);

  final String tooltip;
  final bool isSelected;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: isSelected
              ? foregroundColor.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 42,
              height: 40,
              child: Center(
                child: icon == null
                    ? Text(
                        label!,
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Icon(icon, size: 22, color: foregroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NoteRichTextViewer extends StatefulWidget {
  const NoteRichTextViewer({
    required this.plainText,
    this.deltaJson,
    this.foregroundColor,
    this.onLaunchUrl,
    super.key,
  });

  final String plainText;
  final String? deltaJson;
  final Color? foregroundColor;
  final ValueChanged<String>? onLaunchUrl;

  @override
  State<NoteRichTextViewer> createState() => _NoteRichTextViewerState();
}

class _NoteRichTextViewerState extends State<NoteRichTextViewer> {
  late final QuillController _controller = _buildController();

  QuillController _buildController() => QuillController(
    document: noteDocumentFromContent(
      plainText: widget.plainText,
      deltaJson: widget.deltaJson,
    ),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: true,
  );

  @override
  void didUpdateWidget(covariant NoteRichTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plainText != widget.plainText ||
        oldWidget.deltaJson != widget.deltaJson) {
      _controller.document = noteDocumentFromContent(
        plainText: widget.plainText,
        deltaJson: widget.deltaJson,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(color: widget.foregroundColor),
      child: QuillEditor.basic(
        controller: _controller,
        config: QuillEditorConfig(
          scrollable: false,
          padding: EdgeInsets.zero,
          enableInteractiveSelection: true,
          showCursor: false,
          onLaunchUrl: widget.onLaunchUrl,
        ),
      ),
    );
  }
}

int _plainCharacterCount(Document document) {
  return document.toPlainText().trim().length;
}
