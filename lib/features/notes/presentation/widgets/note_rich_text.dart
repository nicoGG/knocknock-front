import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_link.dart';

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

class NoteLinkifiedText extends StatefulWidget {
  const NoteLinkifiedText({
    required this.plainText,
    required this.style,
    this.deltaJson,
    this.maxLines,
    this.overflow = TextOverflow.visible,
    this.linkColor,
    this.onOpenUrl,
    super.key,
  });

  final String plainText;
  final String? deltaJson;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final Color? linkColor;
  final ValueChanged<String>? onOpenUrl;

  @override
  State<NoteLinkifiedText> createState() => _NoteLinkifiedTextState();
}

class _NoteLinkifiedTextState extends State<NoteLinkifiedText> {
  final Map<int, TapGestureRecognizer> _linkRecognizers = {};

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(int index, String url) {
    final recognizer = _linkRecognizers.putIfAbsent(
      index,
      TapGestureRecognizer.new,
    );
    recognizer.onTap = () {
      final callback = widget.onOpenUrl;
      if (callback != null) {
        callback(url);
      } else {
        unawaited(openNoteLink(url));
      }
    };
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      _noteLinkifiedTextSpan(
        plainText: widget.plainText,
        deltaJson: widget.deltaJson,
        style: widget.style,
        linkColor: widget.linkColor,
        recognizerFor: _recognizerFor,
      ),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
  }
}

TextSpan noteLinkifiedTextSpan({
  required String plainText,
  required String? deltaJson,
  required TextStyle? style,
  Color? linkColor,
}) => _noteLinkifiedTextSpan(
  plainText: plainText,
  deltaJson: deltaJson,
  style: style,
  linkColor: linkColor,
);

TextSpan _noteLinkifiedTextSpan({
  required String plainText,
  required String? deltaJson,
  required TextStyle? style,
  Color? linkColor,
  TapGestureRecognizer Function(int index, String url)? recognizerFor,
}) {
  final document = noteDocumentFromContent(
    plainText: plainText,
    deltaJson: deltaJson,
  );
  final visibleLength = document.length - 1;
  final spans = <InlineSpan>[];
  var cursor = 0;
  var operationIndex = 0;
  for (final operation in document.toDelta().toJson()) {
    final insertion = operation['insert'];
    if (insertion is! String || cursor >= visibleLength) {
      operationIndex++;
      continue;
    }
    final remaining = visibleLength - cursor;
    final text = insertion.length <= remaining
        ? insertion
        : insertion.substring(0, remaining);
    cursor += text.length;
    final attributes = operation['attributes'];
    final rawLink = attributes is Map ? attributes[Attribute.link.key] : null;
    final link = rawLink is String ? normalizeNoteLink(rawLink) : null;
    final decorations = <TextDecoration>[];
    if (link != null ||
        (attributes is Map && attributes['underline'] == true)) {
      decorations.add(TextDecoration.underline);
    }
    if (attributes is Map && attributes['strike'] == true) {
      decorations.add(TextDecoration.lineThrough);
    }
    spans.add(
      TextSpan(
        text: text,
        style: style?.copyWith(
          color: link == null ? style.color : linkColor ?? style.color,
          fontWeight: attributes is Map && attributes['bold'] == true
              ? FontWeight.w700
              : null,
          fontStyle: attributes is Map && attributes['italic'] == true
              ? FontStyle.italic
              : null,
          decoration: decorations.isEmpty
              ? style.decoration
              : TextDecoration.combine(decorations),
          decorationColor: link == null ? null : linkColor ?? style.color,
          decorationThickness: link == null ? null : 1.25,
        ),
        recognizer: link == null || recognizerFor == null
            ? null
            : recognizerFor(operationIndex, link),
      ),
    );
    operationIndex++;
  }
  return TextSpan(style: style, children: spans);
}

class NoteRichLinkMatch {
  const NoteRichLinkMatch({
    required this.start,
    required this.length,
    required this.label,
    required this.url,
  });

  final int start;
  final int length;
  final String label;
  final String url;
}

