import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

const _checklistLinkLabelMaxLength = 120;
const _checklistLinkUrlMaxLength = 800;

class NoteLinkValue {
  const NoteLinkValue({required this.label, required this.url});

  final String label;
  final String url;
}

class NoteLinkEditResult {
  const NoteLinkEditResult.link(this.value) : removeLink = false;

  const NoteLinkEditResult.remove() : value = null, removeLink = true;

  final NoteLinkValue? value;
  final bool removeLink;
}

enum NoteLinkAction { open, edit }

Future<NoteLinkAction?> showNoteLinkActionMenu(
  BuildContext context, {
  required Offset globalPosition,
}) {
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return Future.value();
  final position = overlay.globalToLocal(globalPosition);
  final colorScheme = Theme.of(context).colorScheme;
  return showMenu<NoteLinkAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    ),
    color: colorScheme.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    constraints: const BoxConstraints(minWidth: 168, maxWidth: 196),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: const [
      PopupMenuItem(
        key: ValueKey('open-note-link-action'),
        value: NoteLinkAction.open,
        height: 42,
        child: Row(
          children: [
            Icon(Icons.open_in_new_rounded, size: 19),
            SizedBox(width: 10),
            Expanded(child: Text('Abrir')),
          ],
        ),
      ),
      PopupMenuItem(
        key: ValueKey('edit-note-link-action'),
        value: NoteLinkAction.edit,
        height: 42,
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 19),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Editar nombre',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

String normalizeNoteLink(String input) {
  final link = input.trim();
  if (link.isEmpty) return link;
  final parsed = Uri.tryParse(link);
  if (parsed?.hasScheme ?? false) return link;
  return 'https://$link';
}

bool isSupportedNoteLink(String input) {
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

NoteLinkValue? noteChecklistLinkFromText(String input) {
  final text = input.trim();
  if (text.startsWith('[') && text.endsWith(')')) {
    final separator = text.lastIndexOf('](');
    if (separator > 1) {
      final label = _unescapeChecklistLinkLabel(text.substring(1, separator));
      final url = text.substring(separator + 2, text.length - 1).trim();
      if (label.isNotEmpty && isSupportedNoteLink(url)) {
        return NoteLinkValue(label: label, url: normalizeNoteLink(url));
      }
    }
  }

  if (isSupportedNoteLink(text)) {
    return NoteLinkValue(label: text, url: normalizeNoteLink(text));
  }
  return null;
}

String noteChecklistDisplayText(String input) =>
    noteChecklistLinkFromText(input)?.label ?? input;

String noteChecklistStoredLink(NoteLinkValue link) {
  final label = link.label
      .trim()
      .replaceAll(r'\', r'\\')
      .replaceAll(']', r'\]');
  return '[$label](${normalizeNoteLink(link.url)})';
}

String _unescapeChecklistLinkLabel(String label) {
  final buffer = StringBuffer();
  var escaped = false;
  for (final rune in label.runes) {
    final character = String.fromCharCode(rune);
    if (escaped) {
      buffer.write(character);
      escaped = false;
    } else if (character == r'\') {
      escaped = true;
    } else {
      buffer.write(character);
    }
  }
  if (escaped) buffer.write(r'\');
  return buffer.toString();
}

Future<NoteLinkEditResult?> showNoteChecklistLinkDialog(
  BuildContext context, {
  required String currentText,
}) {
  final currentLink = noteChecklistLinkFromText(currentText);
  return showNoteLinkDialog(
    context,
    initialLabel: currentLink?.label ?? currentText,
    initialUrl: currentLink?.url ?? '',
    canRemoveLink: currentLink != null,
  );
}

Future<NoteLinkEditResult?> showNoteLinkDialog(
  BuildContext context, {
  required String initialLabel,
  required String initialUrl,
  bool canRemoveLink = false,
}) {
  return showDialog<NoteLinkEditResult>(
    context: context,
    builder: (context) => _NoteLinkEditorDialog(
      initialLabel: initialLabel,
      initialUrl: initialUrl,
      canRemoveLink: canRemoveLink,
    ),
  );
}

class _NoteLinkEditorDialog extends StatefulWidget {
  const _NoteLinkEditorDialog({
    required this.initialLabel,
    required this.initialUrl,
    required this.canRemoveLink,
  });

  final String initialLabel;
  final String initialUrl;
  final bool canRemoveLink;

  @override
  State<_NoteLinkEditorDialog> createState() => _NoteLinkEditorDialogState();
}

class _NoteLinkEditorDialogState extends State<_NoteLinkEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController = TextEditingController(
    text: widget.initialLabel,
  );
  late final TextEditingController _urlController = TextEditingController(
    text: widget.initialUrl,
  );

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('note-link-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      iconPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      icon: const Icon(Icons.link_rounded),
      titlePadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      title: Text(widget.canRemoveLink ? 'Editar vínculo' : 'Agregar vínculo'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('note-link-label-field'),
              controller: _labelController,
              autofocus: true,
              maxLength: _checklistLinkLabelMaxLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre visible',
                hintText: 'Ej. Comprar Wegovy',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe un nombre para el vínculo.'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('note-link-url-field'),
              controller: _urlController,
              maxLength: _checklistLinkUrlMaxLength,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.url],
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://ejemplo.cl',
                prefixIcon: Icon(Icons.language_rounded),
              ),
              validator: (value) => isSupportedNoteLink(value ?? '')
                  ? null
                  : 'Ingresa una URL válida.',
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.canRemoveLink)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('remove-note-link-button'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const NoteLinkEditResult.remove()),
                    child: const Text('Quitar vínculo'),
                  ),
                ),
              if (widget.canRemoveLink) const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('cancel-note-link-button'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('save-note-link-button'),
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      NoteLinkEditResult.link(
        NoteLinkValue(
          label: _labelController.text.trim(),
          url: normalizeNoteLink(_urlController.text),
        ),
      ),
    );
  }
}

