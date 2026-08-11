import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';

void main() {
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
    await tester.tap(find.widgetWithText(TextButton, 'Ok'));
    await tester.pumpAndSettle();

    expect(latestContent?.plainText, 'Ver detalles');
    expect(latestContent?.deltaJson, contains('"link":"nocknock.cl/ayuda"'));
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