NoteRichLinkMatch? noteRichLinkMatchForUrl({
  required String plainText,
  required String? deltaJson,
  required String url,
}) {
  final document = noteDocumentFromContent(
    plainText: plainText,
    deltaJson: deltaJson,
  );
  final normalizedUrl = normalizeNoteLink(url);
  var cursor = 0;
  int? matchStart;
  var matchEnd = 0;
  for (final operation in document.toDelta().toJson()) {
    final insertion = operation['insert'];
    final length = insertion is String ? insertion.length : 1;
    final attributes = operation['attributes'];
    final rawLink = attributes is Map ? attributes[Attribute.link.key] : null;
    final operationUrl = rawLink is String ? normalizeNoteLink(rawLink) : null;
    if (operationUrl == normalizedUrl) {
      matchStart ??= cursor;
      matchEnd = cursor + length;
    } else if (matchStart != null) {
      break;
    }
    cursor += length;
  }
  if (matchStart == null || matchEnd <= matchStart) return null;
  return NoteRichLinkMatch(
    start: matchStart,
    length: matchEnd - matchStart,
    label: document.getPlainText(matchStart, matchEnd - matchStart),
    url: normalizedUrl,
  );
}

NoteRichContent applyNoteRichLinkEdit({
  required String plainText,
  required String? deltaJson,
  required NoteRichLinkMatch match,
  required NoteLinkEditResult result,
}) {
  final document = noteDocumentFromContent(
    plainText: plainText,
    deltaJson: deltaJson,
  );
  if (result.removeLink) {
    document.format(
      match.start,
      match.length,
      Attribute.clone(Attribute.link, null),
    );
  } else {
    final link = result.value!;
    final existingStyle = document.collectStyle(match.start, match.length);
    final attributes = Map<String, dynamic>.from(
      existingStyle.toJson() ?? const <String, dynamic>{},
    )..[Attribute.link.key] = normalizeNoteLink(link.url);
    document.compose(
      Delta()
        ..retain(match.start)
        ..delete(match.length)
        ..insert(link.label, attributes),
      ChangeSource.local,
    );
  }
  final hiddenPreviews = noteHiddenLinkPreviews(deltaJson);
  final links = noteLinksFromDocument(document).toSet();
  hiddenPreviews.retainWhere(links.contains);
  return noteRichContentFromDocument(
    document,
    hiddenLinkPreviews: hiddenPreviews,
  );
}