class NoteChecklistLinkText extends StatelessWidget {
  const NoteChecklistLinkText({
    required this.text,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.onOpenUrl,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final ValueChanged<String>? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final link = noteChecklistLinkFromText(text);
    if (link == null) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style);
    }

    final baseDecoration = style?.decoration;
    final decoration =
        baseDecoration == null || baseDecoration == TextDecoration.none
        ? TextDecoration.underline
        : TextDecoration.combine([baseDecoration, TextDecoration.underline]);
    return Semantics(
      link: true,
      label: link.label,
      hint: 'Abre ${link.url}',
      child: InkWell(
        key: ValueKey('checklist-link-${link.url}'),
        onTap: () {
          final callback = onOpenUrl;
          if (callback != null) {
            callback(link.url);
          } else {
            openNoteLink(link.url);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  link.label,
                  maxLines: maxLines,
                  overflow: overflow,
                  style: style?.copyWith(decoration: decoration),
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.open_in_new_rounded, size: 15, color: style?.color),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openNoteLink(String link) async {
  final uri = Uri.tryParse(normalizeNoteLink(link));
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class NoteLinkMetadata {
  const NoteLinkMetadata({
    required this.url,
    required this.siteName,
    this.title,
    this.description,
    this.imageUrl,
  });

  final String url;
  final String siteName;
  final String? title;
  final String? description;
  final String? imageUrl;
}

typedef NoteLinkMetadataLoader = Future<NoteLinkMetadata> Function(String url);

final Map<String, Future<NoteLinkMetadata>> _metadataCache = {};

const _linkPreviewUserAgent =
    'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/136.0 Mobile Safari/537.36';

Future<NoteLinkMetadata> loadNoteLinkMetadata(String input) {
  final url = normalizeNoteLink(input);
  return _metadataCache.putIfAbsent(url, () => _fetchNoteLinkMetadata(url));
}

Future<NoteLinkMetadata> _fetchNoteLinkMetadata(String url) async {
  final uri = Uri.parse(url);
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return _fallbackMetadata(uri);
  }

  try {
    final response = await Dio().get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 5,
        headers: const {
          'Accept': 'text/html,application/xhtml+xml',
          // Several commerce sites reject non-browser user agents even though
          // their public metadata is otherwise available.
          'User-Agent': _linkPreviewUserAgent,
          'Accept-Language': 'es-CL,es;q=0.9,en;q=0.8',
        },
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    final body = response.data;
    if (body == null || body.isEmpty) return _fallbackMetadata(uri);

    final pageUri = response.realUri;
    final document = html_parser.parse(body);
    String? meta(String key, String value) => document
        .querySelector('meta[$key="$value"]')
        ?.attributes['content']
        ?.trim();
    final title = _firstNotEmpty([
      meta('property', 'og:title'),
      meta('name', 'twitter:title'),
      document.querySelector('title')?.text.trim(),
    ]);
    final description = _firstNotEmpty([
      meta('property', 'og:description'),
      meta('name', 'twitter:description'),
      meta('name', 'description'),
    ]);
    final imageCandidate = _firstNotEmpty([
      meta('property', 'og:image'),
      meta('property', 'og:image:url'),
      meta('property', 'og:image:secure_url'),
      meta('name', 'twitter:image'),
      meta('name', 'twitter:image:src'),
      document
          .querySelector(
            'link[rel~="apple-touch-icon"], link[rel~="icon"], '
            'link[rel="shortcut icon"]',
          )
          ?.attributes['href']
          ?.trim(),
    ]);
    final resolvedImage = imageCandidate == null
        ? null
        : pageUri.resolve(imageCandidate);
    final imageUri =
        resolvedImage != null &&
            (resolvedImage.scheme == 'http' || resolvedImage.scheme == 'https')
        ? resolvedImage.toString()
        : null;
    final siteName = _firstNotEmpty([
      meta('property', 'og:site_name'),
      pageUri.host.replaceFirst(RegExp(r'^www\.'), ''),
    ])!;
    return NoteLinkMetadata(
      url: url,
      siteName: siteName,
      title: title,
      description: description,
      imageUrl: imageUri,
    );
  } catch (_) {
    return _fallbackMetadata(uri);
  }
}

String? _firstNotEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

NoteLinkMetadata _fallbackMetadata(Uri uri) => NoteLinkMetadata(
  url: uri.toString(),
  siteName: uri.host.isEmpty
      ? uri.toString()
      : uri.host.replaceFirst(RegExp(r'^www\.'), ''),
);

class NoteLinkPreviewCard extends StatefulWidget {
  const NoteLinkPreviewCard({
    required this.url,
    this.onDismiss,
    this.onOpenUrl,
    this.metadataLoader = loadNoteLinkMetadata,
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  });

  final String url;
  final VoidCallback? onDismiss;
  final ValueChanged<String>? onOpenUrl;
  final NoteLinkMetadataLoader metadataLoader;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  State<NoteLinkPreviewCard> createState() => _NoteLinkPreviewCardState();
}

class _NoteLinkPreviewCardState extends State<NoteLinkPreviewCard> {
  late Future<NoteLinkMetadata> _metadata = widget.metadataLoader(widget.url);

  @override
  void didUpdateWidget(covariant NoteLinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.metadataLoader != widget.metadataLoader) {
      _metadata = widget.metadataLoader(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NoteLinkMetadata>(
      future: _metadata,
      builder: (context, snapshot) {
        final uri = Uri.tryParse(normalizeNoteLink(widget.url));
        final metadata =
            snapshot.data ??
            NoteLinkMetadata(
              url: widget.url,
              siteName:
                  uri?.host.replaceFirst(RegExp(r'^www\.'), '') ?? widget.url,
            );
        return _buildCard(context, metadata, snapshot.connectionState);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    NoteLinkMetadata metadata,
    ConnectionState connectionState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.foregroundColor ?? colorScheme.onSurface;
    final background = widget.backgroundColor ?? colorScheme.surfaceContainer;
    final title = metadata.title ?? metadata.siteName;
    final imageUrl = metadata.imageUrl;
    return Semantics(
      link: true,
      label: 'Vista previa de $title',
      child: Material(
        key: ValueKey('note-link-preview-${widget.url}'),
        color: background,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final callback = widget.onOpenUrl;
            if (callback != null) {
              callback(widget.url);
            } else {
              openNoteLink(widget.url);
            }
          },
          child: Container(
            // The title can occupy two lines alongside a description and the
            // site name. This needs slightly more than the old 96px height
            // at narrow widths, while keeping a finite height for the
            // cross-axis-stretching row.
            height: 104,
            decoration: BoxDecoration(
              border: Border.all(color: foreground.withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 92,
                  child: imageUrl == null
                      ? _LinkImageFallback(
                          foregroundColor: foreground,
                          isLoading: connectionState == ConnectionState.waiting,
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _LinkImageFallback(
                                foregroundColor: foreground,
                                isLoading: false,
                              ),
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (metadata.description case final description?) ...[
                          const SizedBox(height: 3),
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: foreground.withValues(alpha: 0.7),
                                ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          metadata.siteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.64),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.onDismiss case final onDismiss?)
                  Align(
                    alignment: Alignment.topCenter,
                    child: IconButton(
                      key: ValueKey('dismiss-note-link-preview-${widget.url}'),
                      tooltip: 'Quitar vista previa',
                      onPressed: onDismiss,
                      visualDensity: VisualDensity.compact,
                      color: foreground.withValues(alpha: 0.72),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: foreground.withValues(alpha: 0.62),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkImageFallback extends StatelessWidget {
  const _LinkImageFallback({
    required this.foregroundColor,
    required this.isLoading,
  });

  final Color foregroundColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: foregroundColor.withValues(alpha: 0.08),
      child: Center(
        child: isLoading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor.withValues(alpha: 0.62),
                ),
              )
            : Icon(
                Icons.language_rounded,
                size: 30,
                color: foregroundColor.withValues(alpha: 0.62),
              ),
      ),
    );
  }
}
