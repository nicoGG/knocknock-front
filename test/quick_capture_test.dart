import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:share_handler/share_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/quick_capture_inbox.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/widgets/quick_capture_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('text and links retain their content', () {
    final text = quickCaptureDraft('Comprar pan\nIntegral y leche', 'Nico');
    expect(text.title, 'Comprar pan');
    expect(text.content, 'Integral y leche');
    final link = quickCaptureDraft(
      'https://www.example.com/articulo?q=1',
      'Nico',
    );
    expect(link.title, 'example.com');
    expect(link.content, 'https://www.example.com/articulo?q=1');
    final long = List.filled(130, '👨‍👩‍👧').join();
    expect(quickCaptureDraft(long, 'Nico').content, long);
  });

  test(
    'queued shares survive restart and only acknowledged item is removed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final inbox = QuickCaptureInbox();
      await Future.wait([inbox.enqueue('Primera'), inbox.enqueue('Segunda')]);
      await inbox.start(listenToPlatform: false);
      expect(inbox.pending.map((e) => e.text), ['Primera', 'Segunda']);
      final restored = QuickCaptureInbox();
      await restored.start(listenToPlatform: false);
      await restored.acknowledge(restored.pending.first.id);
      final reopened = QuickCaptureInbox();
      await reopened.start(listenToPlatform: false);
      expect(reopened.pending.single.text, 'Segunda');
      inbox.dispose();
      restored.dispose();
      reopened.dispose();
    },
  );

  test(
    'initial and live shares are persisted without a duplicate on launch',
    () async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final original = ShareHandlerPlatform.instance;
      final handler = _ShareReceiver();
      ShareHandlerPlatform.instance = handler;
      final inbox = QuickCaptureInbox();
      try {
        await inbox.start();
        handler.events.add(SharedMedia(content: 'Compartida al abrir'));
        handler.events.add(
          SharedMedia(content: 'Compartida con la app abierta'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(inbox.pending.map((e) => e.text), [
          'Compartida al abrir',
          'Compartida con la app abierta',
        ]);
        expect(handler.resets, 2);
      } finally {
        inbox.dispose();
        await handler.events.close();
        ShareHandlerPlatform.instance = original;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'failed save keeps text and allows retry; more options cancellation keeps sheet',
    (tester) async {
      var attempts = 0;
      NoteDraft? saved;
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showQuickCaptureSheet(
                  context: context,
                  lists: [
                    NoteList(
                      id: 'home',
                      name: 'Casa',
                      createdAt: now,
                      updatedAt: now,
                    ),
                  ],
                  selectedListId: 'home',
                  authorName: 'Nico',
                  initialText: 'Comprar pan',
                  onSave: (id, draft) async {
                    if (attempts++ == 0) throw Exception('sin conexión');
                    saved = draft;
                  },
                  onMoreOptions: (_, _) async => false,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('quick-capture-more-options')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-capture-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-capture-save')));
      await tester.pumpAndSettle();
      expect(find.text('Comprar pan'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-capture-save')));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Comprar pan');
      expect(find.byKey(const ValueKey('quick-capture-sheet')), findsNothing);
    },
  );
}

class _ShareReceiver extends ShareHandlerPlatform {
  final events = StreamController<SharedMedia>();
  int resets = 0;
  @override
  Stream<SharedMedia> get sharedMediaStream => events.stream;
  @override
  Future<SharedMedia?> getInitialSharedMedia() async =>
      SharedMedia(content: 'Compartida al abrir');
  @override
  Future<void> resetInitialSharedMedia() async {
    resets++;
  }
}