Document noteDocumentFromContent({
  required String plainText,
  String? deltaJson,
}) {
  if (deltaJson != null && deltaJson.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(deltaJson);
      final operations = switch (decoded) {
        final List<dynamic> value => value,
        final Map<String, dynamic> value when value['ops'] is List =>
          value['ops'] as List<dynamic>,
        _ => null,
      };
      if (operations != null) {
        return _documentWithDetectedLinks(Document.fromJson(operations));
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
          Attribute.link.key: normalizeNoteLink(visibleLink),
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

NoteRichContent noteRichContentFromDocument(
  Document document, {
  Iterable<String> hiddenLinkPreviews = const [],
}) {
  final operations = document.toDelta().toJson();
  final hiddenPreviews = hiddenLinkPreviews.toSet().toList()..sort();
  return NoteRichContent(
    plainText: document.toPlainText().trim(),
    deltaJson: jsonEncode(
      hiddenPreviews.isEmpty
          ? operations
          : <String, dynamic>{
              'ops': operations,
              'hiddenLinkPreviews': hiddenPreviews,
            },
    ),
  );
}

Set<String> noteHiddenLinkPreviews(String? deltaJson) {
  if (deltaJson == null || deltaJson.trim().isEmpty) return <String>{};
  try {
    final decoded = jsonDecode(deltaJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['hiddenLinkPreviews'] is! List) {
      return <String>{};
    }
    return (decoded['hiddenLinkPreviews'] as List<dynamic>)
        .whereType<String>()
        .map(normalizeNoteLink)
        .where((url) => url.isNotEmpty)
        .toSet();
  } catch (_) {
    return <String>{};
  }
}

List<String> noteLinksFromDocument(Document document) {
  final links = <String>[];
  final seen = <String>{};
  for (final rawOperation in document.toDelta().toJson()) {
    final insertion = rawOperation['insert'];
    if (insertion is! String) continue;
    final attributes = rawOperation['attributes'];
    if (attributes is Map && attributes[Attribute.link.key] is String) {
      final link = normalizeNoteLink(attributes[Attribute.link.key] as String);
      if (isSupportedNoteLink(link) && seen.add(link)) links.add(link);
      continue;
    }
    for (final match in _visibleNoteUrlPattern.allMatches(insertion)) {
      var end = match.end;
      while (end > match.start &&
          '.,;:!?'.contains(insertion.substring(end - 1, end))) {
        end--;
      }
      final link = normalizeNoteLink(insertion.substring(match.start, end));
      if (isSupportedNoteLink(link) && seen.add(link)) links.add(link);
    }
  }
  return links;
}

String? notePreviewLinkFromContent({
  required String plainText,
  String? deltaJson,
}) {
  final hidden = noteHiddenLinkPreviews(deltaJson);
  final document = noteDocumentFromContent(
    plainText: plainText,
    deltaJson: deltaJson,
  );
  for (final link in noteLinksFromDocument(document)) {
    final uri = Uri.tryParse(link);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !hidden.contains(link)) {
      return link;
    }
  }
  return null;
}

NoteRichContent normalizeNoteRichContent(NoteRichContent content) {
  final hiddenLinkPreviews = noteHiddenLinkPreviews(content.deltaJson);
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
    if (_startsWithWebLink(insertion, firstLetter.start)) break;
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
  final normalizedDocument = Document.fromJson(operations);
  final links = noteLinksFromDocument(normalizedDocument).toSet();
  hiddenLinkPreviews.retainWhere(links.contains);
  return noteRichContentFromDocument(
    normalizedDocument,
    hiddenLinkPreviews: hiddenLinkPreviews,
  );
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
    this.focusNode,
    this.onFocusChanged,
    this.linkMetadataLoader = loadNoteLinkMetadata,
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
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final NoteLinkMetadataLoader linkMetadataLoader;

  @override
  State<NoteRichTextEditor> createState() => _NoteRichTextEditorState();
}

class _NoteRichTextEditorState extends State<NoteRichTextEditor> {
  late final QuillController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  final ScrollController _scrollController = ScrollController();
  late int _characterCount;
  late final Set<String> _hiddenLinkPreviews;
  bool _isCapitalizingInitialLetter = false;
  bool _isCapitalizationScheduled = false;
  bool _isApplyingLinkEdit = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode =
        widget.focusNode ?? FocusNode(debugLabel: 'note-detail-editor');
    _focusNode.addListener(_handleFocusChanged);
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
    _hiddenLinkPreviews = noteHiddenLinkPreviews(initialContent.deltaJson);
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
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() =>
      widget.onFocusChanged?.call(_focusNode.hasFocus);

  void _handleDocumentChanged() {
    if (_isCapitalizingInitialLetter || _isApplyingLinkEdit) return;
    _scheduleInitialCapitalization();
    _notifyContentChanged();
  }

  void _scheduleInitialCapitalization() {
    if (_isCapitalizationScheduled) return;
    _isCapitalizationScheduled = true;
    scheduleMicrotask(() {
      _isCapitalizationScheduled = false;
      if (!mounted || !_capitalizeDocumentInitialLetter()) return;
      _notifyContentChanged();
    });
  }

  void _notifyContentChanged() {
    final links = noteLinksFromDocument(_controller.document).toSet();
    _hiddenLinkPreviews.retainWhere(links.contains);
    final content = noteRichContentFromDocument(
      _controller.document,
      hiddenLinkPreviews: _hiddenLinkPreviews,
    );
    final nextCount = content.plainText.length;
    if (mounted && nextCount != _characterCount) {
      setState(() => _characterCount = nextCount);
    }
    widget.onChanged(content);
  }

  bool _capitalizeDocumentInitialLetter() {
    final plainText = _controller.document.toPlainText();
    final firstLetter = RegExp(
      r'[a-záéíóúüñ]',
      caseSensitive: false,
    ).firstMatch(plainText);
    if (firstLetter != null &&
        _startsWithWebLink(plainText, firstLetter.start)) {
      return false;
    }
    final capitalizedText = capitalizeInitialLetter(plainText);
    if (plainText == capitalizedText) return false;

    var changedIndex = 0;
    while (changedIndex < plainText.length &&
        plainText.codeUnitAt(changedIndex) ==
            capitalizedText.codeUnitAt(changedIndex)) {
      changedIndex++;
    }
    if (changedIndex >= plainText.length) return false;

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
    return true;
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
    final previewUrl = _previewUrl;
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
                onEditLink: () => _editLink(context),
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
        if (previewUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: NoteLinkPreviewCard(
              url: previewUrl,
              metadataLoader: widget.linkMetadataLoader,
              foregroundColor: foregroundColor,
              backgroundColor: backgroundColor,
              onDismiss: () => _dismissPreview(previewUrl),
            ),
          ),
      ],
    );
  }

  String? get _previewUrl {
    for (final link in noteLinksFromDocument(_controller.document)) {
      final uri = Uri.tryParse(link);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          !_hiddenLinkPreviews.contains(link)) {
        return link;
      }
    }
    return null;
  }

  void _dismissPreview(String url) {
    setState(() => _hiddenLinkPreviews.add(url));
    widget.onChanged(
      noteRichContentFromDocument(
        _controller.document,
        hiddenLinkPreviews: _hiddenLinkPreviews,
      ),
    );
  }

  Future<void> _editLink(BuildContext context) async {
    final target = _noteLinkTarget(_controller);
    final result = await showNoteLinkDialog(
      context,
      initialLabel: target.text,
      initialUrl: target.url ?? '',
      canRemoveLink: target.url != null,
    );
    if (!mounted || result == null) return;

    if (result.removeLink) {
      _controller.formatText(
        target.start,
        target.length,
        Attribute.clone(Attribute.link, null),
      );
      _notifyContentChanged();
      if (mounted) setState(() {});
      return;
    }

    final link = result.value!;
    final existingStyle = target.length == 0
        ? const Style()
        : _controller.document.collectStyle(target.start, target.length);
    final attributes = Map<String, dynamic>.from(
      existingStyle.toJson() ?? const <String, dynamic>{},
    )..[Attribute.link.key] = link.url;
    final change = Delta()
      ..retain(target.start)
      ..delete(target.length)
      ..insert(link.label, attributes);
    _isApplyingLinkEdit = true;
    try {
      _controller.compose(change, _controller.selection, ChangeSource.local);
      _controller.updateSelection(
        TextSelection.collapsed(offset: target.start + link.label.length),
        ChangeSource.local,
      );
    } finally {
      _isApplyingLinkEdit = false;
    }
    _notifyContentChanged();
    if (mounted) setState(() {});
  }
}

