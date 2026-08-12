import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_link.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

Future<NoteLinkMetadata> _metadata(String url) async => NoteLinkMetadata(
  url: url,
  siteName: 'NockNock',
  title: 'Ayuda de NockNock',
  description: 'Todo lo que necesitas para organizar tu nota.',
  imageUrl: null,
);

void main() {
  testWidgets('link editor stays compact above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const url =
        'https://www.cruzverde.cl/wegovy-05-mgdosis-solucion-inyectable-en-'
        'pluma-precargada/588008.html';
    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showNoteLinkDialog(
                  context,
                  initialLabel: url,
                  initialUrl: url,
                  canRemoveLink: true,
                ),
                child: const Text('Editar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('note-link-dialog'));
    final cancel = find.byKey(const ValueKey('cancel-note-link-button'));
    final save = find.byKey(const ValueKey('save-note-link-button'));
    final remove = find.byKey(const ValueKey('remove-note-link-button'));
    expect(tester.widget<AlertDialog>(dialog).scrollable, isTrue);
    final dialogSurface = find
        .descendant(of: dialog, matching: find.byType(Material))
        .first;
    expect(tester.getBottomLeft(dialogSurface).dy, lessThanOrEqualTo(514));
    expect(
      tester.getCenter(cancel).dy,
      closeTo(tester.getCenter(save).dy, 0.5),
    );
    expect(tester.getCenter(remove).dy, lessThan(tester.getCenter(save).dy));
    expect(tester.takeException(), isNull);
  });

  test('detects links in legacy plain text and keeps punctuation outside', () {
    final document = noteDocumentFromContent(
      plainText: 'Revisa https://nocknock.cl/notas.',
    );

    expect(document.toPlainText().trim(), 'Revisa https://nocknock.cl/notas.');
    expect(document.toDelta().toJson(), [
      {'insert': 'Revisa '},
      {
        'insert': 'https://nocknock.cl/notas',
        'attributes': {'link': 'https://nocknock.cl/notas'},
      },
      {'insert': '.\n'},
    ]);
  });

  test('detects www links inside an existing rich-text delta', () {
    final document = noteDocumentFromContent(
      plainText: 'Visita www.nocknock.cl',
      deltaJson: jsonEncode([
        {
          'insert': 'Visita www.nocknock.cl',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]),
    );

    expect(document.toDelta().toJson(), [
      {
        'insert': 'Visita ',
        'attributes': {'bold': true},
      },
      {
        'insert': 'www.nocknock.cl',
        'attributes': {'bold': true, 'link': 'https://www.nocknock.cl'},
      },
      {'insert': '\n'},
    ]);
  });

  testWidgets('creates a hyperlink for the selected note text', (tester) async {
    NoteRichContent? latestContent;
    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: NoteRichTextEditor(
            initialPlainText: 'Ver detalles',
            linkMetadataLoader: _metadata,
            onChanged: (content) => latestContent = content,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 12),
      ChangeSource.local,
    );
    await tester.pump();

    final linkButton = find.byKey(const ValueKey('note-hyperlink-button'));
    expect(linkButton, findsOneWidget);
    tester
        .widget<InkWell>(
          find.descendant(of: linkButton, matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pumpAndSettle();

    final linkFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    expect(linkFields, findsNWidgets(2));
    expect(
      tester.widget<TextFormField>(linkFields.first).controller?.text,
      'Ver detalles',
    );
    await tester.enterText(linkFields.last, 'nocknock.cl/ayuda');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-note-link-button')));
    await tester.pumpAndSettle();

    expect(latestContent?.plainText, 'Ver detalles');
    expect(
      latestContent?.deltaJson,
      contains('"link":"https://nocknock.cl/ayuda"'),
    );
  });

  testWidgets('renames an existing URL while keeping its destination', (
    tester,
  ) async {
    NoteRichContent? latestContent;
    const url = 'https://nocknock.cl/ayuda';
    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: NoteRichTextEditor(
            initialPlainText: url,
            linkMetadataLoader: _metadata,
            onChanged: (content) => latestContent = content,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: url.length),
      ChangeSource.local,
    );
    await tester.pump();

    final linkButton = find.byKey(const ValueKey('note-hyperlink-button'));
    tester
        .widget<InkWell>(
          find.descendant(of: linkButton, matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextFormField>(fields.first).controller?.text, url);
    expect(tester.widget<TextFormField>(fields.last).controller?.text, url);
    await tester.enterText(fields.first, 'Centro de ayuda');
    await tester.tap(find.byKey(const ValueKey('save-note-link-button')));
    await tester.pumpAndSettle();

    expect(latestContent?.plainText, 'Centro de ayuda');
    expect(latestContent?.deltaJson, contains('"link":"$url"'));
  });

  testWidgets('loads and persistently dismisses the page preview', (
    tester,
  ) async {
    NoteRichContent? latestContent;
    const url = 'https://nocknock.cl/ayuda';
    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: NoteRichTextEditor(
              initialPlainText: url,
              linkMetadataLoader: _metadata,
              onChanged: (content) => latestContent = content,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ayuda de NockNock'), findsOneWidget);
    expect(find.text('NockNock'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('dismiss-note-link-preview-$url')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('note-link-preview-$url')), findsNothing);
    expect(noteHiddenLinkPreviews(latestContent?.deltaJson), {url});
    expect(
      notePreviewLinkFromContent(
        plainText: latestContent!.plainText,
        deltaJson: latestContent!.deltaJson,
      ),
      isNull,
    );
  });

  testWidgets('opens a rendered hyperlink through the viewer callback', (
    tester,
  ) async {
    String? openedUrl;
    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: SizedBox(
            width: 240,
            child: NoteRichTextViewer(
              plainText: 'Abrir sitio',
              deltaJson: jsonEncode([
                {
                  'insert': 'Abrir sitio',
                  'attributes': {'link': 'https://nocknock.cl'},
                },
                {'insert': '\n'},
              ]),
              showLinkPreview: false,
              onLaunchUrl: (url) => openedUrl = url,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir sitio', findRichText: true));
    await tester.pump();

    expect(openedUrl, 'https://nocknock.cl');
  });

  testWidgets(
    'shows open and rename actions without tapping the parent editor',
    (tester) async {
      String? openedUrl;
      String? editedUrl;
      var parentTapped = false;
      const url = 'https://nocknock.cl';
      await tester.pumpWidget(
        _TestApp(
          child: Scaffold(
            body: Center(
              child: InkWell(
                onTap: () => parentTapped = true,
                child: SizedBox(
                  width: 240,
                  child: NoteRichTextViewer(
                    plainText: 'Abrir sitio',
                    deltaJson: jsonEncode([
                      {
                        'insert': 'Abrir sitio',
                        'attributes': {'link': url},
                      },
                      {'insert': '\n'},
                    ]),
                    showLinkPreview: false,
                    onLaunchUrl: (value) => openedUrl = value,
                    onEditLink: (value) => editedUrl = value,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir sitio', findRichText: true));
      await tester.pumpAndSettle();

      expect(parentTapped, isFalse);
      expect(
        find.byKey(const ValueKey('open-note-link-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('edit-note-link-action')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('open-note-link-action')));
      await tester.pumpAndSettle();
      expect(openedUrl, url);

      await tester.tap(find.text('Abrir sitio', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-note-link-action')));
      await tester.pumpAndSettle();
      expect(editedUrl, url);
      expect(parentTapped, isFalse);
    },
  );

  test('renames a link from a rendered-link action', () {
    const url = 'https://nocknock.cl';
    final content = NoteRichContent(
      plainText: 'Abrir sitio',
      deltaJson: jsonEncode([
        {
          'insert': 'Abrir sitio',
          'attributes': {'link': url},
        },
        {'insert': '\n'},
      ]),
    );
    final match = noteRichLinkMatchForUrl(
      plainText: content.plainText,
      deltaJson: content.deltaJson,
      url: url,
    );
    final updated = applyNoteRichLinkEdit(
      plainText: content.plainText,
      deltaJson: content.deltaJson,
      match: match!,
      result: const NoteLinkEditResult.link(
        NoteLinkValue(label: 'Sitio NockNock', url: url),
      ),
    );

    expect(updated.plainText, 'Sitio NockNock');
    expect(updated.deltaJson, contains('"link":"$url"'));
  });

  testWidgets('mosaic link text opens directly and preserves card gestures', (
    tester,
  ) async {
    String? openedUrl;
    var cardTapped = false;
    var cardLongPressed = false;
    const url = 'https://nocknock.cl';
    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: Center(
            child: InkWell(
              onTap: () => cardTapped = true,
              onLongPress: () => cardLongPressed = true,
              child: NoteLinkifiedText(
                plainText: url,
                style: const TextStyle(fontSize: 16),
                onOpenUrl: (value) => openedUrl = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(url));
    await tester.pump();
    expect(openedUrl, url);
    expect(cardTapped, isFalse);

    openedUrl = null;
    await tester.longPress(find.text(url));
    await tester.pump();
    expect(cardLongPressed, isTrue);
    expect(openedUrl, isNull);
  });

  testWidgets('mosaic links use compact text and characteristic blue', (
    tester,
  ) async {
    const url =
        'https://www.cruzverde.cl/wegovy-05-mgdosis-solucion-inyectable-en-'
        'pluma-precargada/588008.html';
    const content = 'Comprar tercera dosis Wegovy\n$url';
    await tester.pumpWidget(
      _TestApp(
        child: Center(
          child: SizedBox(
            width: 146,
            child: Builder(
              builder: (context) => NoteLinkifiedText(
                plainText: content,
                style: gridNoteDescriptionTextStyle(
                  context,
                  color: Colors.white,
                ),
                linkColor: gridNoteLinkColor(Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final linkified = tester.widget<NoteLinkifiedText>(
      find.byType(NoteLinkifiedText),
    );
    expect(linkified.style?.fontSize, 14);
    expect(linkified.style?.height, 1.35);

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(NoteLinkifiedText),
        matching: find.byType(Text),
      ),
    );
    final rootSpan = text.textSpan! as TextSpan;
    final linkSpan = rootSpan.children!.whereType<TextSpan>().firstWhere(
      (span) => span.recognizer != null,
    );
    expect(linkSpan.style?.color, noteMosaicLinkBlue);
    expect(linkSpan.style?.decoration, TextDecoration.underline);

    final element = tester.element(find.byType(NoteLinkifiedText));
    final painter = TextPainter(
      text: noteLinkifiedTextSpan(
        plainText: content,
        deltaJson: null,
        style: linkified.style,
        linkColor: linkified.linkColor,
      ),
      textDirection: Directionality.of(element),
      textScaler: MediaQuery.textScalerOf(element),
    )..layout(maxWidth: 146);
    expect(
      tester.getSize(find.byType(NoteLinkifiedText)).height,
      closeTo(painter.height, 0.01),
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      home: child,
    );
  }
}
