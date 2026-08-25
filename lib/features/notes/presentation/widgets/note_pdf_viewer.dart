import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_download.dart';
import 'package:pdfrx/pdfrx.dart';

typedef NotePdfViewBuilder =
    Widget Function(Uint8List bytes, String sourceName);

Future<void> showNotePdfViewer(
  BuildContext context, {
  required NoteAttachment attachment,
  required Future<NoteAttachment> Function(String attachmentId)? loader,
  NoteAttachmentSaver? saver,
  NotePdfViewBuilder? pdfViewBuilder,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => NotePdfAttachmentViewer(
      attachment: attachment,
      loader: loader,
      saver: saver,
      pdfViewBuilder: pdfViewBuilder,
    ),
  ),
);

class NotePdfAttachmentViewer extends StatefulWidget {
  const NotePdfAttachmentViewer({
    required this.attachment,
    required this.loader,
    this.saver,
    this.pdfViewBuilder,
    super.key,
  });

  final NoteAttachment attachment;
  final Future<NoteAttachment> Function(String attachmentId)? loader;
  final NoteAttachmentSaver? saver;
  final NotePdfViewBuilder? pdfViewBuilder;

  @override
  State<NotePdfAttachmentViewer> createState() =>
      _NotePdfAttachmentViewerState();
}

class _NotePdfAttachmentViewerState extends State<NotePdfAttachmentViewer> {
  late Future<_LoadedPdf> _loadedPdf;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    _loadedPdf = _loadPdf();
  }

  Future<_LoadedPdf> _loadPdf() async {
    final source = widget.attachment.dataBase64 != null
        ? widget.attachment
        : await widget.loader?.call(widget.attachment.id) ?? widget.attachment;
    final bytes = decodeNoteAttachmentBytes(source);
    if (!source.isPdf ||
        bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('El archivo no es un PDF válido');
    }
    return _LoadedPdf(attachment: source, bytes: bytes);
  }

  Future<void> _download() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final loaded = await _loadedPdf;
      final result = await (widget.saver ?? saveNoteAttachmentToDevice)(
        loaded.attachment,
        loaded.bytes,
      );
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF guardado en el dispositivo')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar el PDF')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('pdf-attachment-viewer'),
    backgroundColor: const Color(0xFF202124),
    appBar: AppBar(
      backgroundColor: const Color(0xFF202124),
      foregroundColor: Colors.white,
      title: Text(
        widget.attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          key: ValueKey('download-pdf-${widget.attachment.id}'),
          tooltip: 'Guardar en el dispositivo',
          onPressed: _isSaving ? null : _download,
          icon: _isSaving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: FutureBuilder<_LoadedPdf>(
      future: _loadedPdf,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final loaded = snapshot.data;
        if (snapshot.hasError || loaded == null) {
          return _PdfLoadError(onRetry: () => setState(_startLoading));
        }
        return KeyedSubtree(
          key: ValueKey('pdf-document-${loaded.attachment.id}'),
          child:
              widget.pdfViewBuilder?.call(
                loaded.bytes,
                loaded.attachment.name,
              ) ??
              PdfViewer.data(loaded.bytes, sourceName: loaded.attachment.name),
        );
      },
    ),
  );
}

class _LoadedPdf {
  const _LoadedPdf({required this.attachment, required this.bytes});

  final NoteAttachment attachment;
  final Uint8List bytes;
}

class _PdfLoadError extends StatelessWidget {
  const _PdfLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.picture_as_pdf_outlined,
            color: Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'No pudimos abrir este PDF',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}