class _NoteFormatToolbar extends StatelessWidget {
  const _NoteFormatToolbar({
    required this.controller,
    required this.foregroundColor,
    required this.onEditLink,
  });

  final QuillController controller;
  final Color foregroundColor;
  final VoidCallback onEditLink;

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
                KeyedSubtree(
                  key: const ValueKey('note-hyperlink-button'),
                  child: _FormatButton(
                    tooltip: 'Nombrar o editar vínculo',
                    icon: Icons.link_rounded,
                    foregroundColor: foregroundColor,
                    isSelected: attributes.containsKey(Attribute.link.key),
                    onPressed: onEditLink,
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

class _NoteLinkTarget {
  const _NoteLinkTarget({
    required this.start,
    required this.length,
    required this.text,
    required this.url,
  });

  final int start;
  final int length;
  final String text;
  final String? url;
}

class _NoteLinkSegment {
  const _NoteLinkSegment({
    required this.start,
    required this.end,
    required this.url,
  });

  final int start;
  final int end;
  final String? url;
}

_NoteLinkTarget _noteLinkTarget(QuillController controller) {
  final documentLength = controller.document.length - 1;
  final selection = controller.selection;
  final selectionStart = selection.start.clamp(0, documentLength);
  final selectionEnd = selection.end.clamp(selectionStart, documentLength);
  final segments = <_NoteLinkSegment>[];
  var cursor = 0;
  for (final operation in controller.document.toDelta().toJson()) {
    final insertion = operation['insert'];
    final length = insertion is String ? insertion.length : 1;
    final attributes = operation['attributes'];
    final rawLink = attributes is Map ? attributes[Attribute.link.key] : null;
    segments.add(
      _NoteLinkSegment(
        start: cursor,
        end: cursor + length,
        url: rawLink is String ? normalizeNoteLink(rawLink) : null,
      ),
    );
    cursor += length;
  }

  var linkedIndex = segments.indexWhere(
    (segment) =>
        segment.url != null &&
        selectionStart >= segment.start &&
        selectionStart < segment.end,
  );
  if (linkedIndex == -1 && selectionStart > 0) {
    linkedIndex = segments.indexWhere(
      (segment) =>
          segment.url != null &&
          selectionStart - 1 >= segment.start &&
          selectionStart - 1 < segment.end,
    );
  }
  if (linkedIndex != -1) {
    final url = segments[linkedIndex].url!;
    var first = linkedIndex;
    var last = linkedIndex;
    while (first > 0 &&
        segments[first - 1].end == segments[first].start &&
        segments[first - 1].url == url) {
      first--;
    }
    while (last + 1 < segments.length &&
        segments[last].end == segments[last + 1].start &&
        segments[last + 1].url == url) {
      last++;
    }
    final start = segments[first].start;
    final end = segments[last].end;
    return _NoteLinkTarget(
      start: start,
      length: end - start,
      text: controller.document.getPlainText(start, end - start),
      url: url,
    );
  }

  final length = selectionEnd - selectionStart;
  final text = length == 0
      ? ''
      : controller.document.getPlainText(selectionStart, length);
  return _NoteLinkTarget(
    start: selectionStart,
    length: length,
    text: text,
    url: isSupportedNoteLink(text) ? normalizeNoteLink(text) : null,
  );
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
    this.onEditLink,
    this.onTapOutsideLink,
    this.showLinkPreview = true,
    this.linkMetadataLoader = loadNoteLinkMetadata,
    super.key,
  });

  final String plainText;
  final String? deltaJson;
  final Color? foregroundColor;
  final ValueChanged<String>? onLaunchUrl;
  final ValueChanged<String>? onEditLink;
  final VoidCallback? onTapOutsideLink;
  final bool showLinkPreview;
  final NoteLinkMetadataLoader linkMetadataLoader;

  @override
  State<NoteRichTextViewer> createState() => _NoteRichTextViewerState();
}

class _NoteRichTextViewerState extends State<NoteRichTextViewer> {
  late final QuillController _controller = _buildController();
  Offset? _lastPointerPosition;
  bool _linkHandledForPointer = false;

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

  void _openLink(String url) {
    final callback = widget.onLaunchUrl;
    if (callback != null) {
      callback(url);
    } else {
      unawaited(openNoteLink(url));
    }
  }

  Future<void> _handleLinkTap(String url) async {
    _linkHandledForPointer = true;
    final editLink = widget.onEditLink;
    if (editLink == null) {
      _openLink(url);
      return;
    }
    final renderObject = context.findRenderObject();
    final fallbackPosition = renderObject is RenderBox
        ? renderObject.localToGlobal(renderObject.size.center(Offset.zero))
        : Offset.zero;
    final action = await showNoteLinkActionMenu(
      context,
      globalPosition: _lastPointerPosition ?? fallbackPosition,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case NoteLinkAction.open:
        _openLink(url);
        break;
      case NoteLinkAction.edit:
        editLink(url);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = widget.showLinkPreview
        ? notePreviewLinkFromContent(
            plainText: widget.plainText,
            deltaJson: widget.deltaJson,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefaultTextStyle.merge(
          style: TextStyle(color: widget.foregroundColor),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _lastPointerPosition = event.position;
              _linkHandledForPointer = false;
            },
            onPointerUp: (_) {
              final callback = widget.onTapOutsideLink;
              if (callback == null) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_linkHandledForPointer) callback();
              });
            },
            child: QuillEditor.basic(
              controller: _controller,
              config: QuillEditorConfig(
                scrollable: false,
                padding: EdgeInsets.zero,
                enableInteractiveSelection: true,
                showCursor: false,
                onLaunchUrl: _handleLinkTap,
              ),
            ),
          ),
        ),
        if (previewUrl != null) ...[
          const SizedBox(height: 10),
          NoteLinkPreviewCard(
            url: previewUrl,
            metadataLoader: widget.linkMetadataLoader,
            foregroundColor: widget.foregroundColor,
            backgroundColor: widget.foregroundColor?.withValues(alpha: 0.08),
            onOpenUrl: widget.onLaunchUrl,
          ),
        ],
      ],
    );
  }
}

int _plainCharacterCount(Document document) {
  return document.toPlainText().trim().length;
}

bool _startsWithWebLink(String text, int offset) {
  final remainder = text.substring(offset).toLowerCase();
  return remainder.startsWith('http://') ||
      remainder.startsWith('https://') ||
      remainder.startsWith('www.');
}
