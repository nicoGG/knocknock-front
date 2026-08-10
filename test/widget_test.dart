import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<MethodCall> _captureSystemSoundCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemSound.play') calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opens an Android invitation app link on the board', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/invitations';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-list-button')), findsOneWidget);
  });

  testWidgets('collaborator avatars float softly with staggered movement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(withInvitedPeople: true),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final firstAvatar = find.byKey(
      const ValueKey('collaborator-avatar-float-0'),
    );
    final secondAvatar = find.byKey(
      const ValueKey('collaborator-avatar-float-1'),
    );
    expect(firstAvatar, findsOneWidget);
    expect(secondAvatar, findsOneWidget);

    final initialFirstOffset = tester
        .widget<Transform>(firstAvatar)
        .transform
        .getTranslation();
    final initialSecondOffset = tester
        .widget<Transform>(secondAvatar)
        .transform
        .getTranslation();

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 900));

    final movedFirstOffset = tester
        .widget<Transform>(firstAvatar)
        .transform
        .getTranslation();
    final movedSecondOffset = tester
        .widget<Transform>(secondAvatar)
        .transform
        .getTranslation();
    expect((movedFirstOffset.y - initialFirstOffset.y).abs(), greaterThan(0.1));
    expect(
      (movedSecondOffset.y - initialSecondOffset.y).abs(),
      greaterThan(0.1),
    );
    expect(movedFirstOffset.y, isNot(closeTo(movedSecondOffset.y, 0.1)));
  });

  testWidgets('collaborator avatars stay still with reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(withInvitedPeople: true),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final firstAvatar = find.byKey(
      const ValueKey('collaborator-avatar-float-0'),
    );
    final initialOffset = tester
        .widget<Transform>(firstAvatar)
        .transform
        .getTranslation();
    await tester.pump(const Duration(seconds: 5));
    final laterOffset = tester
        .widget<Transform>(firstAvatar)
        .transform
        .getTranslation();

    expect(initialOffset.x, 0);
    expect(initialOffset.y, 0);
    expect(laterOffset.x, 0);
    expect(laterOffset.y, 0);
  });

  testWidgets('shows the board and can open the note editor', (tester) async {
    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('NockNock'), findsNothing);
    expect(find.text('En vivo'), findsNothing);
    expect(
      find.byKey(const ValueKey('disconnected-status-indicator')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('connection-status-button')));
    await tester.pumpAndSettle();

    expect(find.text('Estado de NockNock'), findsOneWidget);
    final statusDialog = find.byKey(const ValueKey('connection-status-dialog'));
    expect(
      find.descendant(of: statusDialog, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    final glassSurface = tester.widget<Container>(
      find.byKey(const ValueKey('connection-status-glass-surface')),
    );
    expect((glassSurface.decoration! as BoxDecoration).gradient, isNotNull);
    expect(tester.getSize(statusDialog).width, greaterThan(500));
    expect(find.text('Backend'), findsOneWidget);
    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.text('Canal en tiempo real'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
    expect(find.text('Sincronización'), findsOneWidget);
    expect(find.text('Solo en este dispositivo'), findsOneWidget);
    expect(find.text('1 nota cargada'), findsOneWidget);
    expect(find.text('Cifrado de lista y notas'), findsOneWidget);
    expect(find.text('Disponible al iniciar sesión'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('close-connection-status-dialog')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-avatar-button')), findsOneWidget);
    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-grid')), findsOneWidget);
    expect(find.byType(LongPressDraggable<String>), findsOneWidget);

    final pinRect = tester.getRect(
      find.byKey(const ValueKey('pin-note-note-1')),
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('note-surface-note-1')),
    );
    expect(pinRect.center.dy, closeTo(cardRect.top, 0.5));
    expect(pinRect.bottom, greaterThan(cardRect.top));

    await tester.tap(find.byKey(const ValueKey('pin-note-note-1')));
    await tester.pumpAndSettle();
    expect(repository.lastChanges, containsPair('isPinned', true));
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    await tester.pumpAndSettle();

    expect(find.text('Nueva nota'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('note-title-field')), findsOneWidget);
  });

  testWidgets('long press previews a note in grid and list modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          withInvitedPeople: true,
          initialContent: 'Texto importante para mañana',
          initialContentDelta:
              '[{"insert":"Texto importante","attributes":{"bold":true}},{"insert":" para mañana\\n"}]',
        ),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('note-note-1')));
    await tester.pump();

    expect(find.byKey(const ValueKey('note-preview-dialog')), findsOneWidget);
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('note-preview-transparent-shell')),
          )
          .type,
      MaterialType.transparency,
    );
    expect(find.text('Vista previa'), findsNothing);
    expect(find.byIcon(Icons.visibility_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey('note-preview-scale-transition')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-preview-card')),
        matching: find.text('Comprar café'),
      ),
      findsOneWidget,
    );
    final previewCard = find.byKey(const ValueKey('note-preview-card'));
    final richContent = find.descendant(
      of: previewCard,
      matching: find.byKey(const ValueKey('preview-rich-content-note-1')),
    );
    expect(richContent, findsOneWidget);
    final richEditor = tester.widget<QuillEditor>(
      find.descendant(of: richContent, matching: find.byType(QuillEditor)),
    );
    expect(
      richEditor.controller.document.toDelta().toJson().first['attributes'],
      containsPair('bold', true),
    );
    final createdBy = find.descendant(
      of: previewCard,
      matching: find.byKey(const ValueKey('preview-created-by-note-1')),
    );
    final assignedTo = find.descendant(
      of: previewCard,
      matching: find.byKey(const ValueKey('preview-assigned-to-note-1')),
    );
    final authorAvatar = find.descendant(
      of: previewCard,
      matching: find.byKey(const ValueKey('author-avatar-note-1')),
    );
    final assigneeAvatar = find.descendant(
      of: previewCard,
      matching: find.byKey(const ValueKey('assignee-avatar-note-1')),
    );
    expect(createdBy, findsOneWidget);
    expect(assignedTo, findsOneWidget);
    expect(authorAvatar, findsOneWidget);
    expect(assigneeAvatar, findsOneWidget);
    expect(
      tester.getRect(createdBy).bottom,
      lessThan(tester.getRect(authorAvatar).top),
    );
    expect(
      tester.getRect(assignedTo).bottom,
      lessThan(tester.getRect(assigneeAvatar).top),
    );
    expect(
      find.byKey(const ValueKey('open-note-from-preview-button')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('close-note-preview-button')));
    await tester.pumpAndSettle();

    final dragGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('note-note-1'))),
    );
    await tester.pump(const Duration(milliseconds: 520));
    await dragGesture.moveBy(const Offset(0, 32));
    await tester.pump(const Duration(milliseconds: 100));
    await dragGesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-preview-dialog')), findsNothing);

    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-preview-dialog')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('open-note-from-preview-button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-detail-page')), findsOneWidget);
  });

  testWidgets('reacts without leaving the quick preview', (tester) async {
    final repository = _FakeNotesRepository(withInvitedPeople: true);
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'owner-1',
            displayName: 'Nico',
            email: 'nico@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('note-preview-dialog'));
    expect(preview, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: preview,
        matching: find.byKey(const ValueKey('add-note-reaction-button')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reaction-option-🎉')));
    await tester.pumpAndSettle();

    final reactionChip = find.descendant(
      of: preview,
      matching: find.byKey(const ValueKey('note-reaction-note-1-🎉')),
    );
    expect(reactionChip, findsOneWidget);
    expect(repository._note.reactions.single.userUids, ['owner-1']);
    expect(find.byKey(const ValueKey('note-detail-page')), findsNothing);

    await tester.longPress(reactionChip);
    await tester.pumpAndSettle();
    expect(find.text('🎉  Tú'), findsOneWidget);
    expect(repository._note.reactions.single.userUids, ['owner-1']);
  });

  testWidgets('aligns floating reactions with the pin', (tester) async {
    final repository = _FakeNotesRepository(
      reactions: const [
        NoteReaction(emoji: '❤️', userUids: ['owner-1']),
        NoteReaction(emoji: '😮', userUids: ['person-ana']),
        NoteReaction(emoji: '👍', userUids: ['person-luis']),
      ],
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final reactionsRect = tester.getRect(
      find.byKey(const ValueKey('note-reactions-summary-note-1')),
    );
    final pinRect = tester.getRect(
      find.byKey(const ValueKey('pin-note-note-1')),
    );

    expect(pinRect.center.dy, closeTo(reactionsRect.center.dy, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plays board action sounds and distinguishes a long press', (
    tester,
  ) async {
    final systemSoundCalls = _captureSystemSoundCalls(tester);
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pin-note-note-1')));
    await tester.pump();
    expect(systemSoundCalls, hasLength(1));
    expect(
      systemSoundCalls.single,
      isMethodCall('SystemSound.play', arguments: 'SystemSoundType.click'),
    );
    await tester.pumpAndSettle();

    systemSoundCalls.clear();
    await tester.tap(find.byKey(const ValueKey('list-options-button')));
    await tester.pump();
    expect(systemSoundCalls, hasLength(1));
    Navigator.of(tester.element(find.text('Cambiar fondo'))).pop();
    await tester.pumpAndSettle();

    systemSoundCalls.clear();
    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pump();
    expect(systemSoundCalls, hasLength(1));
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byKey(const ValueKey('note-detail-page'))),
    ).pop();
    await tester.pumpAndSettle();

    systemSoundCalls.clear();
    await tester.longPress(find.byKey(const ValueKey('note-note-1')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(systemSoundCalls, hasLength(2));
    expect(
      systemSoundCalls,
      everyElement(
        isMethodCall('SystemSound.play', arguments: 'SystemSoundType.click'),
      ),
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('note-preview-dialog'))),
    ).pop();
    await tester.pumpAndSettle();

    systemSoundCalls.clear();
    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    await tester.pump();
    expect(systemSoundCalls, hasLength(1));
  });

  testWidgets(
    'quick edits title, content and reordered subtasks inside the preview',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const checklist = [
        NoteChecklistItem(id: 'quick-task-1', text: 'Primera subtarea'),
        NoteChecklistItem(id: 'quick-task-2', text: 'Segunda subtarea'),
      ];
      final repository = _FakeNotesRepository(checklist: checklist);
      await tester.pumpWidget(
        NockNockApp(
          repository: repository,
          authRepository: _FakeAuthRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const ValueKey('note-note-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-edit-note-button')));
      await tester.pumpAndSettle();

      expect(find.text('Edición rápida'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-note-editor')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick-edit-title-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('quick-edit-content-editor')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick-edit-title-field')),
        'comprar café y té',
      );
      final contentEditor = tester.widget<QuillEditor>(
        find.byKey(const ValueKey('quick-edit-content-editor')),
      );
      final replaceLength = contentEditor.controller.document.length - 1;
      const updatedContent = 'Contenido actualizado desde la vista rápida';
      contentEditor.controller.replaceText(
        0,
        replaceLength,
        updatedContent,
        const TextSelection.collapsed(offset: updatedContent.length),
      );
      await tester.pump();

      final checklistEditor = find.byKey(
        const ValueKey('quick-edit-checklist-editor'),
      );
      final addItem = find.descendant(
        of: checklistEditor,
        matching: find.byKey(const ValueKey('add-checklist-item')),
      );
      await tester.ensureVisible(addItem);
      await tester.tap(addItem);
      await tester.pump();

      final checklistFields = find.descendant(
        of: checklistEditor,
        matching: find.byType(TextFormField),
      );
      expect(checklistFields, findsNWidgets(3));
      await tester.enterText(checklistFields.last, 'Tercera subtarea');
      await tester.pump();

      final reorderable = tester.widget<ReorderableListView>(
        find.descendant(
          of: checklistEditor,
          matching: find.byType(ReorderableListView),
        ),
      );
      reorderable.onReorderItem!(0, 2);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save-quick-edit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick-note-editor')), findsNothing);
      expect(find.byKey(const ValueKey('note-preview-dialog')), findsOneWidget);
      expect(
        repository.lastChanges,
        containsPair('title', 'Comprar café y té'),
      );
      expect(repository.lastChanges, containsPair('content', updatedContent));
      final savedChecklist =
          repository.lastChanges!['checklist'] as List<dynamic>;
      expect(savedChecklist.map((item) => (item as Map)['text']), [
        'Segunda subtarea',
        'Tercera subtarea',
        'Primera subtarea',
      ]);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('note-preview-card')),
          matching: find.text('Comprar café y té'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changes a list background and blur from the board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Mis notas')).dy, lessThan(100));

    final listOptionsButton = find.byKey(const ValueKey('list-options-button'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: listOptionsButton),
      findsNothing,
    );
    expect(find.textContaining('Tiempo real'), findsNothing);
    final noteCountLabel = find.text('1 nota');
    final listOptionsButtonRect = tester.getRect(listOptionsButton);
    final noteCountLabelRect = tester.getRect(noteCountLabel);
    final verticalCenterDelta =
        listOptionsButtonRect.center.dy - noteCountLabelRect.center.dy;
    expect(
      verticalCenterDelta.abs(),
      lessThan(1),
      reason:
          'button=$listOptionsButtonRect, label=$noteCountLabelRect, delta=$verticalCenterDelta',
    );
    expect(listOptionsButtonRect.right, greaterThan(398));

    await tester.tap(listOptionsButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('customize-background-menu-item')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fondo de esta lista'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-live-preview')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('background-preset-lagoon')));
    final blurSlider = find.byKey(const ValueKey('background-blur-slider'));
    await tester.ensureVisible(blurSlider);
    await tester.pumpAndSettle();
    await tester.drag(blurSlider, const Offset(110, 0));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-background-button')));
    await tester.pumpAndSettle();

    expect(
      repository.lastAppearance?.backgroundPreset,
      ListBackgroundPreset.lagoon,
    );
    expect(repository.lastAppearance!.backgroundBlur, greaterThan(0));
    expect(
      find.byKey(const ValueKey('preset-background-lagoon')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('board-background-blur')), findsOneWidget);
  });

  testWidgets('custom backgrounds fill the complete available canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const onePixelPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
        'A8AAQUBAScY42YAAAAASUVORK5CYII=';
    await tester.pumpWidget(
      const MaterialApp(
        home: ListBoardBackground(
          appearance: ListAppearance(
            backgroundPreset: ListBackgroundPreset.custom,
            customBackgroundImage: onePixelPng,
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('custom-board-background'))),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
  });

  testWidgets('capitalizes the title and detail initial letters', (
    tester,
  ) async {
    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-author-field')), findsOneWidget);
    final titleField = find.byKey(const ValueKey('note-title-field'));
    final contentField = find.byKey(const ValueKey('note-content-editor'));
    expect(find.byTooltip('Título grande'), findsOneWidget);
    expect(find.byTooltip('Título mediano'), findsOneWidget);
    expect(find.byTooltip('Texto normal'), findsOneWidget);
    expect(find.byTooltip('Negrita'), findsOneWidget);
    expect(find.byTooltip('Cursiva'), findsOneWidget);
    expect(find.byTooltip('Subrayado'), findsOneWidget);
    expect(find.byTooltip('Tachado'), findsOneWidget);
    await tester.enterText(titleField, 'comprar leche');
    final richEditor = tester.widget<QuillEditor>(contentField);
    richEditor.controller.replaceText(
      0,
      0,
      'llevar dos cajas',
      const TextSelection.collapsed(offset: 16),
    );
    await tester.pump();

    expect(
      richEditor.controller.document.toPlainText().trim(),
      'Llevar dos cajas',
    );

    await tester.ensureVisible(find.byTooltip('Negrita'));
    await tester.tap(find.byTooltip('Negrita'));
    await tester.pump();
    await tester.tap(find.byTooltip('Título grande'));
    await tester.pump();

    final styledDelta = richEditor.controller.document.toDelta().toJson();
    expect(styledDelta.first['attributes'], containsPair('bold', true));
    expect(styledDelta.last['attributes'], containsPair('header', 1));

    expect(find.text('Comprar leche'), findsOneWidget);
    final saveButton = find.byKey(const ValueKey('save-note-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(repository.createdDraft?.title, 'Comprar leche');
    expect(repository.createdDraft?.content, 'Llevar dos cajas');
    expect(repository.createdDraft?.contentDelta, contains('"bold":true'));
    expect(repository.createdDraft?.contentDelta, contains('"header":1'));
  });

  testWidgets(
    'new note editor is glass and uses the signed-in author automatically',
    (tester) async {
      const user = AppUser(
        id: 'google-user',
        displayName: 'Nico Galdames',
        email: 'nico@example.com',
      );
      final repository = _FakeNotesRepository();
      await tester.pumpWidget(
        NockNockApp(
          repository: repository,
          authRepository: _FakeAuthRepository(user: user),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('new-note-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('note-editor-glass-blur')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('note-editor-glass-surface')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('note-author-field')), findsNothing);
      expect(find.text('Tu nombre'), findsNothing);

      final reminder = find.byKey(const ValueKey('note-reminder-button'));
      await tester.ensureVisible(reminder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-reminder-glass-surface')),
        findsOneWidget,
      );
      final sheetWidth = tester
          .getSize(find.byKey(const ValueKey('note-editor-glass-surface')))
          .width;
      expect(tester.getSize(reminder).width, closeTo(sheetWidth - 48, 0.1));

      final beforePreset = DateTime.now();
      await tester.tap(reminder);
      await tester.pumpAndSettle();
      expect(find.text('Dentro de 1 día'), findsOneWidget);
      expect(find.text('Dentro de 1 semana'), findsOneWidget);
      expect(find.text('Dentro de 1 mes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-preset-day')));
      await tester.pumpAndSettle();
      final afterPreset = DateTime.now();

      final titleField = find.byKey(const ValueKey('note-title-field'));
      await tester.ensureVisible(titleField);
      await tester.enterText(titleField, 'nota con autor');
      final saveButton = find.byKey(const ValueKey('save-note-button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repository.createdDraft?.authorName, 'Nico Galdames');
      final createdReminder = repository.createdDraft!.reminderAt!;
      final earliestReminder = DateTime(
        beforePreset.year,
        beforePreset.month,
        beforePreset.day,
        beforePreset.hour,
        beforePreset.minute,
      ).add(const Duration(days: 1));
      final latestReminder = DateTime(
        afterPreset.year,
        afterPreset.month,
        afterPreset.day,
        afterPreset.hour,
        afterPreset.minute,
      ).add(const Duration(days: 1));
      expect(createdReminder.isBefore(earliestReminder), isFalse);
      expect(createdReminder.isAfter(latestReminder), isFalse);
    },
  );

  testWidgets('keeps focus in the detail while typing', (tester) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    await tester.pumpAndSettle();

    final editorFinder = find.byKey(const ValueKey('note-content-editor'));
    final initialEditor = tester.widget<QuillEditor>(editorFinder);
    initialEditor.focusNode.requestFocus();
    await tester.pump();
    initialEditor.controller.replaceText(
      0,
      0,
      'Es',
      const TextSelection.collapsed(offset: 2),
    );
    await tester.pump();

    final rebuiltEditor = tester.widget<QuillEditor>(editorFinder);
    expect(rebuiltEditor.focusNode, same(initialEditor.focusNode));
    expect(rebuiltEditor.focusNode.hasFocus, isTrue);
  });

  testWidgets('creates categorized notes with nested checklist items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-note-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'plan semanal',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final workCategory = find.byKey(const ValueKey('note-category-work'));
    await tester.ensureVisible(workCategory);
    await tester.tap(workCategory);
    await tester.pump();

    final addItem = find.byKey(const ValueKey('add-checklist-item'));
    await tester.ensureVisible(addItem);
    await tester.tap(addItem);
    await tester.pump();
    await tester.ensureVisible(addItem);
    await tester.tap(addItem);
    await tester.pump();

    final checklistEditor = find.byKey(const ValueKey('checklist-editor'));
    final fields = find.descendant(
      of: checklistEditor,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'preparar pauta');
    await tester.enterText(fields.at(1), 'confirmar asistentes');

    final menus = find.descendant(
      of: checklistEditor,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menus.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convertir en subtarea'));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('save-note-button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.createdDraft?.category, NoteCategory.work);
    expect(repository.createdDraft?.checklist.map((item) => item.text), [
      'Preparar pauta',
      'Confirmar asistentes',
    ]);
    expect(repository.createdDraft?.checklist.last.indent, 1);
  });

  testWidgets('unfocuses a checklist field before reordering it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-note-fab')));
    await tester.pumpAndSettle();

    final addItem = find.byKey(const ValueKey('add-checklist-item'));
    await tester.ensureVisible(addItem);
    await tester.tap(addItem);
    await tester.pump();

    final field = find
        .descendant(
          of: find.byKey(const ValueKey('checklist-editor')),
          matching: find.byType(TextFormField),
        )
        .first;
    await tester.tap(field);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    final focusedField = FocusManager.instance.primaryFocus!;

    final dragHandle = find.descendant(
      of: find.byKey(const ValueKey('checklist-editor')),
      matching: find.byIcon(Icons.drag_indicator_rounded),
    );
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await gesture.moveBy(const Offset(0, 48));
    await tester.pump();

    expect(focusedField.hasFocus, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds consecutive checklist items by pressing enter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-note-fab')));
    await tester.pumpAndSettle();
    final addItem = find.byKey(const ValueKey('add-checklist-item'));
    await tester.ensureVisible(addItem);
    await tester.tap(addItem);
    await tester.pump();

    var fields = find.descendant(
      of: find.byKey(const ValueKey('checklist-editor')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.first, 'Primera subtarea');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    fields = find.descendant(
      of: find.byKey(const ValueKey('checklist-editor')),
      matching: find.byType(TextFormField),
    );
    expect(fields, findsNWidgets(2));
    final lastEditable = tester.widget<EditableText>(
      find.descendant(of: fields.last, matching: find.byType(EditableText)),
    );
    expect(lastEditable.focusNode.hasFocus, isTrue);
  });

  testWidgets('shows category artwork and persists checklist interactions', (
    tester,
  ) async {
    const checklist = [
      NoteChecklistItem(id: 'task-1', text: 'Pasaporte'),
      NoteChecklistItem(id: 'task-2', text: 'Reservas', indent: 1),
      NoteChecklistItem(id: 'task-3', text: 'Maleta'),
    ];
    final repository = _FakeNotesRepository(
      category: NoteCategory.travel,
      checklist: checklist,
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Viajes'), findsOneWidget);
    expect(find.text('Pasaporte'), findsOneWidget);
    final card = find.byKey(const ValueKey('note-note-1'));
    final ink = tester.widget<Ink>(
      find.descendant(of: card, matching: find.byType(Ink)).first,
    );
    final decoration = ink.decoration! as BoxDecoration;
    final image = decoration.image!.image as AssetImage;
    expect(image.assetName, 'assets/note_backgrounds/travel.jpg');

    await tester.tap(find.byKey(const ValueKey('preview-check-task-1')));
    await tester.pumpAndSettle();
    final savedChecklist =
        repository.lastChanges?['checklist'] as List<dynamic>;
    expect(savedChecklist.first['isCompleted'], isTrue);

    await tester.tapAt(tester.getTopLeft(card) + const Offset(40, 40));
    await tester.pumpAndSettle();
    final taskContainer = find.byKey(const ValueKey('note-task-container'));
    final checklistDetail = find.byKey(const ValueKey('note-checklist-detail'));
    expect(
      find.descendant(of: taskContainer, matching: checklistDetail),
      findsOneWidget,
    );
    final taskBackground = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('note-task-background')),
    );
    expect(
      (taskBackground.decoration as BoxDecoration).color,
      NoteCategoryStyle.baseColor(NoteCategory.travel),
    );
    expect(tester.widget<Material>(checklistDetail).color, Colors.transparent);
    expect(
      tester.widget<Text>(find.text('Subtareas')).style?.color,
      NoteCategoryStyle.foregroundColor(NoteCategory.travel),
    );
    expect(
      find.descendant(of: checklistDetail, matching: find.text('Agregar')),
      findsNothing,
    );
    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderable.onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    final reordered = repository.lastChanges?['checklist'] as List<dynamic>;
    expect(reordered.map((item) => item['id']), ['task-2', 'task-3', 'task-1']);
    expect(reordered.first['indent'], 0);

    final deleteTask = find.byKey(
      const ValueKey('delete-detail-checklist-item-task-1'),
    );
    expect(deleteTask, findsOneWidget);
    await tester.tap(deleteTask);
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar subtarea?'), findsOneWidget);
    expect(
      find.text('Se eliminará “Pasaporte”. Esta acción no se puede deshacer.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('cancel-delete-detail-checklist-item')),
    );
    await tester.pumpAndSettle();
    expect(deleteTask, findsOneWidget);

    await tester.tap(deleteTask);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-detail-checklist-item')),
    );
    await tester.pumpAndSettle();
    expect(deleteTask, findsNothing);
    final checklistAfterDelete =
        repository.lastChanges?['checklist'] as List<dynamic>;
    expect(checklistAfterDelete.map((item) => item['id']), [
      'task-2',
      'task-3',
    ]);

    final directAdd = find.byKey(const ValueKey('detail-new-checklist-item'));
    final directAddDecoration = tester.widget<TextField>(directAdd).decoration!;
    expect(directAddDecoration.filled, isTrue);
    expect(
      (directAddDecoration.border! as OutlineInputBorder)
          .borderRadius
          .topLeft
          .x,
      18,
    );
    final cancelDirectAdd = find.byKey(
      const ValueKey('cancel-detail-new-checklist-item'),
    );
    final confirmDirectAdd = find.byKey(
      const ValueKey('confirm-detail-new-checklist-item'),
    );
    expect(cancelDirectAdd, findsOneWidget);
    expect(confirmDirectAdd, findsOneWidget);
    expect(tester.widget<IconButton>(confirmDirectAdd).onPressed, isNull);
    final directAddRect = tester.getRect(directAdd);
    expect(
      tester.getCenter(cancelDirectAdd).dx,
      lessThan(tester.getCenter(confirmDirectAdd).dx),
    );
    expect(
      tester.getRect(confirmDirectAdd).right,
      lessThanOrEqualTo(directAddRect.right),
    );

    await tester.enterText(directAdd, 'Descartar subtarea');
    await tester.pump();
    expect(tester.widget<IconButton>(confirmDirectAdd).onPressed, isNotNull);
    await tester.tap(cancelDirectAdd);
    await tester.pump();
    expect(tester.widget<TextField>(directAdd).controller?.text, isEmpty);
    expect(tester.widget<TextField>(directAdd).focusNode?.hasFocus, isFalse);

    await tester.enterText(directAdd, 'comprar adaptador');
    await tester.pump();
    await tester.tap(confirmDirectAdd);
    await tester.pumpAndSettle();

    final checklistAfterAdd =
        repository.lastChanges?['checklist'] as List<dynamic>;
    expect(checklistAfterAdd.last['text'], 'Comprar adaptador');
    expect(find.text('Comprar adaptador'), findsOneWidget);
    expect(tester.widget<TextField>(directAdd).focusNode?.hasFocus, isTrue);

    final dragProxy = reorderable.proxyDecorator!(
      const SizedBox(width: 260, height: 64),
      0,
      const AlwaysStoppedAnimation<double>(1),
    );
    await tester.pumpWidget(MaterialApp(home: Center(child: dragProxy)));

    expect(
      find.byKey(const ValueKey('detail-checklist-drag-proxy')),
      findsOneWidget,
    );
    final proxySurface = tester.widget<Material>(
      find.byKey(const ValueKey('checklist-drag-proxy-surface')),
    );
    expect(proxySurface.borderRadius, BorderRadius.circular(18));
    expect(proxySurface.elevation, 12);
    expect(proxySurface.color, isNot(Colors.black));
  });

  testWidgets('opens a useful note detail before editing', (tester) async {
    const authorPhotoUrl = 'https://example.com/nico-profile.jpg';
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          withInvitedPeople: true,
          initialAssigneeUid: 'owner-1',
        ),
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'owner-1',
            displayName: 'Nico',
            email: 'nico@example.com',
            photoUrl: authorPhotoUrl,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-detail-page')), findsOneWidget);
    final closeButton = find.byKey(const ValueKey('detail-close-button'));
    expect(closeButton, findsOneWidget);
    expect(
      find.descendant(
        of: closeButton,
        matching: find.byIcon(Icons.close_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    final taskContainer = find.byKey(const ValueKey('note-task-container'));
    final contentRow = find.byKey(const ValueKey('detail-content-row'));
    expect(
      find.descendant(of: taskContainer, matching: contentRow),
      findsOneWidget,
    );
    final contentViewer = tester.widget<NoteRichTextViewer>(
      find.byType(NoteRichTextViewer),
    );
    expect(contentViewer.plainText, 'Para la reunión de mañana');
    expect(contentViewer.foregroundColor, isNotNull);
    expect(find.text('Descripción'), findsNothing);
    final subtasksText = find.text('Subtareas');
    final subtasksStyle = tester.widget<Text>(subtasksText).style!;
    final detailTheme = Theme.of(tester.element(subtasksText));
    expect(
      subtasksStyle.fontSize,
      lessThan(detailTheme.textTheme.titleMedium!.fontSize!),
    );
    expect(find.text('Agregar recordatorio'), findsOneWidget);
    expect(find.text('Creada por'), findsOneWidget);
    expect(find.text('Nico'), findsNWidgets(2));
    expect(
      tester.getTopLeft(contentRow).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('note-detail-header'))).dy,
      ),
    );
    expect(
      tester.getBottomLeft(contentRow).dy,
      lessThan(tester.getTopLeft(find.text('Subtareas')).dy),
    );
    expect(
      find.text('Creada el 1 de enero de 2026 a las 00:00'),
      findsOneWidget,
    );
    expect(
      find.text('Actualizada el 1 de enero de 2026 a las 00:00'),
      findsOneWidget,
    );
    final assigneeAvatar = tester.widget<CircleAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('detail-assignee-avatar')),
        matching: find.byType(CircleAvatar),
      ),
    );
    expect(assigneeAvatar.foregroundImage, isA<NetworkImage>());
    expect(
      (assigneeAvatar.foregroundImage! as NetworkImage).url,
      authorPhotoUrl,
    );
    final authorAvatar = tester.widget<CircleAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('detail-author-avatar')),
        matching: find.byType(CircleAvatar),
      ),
    );
    expect(authorAvatar.foregroundImage, isA<NetworkImage>());
    expect((authorAvatar.foregroundImage! as NetworkImage).url, authorPhotoUrl);
    expect(find.byKey(const ValueKey('detail-delete-button')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('detail-edit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Editar nota'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-title-field')), findsOneWidget);
  });

  testWidgets('adds, summarizes, and removes an emoji reaction', (
    tester,
  ) async {
    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'owner-1',
            displayName: 'Nico',
            email: 'nico@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();
    final reactionsBar = find.byKey(const ValueKey('note-reactions-bar'));
    expect(reactionsBar, findsOneWidget);
    expect(tester.widget(reactionsBar), isA<Wrap>());
    expect(
      find.descendant(of: reactionsBar, matching: find.text('Reacciones')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('add-note-reaction-button')));
    await tester.pumpAndSettle();
    expect(find.text('Reaccionar a la nota'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reaction-option-🎉')));
    await tester.pumpAndSettle();

    final reactionChip = find.byKey(const ValueKey('note-reaction-note-1-🎉'));
    expect(reactionChip, findsOneWidget);
    expect(repository._note.reactions.single.emoji, '🎉');
    expect(repository._note.reactions.single.userUids, ['owner-1']);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('note-reactions-summary-note-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();
    await tester.tap(reactionChip);
    await tester.pumpAndSettle();
    expect(repository._note.reactions, isEmpty);
    expect(reactionChip, findsNothing);
  });

  testWidgets('shows who reacted after a subtle long press', (tester) async {
    final repository = _FakeNotesRepository(
      withInvitedPeople: true,
      reactions: const [
        NoteReaction(emoji: '🎉', userUids: ['owner-1', 'person-ana']),
      ],
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'owner-1',
            displayName: 'Nico',
            email: 'nico@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();
    final reactionChip = find.byKey(const ValueKey('note-reaction-note-1-🎉'));

    await tester.longPress(reactionChip);
    await tester.pumpAndSettle();

    expect(find.text('🎉  Tú y Ana Torres'), findsOneWidget);
    expect(repository._note.reactions.single.userUids, [
      'owner-1',
      'person-ana',
    ]);
  });

  testWidgets('edits the title directly in the note header card', (
    tester,
  ) async {
    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('note-detail-header'));
    await tester.tapAt(
      tester.getRect(header).centerRight - const Offset(70, 0),
    );
    await tester.pump();

    final titleField = find.byKey(const ValueKey('detail-title-field'));
    expect(titleField, findsOneWidget);
    expect(tester.widget<TextField>(titleField).maxLines, isNull);
    final cancelTitle = find.byKey(
      const ValueKey('cancel-detail-title-button'),
    );
    final saveTitle = find.byKey(const ValueKey('save-detail-title-button'));
    final titleFieldRect = tester.getRect(titleField);
    expect(
      tester.getRect(cancelTitle).top,
      greaterThanOrEqualTo(titleFieldRect.bottom),
    );
    expect(
      tester.getRect(saveTitle).top,
      greaterThanOrEqualTo(titleFieldRect.bottom),
    );
    expect(tester.getRect(saveTitle).right, closeTo(titleFieldRect.right, 1));
    await tester.enterText(titleField, 'Comprar té');
    await tester.tap(saveTitle);
    await tester.pumpAndSettle();

    expect(repository.lastChanges, containsPair('title', 'Comprar té'));
    expect(find.text('Comprar té'), findsOneWidget);
    expect(titleField, findsNothing);
  });

  testWidgets('expands and collapses the note editor inline on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();

    final contentRow = find.byKey(const ValueKey('detail-content-row'));
    await tester.tapAt(tester.getTopLeft(contentRow) + const Offset(24, 28));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('detail-content-editor')), findsOneWidget);
    expect(find.text('H1'), findsOneWidget);
    expect(find.text('H2'), findsOneWidget);
    expect(find.byIcon(Icons.format_italic_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('collapse-detail-content-button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-content-editor')), findsNothing);
  });

  testWidgets('edits content, color, and reminder from the note detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeNotesRepository(
      initialReminderAt: DateTime.now().add(const Duration(days: 1)),
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();

    final contentRow = find.byKey(const ValueKey('detail-content-row'));
    await tester.tapAt(tester.getTopLeft(contentRow) + const Offset(24, 28));
    await tester.pumpAndSettle();
    final contentEditor = tester.widget<QuillEditor>(
      find.byKey(const ValueKey('detail-content-editor')),
    );
    contentEditor.controller.replaceText(
      0,
      contentEditor.controller.document.length - 1,
      'texto actualizado',
      const TextSelection.collapsed(offset: 17),
    );
    contentEditor.controller.formatText(0, 5, Attribute.italic);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-detail-content-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NoteRichTextViewer>(find.byType(NoteRichTextViewer))
          .plainText,
      'Texto actualizado',
    );
    expect(repository.lastChanges?['content'], 'Texto actualizado');
    expect(repository.lastChanges?['contentDelta'], contains('"italic":true'));

    final colorRow = find.byKey(const ValueKey('detail-color-row'));
    await tester.ensureVisible(colorRow);
    await tester.pumpAndSettle();
    await tester.tap(colorRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-color-blue')));
    await tester.pumpAndSettle();
    expect(find.text('Azul'), findsOneWidget);
    expect(repository.lastChanges?['color'], 'blue');

    final categoryRow = find.byKey(const ValueKey('detail-category-row'));
    await tester.ensureVisible(categoryRow);
    await tester.pumpAndSettle();
    await tester.tap(categoryRow);
    await tester.pumpAndSettle();
    expect(find.text('Cambiar categoría'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-category-work')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('detail-category-row')),
        matching: find.text('Trabajo'),
      ),
      findsOneWidget,
    );
    expect(repository.lastChanges?['category'], 'work');
    expect(find.byKey(const ValueKey('detail-color-row')), findsNothing);

    final reminderRow = find.byKey(const ValueKey('detail-reminder-row'));
    await tester.ensureVisible(reminderRow);
    await tester.pumpAndSettle();
    await tester.tap(reminderRow);
    await tester.pumpAndSettle();
    expect(find.text('Dentro de 1 día'), findsOneWidget);
    expect(find.text('Dentro de 1 semana'), findsOneWidget);
    expect(find.text('Dentro de 1 mes'), findsOneWidget);
    final beforePreset = DateTime.now();
    await tester.tap(find.byKey(const ValueKey('reminder-preset-week')));
    await tester.pumpAndSettle();
    final afterPreset = DateTime.now();
    final savedPreset = DateTime.parse(
      repository.lastChanges!['reminderAt'] as String,
    );
    final earliestReminder = DateTime(
      beforePreset.year,
      beforePreset.month,
      beforePreset.day,
      beforePreset.hour,
      beforePreset.minute,
    ).add(const Duration(days: 7));
    final latestReminder = DateTime(
      afterPreset.year,
      afterPreset.month,
      afterPreset.day,
      afterPreset.hour,
      afterPreset.minute,
    ).add(const Duration(days: 7));
    expect(savedPreset.isBefore(earliestReminder), isFalse);
    expect(savedPreset.isAfter(latestReminder), isFalse);

    await tester.tap(find.byKey(const ValueKey('detail-reminder-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-custom-date')));
    await tester.pumpAndSettle();
    final datePicker = find.byType(DatePickerDialog);
    expect(datePicker, findsOneWidget);
    await tester.tap(
      find.descendant(of: datePicker, matching: find.byType(TextButton)).last,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(TimePickerDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('remove-detail-reminder-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Agregar recordatorio'), findsOneWidget);
    expect(repository.lastChanges, containsPair('reminderAt', null));
  });

  testWidgets('does not repeat list collaborators in note detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(withInvitedPeople: true),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();

    expect(find.text('Persona invitada'), findsNothing);
    expect(find.text('Ana Torres\nana@example.com'), findsNothing);
    expect(find.text('Invitación pendiente'), findsNothing);
    expect(find.text('pedro@example.com'), findsNothing);
  });

  testWidgets('assigns a task and shows only its responsible person', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const authorPhotoUrl = 'https://example.com/nico-profile.jpg';
    const photoUrl = 'https://example.com/ana-profile.jpg';
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          withInvitedPeople: true,
          collaboratorPhotoUrl: photoUrl,
        ),
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'owner-1',
            displayName: 'Nico',
            email: 'nico@example.com',
            photoUrl: authorPhotoUrl,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('assignee-note-1')), findsOneWidget);
    expect(find.byTooltip('Responsable: Ana Torres'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const ValueKey('assignee-avatar-note-1')),
    );
    expect(avatar.foregroundImage, isA<NetworkImage>());
    expect((avatar.foregroundImage! as NetworkImage).url, photoUrl);
    expect(find.byTooltip(RegExp('invitación pendiente')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a responsible person when creating a task', (
    tester,
  ) async {
    const photoUrl = 'https://example.com/ana-profile.jpg';
    final repository = _FakeNotesRepository(
      withInvitedPeople: true,
      collaboratorPhotoUrl: photoUrl,
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Comprar entradas',
    );
    final assigneeField = find.byKey(const ValueKey('note-assignee-field'));
    await tester.ensureVisible(assigneeField);
    await tester.tap(assigneeField);
    await tester.pumpAndSettle();
    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const ValueKey('assignee-option-avatar-person-ana')),
    );
    expect(avatar.foregroundImage, isA<NetworkImage>());
    expect((avatar.foregroundImage! as NetworkImage).url, photoUrl);
    await tester.tap(find.text('Ana Torres').last);
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('save-note-button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.createdDraft?.assigneeUid, 'person-ana');
  });

  testWidgets('changes the responsible person directly from note detail', (
    tester,
  ) async {
    final repository = _FakeNotesRepository(withInvitedPeople: true);
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-note-1')));
    await tester.pumpAndSettle();
    final assigneeRow = find.byKey(const ValueKey('detail-assignee-row'));
    await tester.ensureVisible(assigneeRow);
    await tester.pumpAndSettle();
    await tester.tap(assigneeRow);
    await tester.pumpAndSettle();

    expect(find.text('Asignar responsable'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assignee-option-person-ana')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('assignee-option-unassigned')));
    await tester.pumpAndSettle();

    expect(repository.lastChanges, containsPair('assigneeUid', null));
    expect(find.text('Sin responsable'), findsOneWidget);

    await tester.ensureVisible(assigneeRow);
    await tester.pumpAndSettle();
    await tester.tap(assigneeRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assignee-option-person-ana')));
    await tester.pumpAndSettle();

    expect(repository.lastChanges, containsPair('assigneeUid', 'person-ana'));
    expect(find.text('Ana Torres'), findsOneWidget);
  });

  testWidgets('note detail fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    final noteCard = find.byKey(const ValueKey('note-note-1'));
    await tester.ensureVisible(noteCard);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(noteCard) + const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-detail-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-detail-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-delete-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category picker scrolls on a short screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final noteCard = find.byKey(const ValueKey('note-note-1'));
    await tester.ensureVisible(noteCard);
    await tester.tapAt(tester.getTopLeft(noteCard) + const Offset(24, 24));
    await tester.pumpAndSettle();

    final categoryRow = find.byKey(const ValueKey('detail-category-row'));
    await tester.ensureVisible(categoryRow);
    await tester.tap(categoryRow);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail-category-list')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final travelCategory = find.byKey(const ValueKey('detail-category-travel'));
    await tester.ensureVisible(travelCategory);
    await tester.tap(travelCategory);
    await tester.pumpAndSettle();

    expect(repository.lastChanges?['category'], 'travel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches board views on a compact screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          withInvitedPeople: true,
          category: NoteCategory.shopping,
          initialReminderAt: DateTime(2026, 8, 4, 6, 39),
        ),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-grid')), findsOneWidget);
    final assignedCard = find.byKey(const ValueKey('note-note-1'));
    expect(
      find.descendant(
        of: assignedCard,
        matching: find.text('Para la reunión de mañana'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: assignedCard,
        matching: find.byKey(const ValueKey('assignee-note-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedCard, matching: find.text('Ana')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedCard, matching: find.text('Ana Torres')),
      findsNothing,
    );
    final gridContent = tester.widget<Text>(
      find.descendant(
        of: assignedCard,
        matching: find.text('Para la reunión de mañana'),
      ),
    );
    expect(gridContent.maxLines, 7);
    expect(gridContent.overflow, TextOverflow.ellipsis);
    final contentRect = tester.getRect(
      find.descendant(
        of: assignedCard,
        matching: find.text('Para la reunión de mañana'),
      ),
    );
    final assigneeRect = tester.getRect(
      find.byKey(const ValueKey('grid-assignee-note-1')),
    );
    expect(assigneeRect.top - contentRect.bottom, greaterThanOrEqualTo(10));
    expect(find.byKey(const ValueKey('masonry-grid-columns')), findsOneWidget);
    expect(find.byKey(const ValueKey('masonry-grid-column-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('masonry-grid-column-1')), findsOneWidget);
    final gridCardSize = tester.getSize(
      find.byKey(const ValueKey('reorder-grid-note-1')),
    );
    expect(gridCardSize.height, inInclusiveRange(184, 300));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('view-mode-list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);
    final compactCard = find.byKey(const ValueKey('note-note-1'));
    expect(
      find.descendant(of: compactCard, matching: find.text('Comprar café')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: compactCard,
        matching: find.text('Para la reunión de mañana'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: compactCard,
        matching: find.byIcon(Icons.notifications_none_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: compactCard,
        matching: find.byKey(const ValueKey('assignee-note-1')),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('reorder-list-note-1'))).height,
      58,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('filter-mode-completed')));
    await tester.pumpAndSettle();
    expect(find.text('No hay notas en este filtro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('masonry cards show ten tasks and open to reveal the rest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final checklist = List.generate(
      12,
      (index) => NoteChecklistItem(
        id: 'long-task-$index',
        text: 'Elemento extenso del checklist número $index',
      ),
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          noteCount: 3,
          withInvitedPeople: true,
          category: NoteCategory.shopping,
          checklist: checklist,
          initialReminderAt: DateTime(2026, 8, 4, 6, 39),
        ),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final tallCard = find.byKey(const ValueKey('reorder-grid-note-1'));
    final shortCard = find.byKey(const ValueKey('reorder-grid-note-2'));
    final tallHeight = tester.getSize(tallCard).height;
    final shortHeight = tester.getSize(shortCard).height;
    expect(tallHeight, greaterThan(shortHeight));
    expect(tallHeight, greaterThan(300));

    final firstSurface = tester.getRect(
      find.byKey(const ValueKey('note-surface-note-1')),
    );
    final secondSurface = tester.getRect(
      find.byKey(const ValueKey('note-surface-note-2')),
    );
    final thirdSurface = tester.getRect(
      find.byKey(const ValueKey('note-surface-note-3')),
    );
    final horizontalGap = secondSurface.left - firstSurface.right;
    final verticalGap = thirdSurface.top - secondSurface.bottom;
    expect(verticalGap, closeTo(horizontalGap, 0.1));

    final categoryRect = tester.getRect(
      find.byKey(const ValueKey('note-category-note-1')),
    );
    final titleRect = tester.getRect(find.text('Comprar café'));
    expect(categoryRect.top - titleRect.bottom, greaterThanOrEqualTo(8));

    final visibleChecklistItems = find.descendant(
      of: tallCard,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Checkbox &&
            widget.key.toString().contains('preview-check-long-task-'),
      ),
    );
    expect(visibleChecklistItems, findsNWidgets(10));
    final firstChecklistRect = tester.getRect(visibleChecklistItems.first);
    expect(
      firstChecklistRect.top - categoryRect.bottom,
      greaterThanOrEqualTo(10),
    );
    final openHint = find.descendant(
      of: tallCard,
      matching: find.text('2 más'),
    );
    expect(openHint, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(openHint);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-detail-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-checklist-long-task-11')),
      findsOneWidget,
    );
  });

  testWidgets('empty masonry notes show only title and optional assignee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          noteCount: 2,
          initialContent: '',
          withInvitedPeople: true,
          category: NoteCategory.shopping,
          initialReminderAt: DateTime(2026, 8, 4, 6, 39),
        ),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final assignedCard = find.byKey(const ValueKey('reorder-grid-note-1'));
    final titleOnlyCard = find.byKey(const ValueKey('reorder-grid-note-2'));
    expect(tester.getSize(assignedCard).height, 136);
    expect(tester.getSize(titleOnlyCard).height, 84);
    final titleOnlySize = tester.getSize(titleOnlyCard);
    expect(titleOnlySize.height / titleOnlySize.width, lessThan(0.55));
    expect(
      find.descendant(of: titleOnlyCard, matching: find.byType(Checkbox)),
      findsOneWidget,
    );
    final titleOnlySurface = tester.getRect(
      find.byKey(const ValueKey('note-surface-note-2')),
    );
    final titleOnlyText = tester.getRect(find.text('Nota 2'));
    expect(titleOnlyText.center.dy, closeTo(titleOnlySurface.center.dy, 2));
    expect(
      find.descendant(of: assignedCard, matching: find.text('Comprar café')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedCard, matching: find.text('Ana')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedCard, matching: find.text('Ana Torres')),
      findsNothing,
    );
    expect(
      find.descendant(of: assignedCard, matching: find.text('Compras')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: assignedCard,
        matching: find.byIcon(Icons.notifications_none_rounded),
      ),
      findsNothing,
    );
    expect(find.text('Sin detalles'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact filters stay visible on a narrow screen', (
    tester,
  ) async {
    final systemSoundCalls = _captureSystemSoundCalls(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FILTRAR'), findsNothing);
    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('Pend.'), findsOneWidget);
    expect(find.text('Listas'), findsOneWidget);
    expect(find.text('VISTA'), findsNothing);
    expect(find.text('Mosaico'), findsOneWidget);
    expect(find.text('Lista'), findsOneWidget);
    expect(find.text('Grande'), findsNothing);
    expect(
      find.byKey(const ValueKey('filter-mode-glass-blur')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('view-mode-glass-blur')), findsOneWidget);
    final filterIndicator = find.byKey(
      const ValueKey('filter-mode-selection-indicator'),
    );
    final filterPill = find.byKey(const ValueKey('filter-mode-selection-pill'));
    expect(filterIndicator, findsOneWidget);
    expect(
      find.byKey(const ValueKey('view-mode-selection-indicator')),
      findsOneWidget,
    );
    expect(
      tester.widget<AnimatedAlign>(filterIndicator).duration,
      const Duration(milliseconds: 300),
    );
    final selectedFilterDecoration =
        tester.widget<DecoratedBox>(filterPill).decoration as BoxDecoration;
    expect(
      selectedFilterDecoration.color?.a,
      allOf(greaterThan(0), lessThan(1)),
    );
    expect(selectedFilterDecoration.borderRadius, BorderRadius.circular(20));
    expect(selectedFilterDecoration.border, isNotNull);

    final startX = tester.getCenter(filterPill).dx;
    final pendingX = tester
        .getCenter(find.byKey(const ValueKey('filter-mode-pending')))
        .dx;
    await tester.tap(find.byKey(const ValueKey('filter-mode-pending')));
    await tester.pump();
    expect(
      systemSoundCalls,
      contains(
        isMethodCall('SystemSound.play', arguments: 'SystemSoundType.click'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final middleX = tester.getCenter(filterPill).dx;
    expect(middleX, allOf(greaterThan(startX), lessThan(pendingX)));
    await tester.pumpAndSettle();
    expect(tester.getCenter(filterPill).dx, closeTo(pendingX, 1));

    await tester.tap(find.byKey(const ValueKey('filter-mode-pending')));
    await tester.pump();
    expect(systemSoundCalls, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('view-mode-list')));
    await tester.pump();
    expect(systemSoundCalls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed notes move below in all and return to their original place',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        NockNockApp(
          repository: _FakeNotesRepository(noteCount: 3),
          authRepository: _FakeAuthRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('view-mode-list')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('note-note-1'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('note-note-2'))).dy,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('view-mode-grid')));
      await tester.pumpAndSettle();
      final firstGridCard = find.byKey(const ValueKey('note-note-1'));
      await tester.tap(
        find.descendant(of: firstGridCard, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();

      final completedHeader = find.byKey(
        const ValueKey('completed-section-header'),
      );
      expect(completedHeader, findsOneWidget);
      final headerRect = tester.getRect(completedHeader);
      expect(
        headerRect.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('note-note-2'))).bottom,
        ),
      );
      expect(tester.getRect(firstGridCard).top, greaterThan(headerRect.bottom));

      await tester.tap(find.byKey(const ValueKey('view-mode-list')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('note-note-1'))).top,
        greaterThan(tester.getRect(completedHeader).bottom),
      );

      await tester.tap(find.byKey(const ValueKey('filter-mode-completed')));
      await tester.pumpAndSettle();
      expect(completedHeader, findsNothing);
      expect(find.byKey(const ValueKey('note-note-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-mode-all')));
      await tester.pumpAndSettle();
      expect(completedHeader, findsOneWidget);
      final completedCard = find.byKey(const ValueKey('note-note-1'));
      await tester.tap(
        find.descendant(of: completedCard, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();

      expect(completedHeader, findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('note-note-1'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('note-note-2'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('note-note-2'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('note-note-3'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a completed pending task animates before leaving the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-mode-pending')));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('note-note-1'));
    final checkbox = find.descendant(of: card, matching: find.byType(Checkbox));
    await tester.tap(checkbox);
    await tester.pump();

    expect(card, findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('note-exit-opacity-note-1')),
          )
          .opacity,
      0,
    );
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('note-exit-scale-note-1')),
          )
          .scale,
      0.94,
    );

    await tester.pump(const Duration(milliseconds: 299));
    expect(card, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(card, findsNothing);
    expect(find.text('No hay notas en este filtro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the selected board view after reopening the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('view-mode-list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('view-mode-list')), findsOneWidget);
  });

  testWidgets('shows profile and creates a list from the menu', (tester) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-drawer-glass-blur')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawer-profile-glass-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('drawer-selected-tile-glass')),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(Drawer)).width, lessThanOrEqualTo(336));
    expect(find.byKey(const ValueKey('drawer-profile-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawer-google-sign-in-suggestion')),
      findsOneWidget,
    );
    expect(find.text('Inicia sesión con Google'), findsOneWidget);
    expect(find.text('Sincroniza y protege tus notas'), findsOneWidget);
    expect(find.byKey(const ValueKey('google-sign-in-button')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drawer-profile-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Perfil'), findsOneWidget);
    expect(find.byKey(const ValueKey('google-sign-in-button')), findsOneWidget);
    expect(find.text('Cifrado de extremo a extremo'), findsOneWidget);
    expect(
      find.text(
        'Al iniciar sesión, tus listas y notas se cifran antes de sincronizarse.',
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-list-button')));
    await tester.pumpAndSettle();

    final createListDialog = find.byKey(
      const ValueKey('create-list-glass-dialog'),
    );
    expect(createListDialog, findsOneWidget);
    expect(
      find.byKey(const ValueKey('create-list-dialog-glass-blur')),
      findsOneWidget,
    );
    expect(tester.getSize(createListDialog).width, greaterThan(560));

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(createListDialog, findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('list-name-field')),
      'trabajo',
    );
    expect(find.text('Trabajo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-list-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.text('Trabajo'), findsOneWidget);
    expect(find.text('Tu lista está lista'), findsOneWidget);
  });

  testWidgets('reorders lists from the button beside the add action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = _FakeNotesRepository(withPinnedAcrossLists: true);
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();

    final reorderButton = find.byKey(const ValueKey('reorder-lists-button'));
    final addButton = find.byKey(const ValueKey('add-list-button'));
    expect(reorderButton, findsOneWidget);
    expect(addButton, findsOneWidget);
    expect(
      tester.getCenter(reorderButton).dx,
      lessThan(tester.getCenter(addButton).dx),
    );
    expect(
      tester.getCenter(reorderButton).dy,
      closeTo(tester.getCenter(addButton).dy, 0.5),
    );
    expect(tester.getSize(reorderButton), tester.getSize(addButton));

    await tester.tap(reorderButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reorder-lists-sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reorder-lists-glass-blur')),
      findsOneWidget,
    );
    final glassSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('reorder-lists-glass-surface')),
    );
    final glassDecoration = glassSurface.decoration as BoxDecoration;
    expect(glassDecoration.gradient, isNotNull);
    expect(glassDecoration.border, isNotNull);
    expect(find.text('Ordenar listas'), findsOneWidget);
    final saveButton = find.byKey(const ValueKey('save-list-order-button'));
    final cancelButton = find.widgetWithText(OutlinedButton, 'Cancelar');
    final saveLabel = tester.widget<Text>(find.text('Guardar orden'));
    expect(saveLabel.maxLines, 1);
    expect(saveLabel.softWrap, isFalse);
    expect(tester.getSize(saveButton).height, greaterThanOrEqualTo(54));
    expect(
      tester.getSize(saveButton).width,
      greaterThan(tester.getSize(cancelButton).width),
    );
    final dragGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('reorder-list-handle-work'))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await dragGesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('reorder-list-item-home'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await dragGesture.up();
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.reorderedListIds, ['work', 'home']);

    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('list-work'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('list-home'))).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renames and deletes a list from the three-dot menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-list-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('list-name-field')),
      'trabajo',
    );
    await tester.tap(find.byKey(const ValueKey('create-list-confirm-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('list-options-button')));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar fondo'), findsOneWidget);
    expect(find.text('Editar nombre'), findsOneWidget);
    expect(find.text('Eliminar lista'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('list-options-glass-blur')),
      findsOneWidget,
    );
    final glassMenu = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('list-options-glass-menu')),
    );
    expect(glassMenu.borderRadius, BorderRadius.circular(26));
    final glassSurface =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('list-options-glass-surface')),
                )
                .decoration
            as BoxDecoration;
    final glassGradient = glassSurface.gradient! as LinearGradient;
    expect(
      glassGradient.colors.every((color) => color.a > 0 && color.a < 1),
      isTrue,
    );
    expect(glassSurface.border, isNotNull);
    await tester.tap(find.byKey(const ValueKey('rename-list-menu-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-list-name-field')),
      'proyectos',
    );
    await tester.tap(find.byKey(const ValueKey('save-list-name-button')));
    await tester.pumpAndSettle();
    expect(find.text('Proyectos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('list-options-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-list-menu-item')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Se eliminará “Proyectos” junto con todas sus notas'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('confirm-delete-list-button')));
    await tester.pumpAndSettle();

    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.text('Proyectos'), findsNothing);
  });

  testWidgets(
    'deletes the only list after confirmation and creates an empty one',
    (tester) async {
      await tester.pumpWidget(
        NockNockApp(
          repository: _FakeNotesRepository(),
          authRepository: _FakeAuthRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Comprar café'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('list-options-button')));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar lista'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-list-menu-item')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Como es tu única lista'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('confirm-delete-list-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Comprar café'), findsNothing);
      expect(find.text('Tu lista está lista'), findsOneWidget);
    },
  );

  testWidgets('opens settings from the bottom of the menu', (tester) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-menu-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-version-label')), findsOneWidget);
    expect(find.textContaining('Versión'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('VISTA DEL TABLERO'), findsNothing);
    expect(find.byKey(const ValueKey('settings-view-grid')), findsNothing);
    expect(find.byKey(const ValueKey('settings-view-list')), findsNothing);
    expect(find.text('DATOS EN ESTE DISPOSITIVO'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-ambient-background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-overview-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-appearance-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-previews-setting')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-licenses-button')),
      findsNothing,
    );
    expect(find.text('Licencias de código abierto'), findsNothing);
  });

  testWidgets('persists private notification previews from settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-menu-button')));
    await tester.pumpAndSettle();

    final previewSwitch = find.byKey(
      const ValueKey('notification-previews-switch'),
    );
    await Scrollable.ensureVisible(
      tester.element(previewSwitch),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(previewSwitch).value, isTrue);

    await tester.tap(previewSwitch);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(previewSwitch).value, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('nocknock.notification_previews_enabled.v1'),
      isFalse,
    );
    expect(
      find.text('Oculta títulos y contenido fuera de NockNock.'),
      findsOneWidget,
    );
  });

  testWidgets('shows notes assigned to the current user from the menu', (
    tester,
  ) async {
    final repository = _FakeNotesRepository(withInvitedPeople: true);
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'person-ana',
            displayName: 'Ana Torres',
            email: 'ana@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final assignedToMe = find.byKey(
      const ValueKey('assigned-to-me-menu-button'),
    );
    expect(assignedToMe, findsOneWidget);
    expect(find.text('Asignado a mí'), findsOneWidget);
    await tester.tap(assignedToMe);
    await tester.pumpAndSettle();

    expect(find.text('Asignado a mí'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    expect(find.text('1 nota'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('collaborator-avatar-stack')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('share-list-button')), findsNothing);
    expect(find.byKey(const ValueKey('list-options-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('list-options-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('customize-background-menu-item')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rename-list-menu-item')), findsNothing);
    expect(find.byKey(const ValueKey('delete-list-menu-item')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('customize-background-menu-item')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('background-preset-lagoon')));
    await tester.tap(find.byKey(const ValueKey('save-background-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preset-background-lagoon')),
      findsOneWidget,
    );
    expect(repository.lastAppearance, isNull);
  });

  testWidgets('shows pinned notes from every list with their origin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(314, 683);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          withPinnedAcrossLists: true,
          initialReminderAt: DateTime(2026, 8, 28, 6),
        ),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();

    final pinnedMenu = find.byKey(const ValueKey('pinned-menu-button'));
    expect(pinnedMenu, findsOneWidget);
    expect(find.text('Ancladas'), findsOneWidget);
    await tester.tap(pinnedMenu);
    await tester.pumpAndSettle();

    expect(find.text('Ancladas'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    expect(find.text('Preparar lanzamiento'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-list-note-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('note-list-note-pinned-work')),
      findsOneWidget,
    );
    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.text('Trabajo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(find.byKey(const ValueKey('list-options-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('list-options-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('customize-background-menu-item')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rename-list-menu-item')), findsNothing);
    expect(find.byKey(const ValueKey('delete-list-menu-item')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('customize-background-menu-item')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('background-live-preview')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pin-note-note-1')));
    await tester.pumpAndSettle();

    expect(find.text('Comprar café'), findsNothing);
    expect(find.text('Preparar lanzamiento'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('note-note-pinned-work')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-detail-page')), findsOneWidget);
    expect(find.text('Trabajo'), findsOneWidget);
  });

  testWidgets('shows notes with reminders below pinned in the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(
          withRemindersAcrossLists: true,
          initialReminderAt: DateTime(2026, 8, 12, 9),
        ),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();

    final pinnedMenu = find.byKey(const ValueKey('pinned-menu-button'));
    final reminderMenu = find.byKey(
      const ValueKey('with-reminder-menu-button'),
    );
    expect(pinnedMenu, findsOneWidget);
    expect(reminderMenu, findsOneWidget);
    expect(
      tester.getTopLeft(reminderMenu).dy,
      greaterThan(tester.getTopLeft(pinnedMenu).dy),
    );

    await tester.tap(reminderMenu);
    await tester.pumpAndSettle();

    expect(find.text('Con recordatorio'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    expect(find.text('Recordar lanzamiento'), findsOneWidget);
    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.text('Trabajo'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-list-button')), findsNothing);
    expect(find.byKey(const ValueKey('new-note-fab')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides notes assigned to another person from the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(withInvitedPeople: true),
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'owner-1',
            displayName: 'Nico',
            email: 'nico@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assigned-to-me-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('Comprar café'), findsNothing);
    expect(
      find.text('No tienes notas asignadas en esta lista'),
      findsOneWidget,
    );
  });

  testWidgets('keeps appearance controls in the profile instead of settings', (
    tester,
  ) async {
    final themeController = AppThemeController();
    addTearDown(themeController.dispose);
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
        themeController: themeController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('APARIENCIA'), findsNothing);
    expect(find.byKey(const ValueKey('theme-mode-system')), findsNothing);
    expect(find.byKey(const ValueKey('theme-mode-light')), findsNothing);
    expect(find.byKey(const ValueKey('theme-mode-dark')), findsNothing);
    expect(find.text('CUENTA'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-profile-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TEMA DE COLOR'), findsOneWidget);
    expect(find.text('MODO'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-theme-dark')), findsOneWidget);
  });

  testWidgets('changes the whole app color theme from the profile', (
    tester,
  ) async {
    final themeController = AppThemeController();
    addTearDown(themeController.dispose);
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
        themeController: themeController,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TEMA DE COLOR'), findsOneWidget);
    expect(find.text('MODO'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-color-theme-sunset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-color-theme-ocean')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-color-theme-forest')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-color-theme-violet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-color-theme-cherry')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('profile-theme-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-theme-light')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-theme-dark')), findsOneWidget);

    final initialPrimary = Theme.of(
      tester.element(find.text('Atardecer')),
    ).colorScheme.primary;
    for (var page = 0; page < 3; page++) {
      await tester.drag(
        find.byKey(const ValueKey('profile-color-theme-list')),
        const Offset(-600, 0),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const ValueKey('profile-color-theme-graphite')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('profile-color-theme-graphite')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final graphitePrimary = Theme.of(
      tester.element(find.text('Grafito')),
    ).colorScheme.primary;
    expect(themeController.colorTheme, AppColorTheme.graphite);
    expect(graphitePrimary, isNot(initialPrimary));
    expect(
      graphitePrimary,
      AppTheme.lightFor(AppColorTheme.graphite).colorScheme.primary,
    );
  });

  testWidgets('keeps a completed note legible in dark mode', (tester) async {
    final themeController = AppThemeController();
    await themeController.setThemeMode(ThemeMode.dark);
    addTearDown(themeController.dispose);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(initiallyCompleted: true),
        authRepository: _FakeAuthRepository(),
        themeController: themeController,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('note-note-1'));
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('note-surface-note-1')),
    );
    final checkbox = tester.widget<Checkbox>(
      find.descendant(of: card, matching: find.byType(Checkbox)),
    );

    expect(surface.color?.a, 1);
    expect(
      find.descendant(
        of: card,
        matching: find.widgetWithIcon(IconButton, Icons.edit_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      ),
      findsNothing,
    );
    expect(checkbox.activeColor, AppTheme.ink);
    expect(checkbox.checkColor, Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirms and clears guest data from settings', (tester) async {
    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('CUENTA'), findsOneWidget);
    expect(find.text('DATOS EN ESTE DISPOSITIVO'), findsOneWidget);
    expect(find.text('ACERCA DE'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('clear-local-data-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-local-data-button')));
    await tester.pumpAndSettle();

    expect(find.text('¿Limpiar los datos locales?'), findsOneWidget);
    expect(repository.didClearLocalData, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('confirm-clear-local-data-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.didClearLocalData, isTrue);
    expect(find.text('Los datos locales fueron eliminados.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tu lista está lista'), findsOneWidget);
  });

  testWidgets('opens profile from the app bar and shows the Google photo', (
    tester,
  ) async {
    const user = AppUser(
      id: 'google-user',
      displayName: 'Nico Galdames',
      email: 'nico@example.com',
      photoUrl: 'https://example.com/avatar.jpg',
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(isConnected: true, isEncrypted: true),
        authRepository: _FakeAuthRepository(user: user),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-photo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('connected-status-indicator')),
      findsOneWidget,
    );
    final connectionIcon = tester.getRect(
      find.byKey(const ValueKey('connected-status-indicator')),
    );
    final lockBadge = tester.getRect(
      find.byKey(const ValueKey('encryption-lock-badge')),
    );
    expect(lockBadge.center.dx, greaterThan(connectionIcon.center.dx));
    expect(lockBadge.center.dy, greaterThan(connectionIcon.center.dy));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('encryption-lock-badge')),
        matching: find.byIcon(Icons.lock_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('En vivo'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('connection-status-button')));
    await tester.pumpAndSettle();
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Al día'), findsOneWidget);
    expect(find.text('Activo en esta lista'), findsOneWidget);
    expect(find.text('AES-256-GCM'), findsOneWidget);
    expect(find.text('Protegidas por dispositivo'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('close-connection-status-dialog')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Nico Galdames'), findsOneWidget);
    expect(find.text('nico@example.com'), findsOneWidget);
    expect(find.text('CUENTA CONECTADA'), findsOneWidget);
    expect(find.text('Sincronización activa'), findsOneWidget);
    expect(find.text('Cifrado de extremo a extremo'), findsOneWidget);
    expect(
      find.text(
        'Tus listas y notas se cifran antes de sincronizarse. Solo tú y tus colaboradores autorizados pueden leerlas.',
      ),
      findsOneWidget,
    );
    final floatingNote = find.byKey(
      const ValueKey('profile-floating-icon-note'),
    );
    expect(floatingNote, findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-floating-icon-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-floating-icon-lock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-floating-icon-cloud')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-floating-icon-shield')),
      findsOneWidget,
    );
    final initialTransform = tester
        .widget<Transform>(floatingNote)
        .transform
        .storage
        .toList();
    await tester.pump(const Duration(milliseconds: 700));
    final movedTransform = tester
        .widget<Transform>(floatingNote)
        .transform
        .storage
        .toList();
    expect(movedTransform, isNot(equals(initialTransform)));
    final heroCenterX = tester
        .getCenter(find.byKey(const ValueKey('profile-hero-card')))
        .dx;
    for (final centeredElement in [
      find.byKey(const ValueKey('profile-photo')),
      find.text('Nico Galdames'),
      find.text('nico@example.com'),
      find.byKey(const ValueKey('profile-connection-badge')),
    ]) {
      expect(tester.getCenter(centeredElement).dx, closeTo(heroCenterX, 1));
    }
    expect(find.text('ZONA DE RIESGO'), findsOneWidget);
  });

  testWidgets('profile app bar fades into the content while scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(
          user: const AppUser(
            id: 'profile-user',
            displayName: 'Nicolás Galdames',
            email: 'nico@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final fade = find.byKey(const ValueKey('profile-appbar-bottom-fade'));
    final background = find.byKey(const ValueKey('profile-appbar-background'));
    expect(
      find.byKey(const ValueKey('profile-ambient-background')),
      findsOneWidget,
    );
    expect(fade, findsOneWidget);
    expect(background, findsOneWidget);
    final initialAlpha = tester.widget<ColoredBox>(background).color.a;

    await tester.drag(
      find.byKey(const ValueKey('profile-scroll-view')),
      const Offset(0, -140),
    );
    await tester.pump();

    final scrolledAlpha = tester.widget<ColoredBox>(background).color.a;
    expect(scrolledAlpha, greaterThan(initialAlpha));
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates the open connection dialog in real time', (
    tester,
  ) async {
    const user = AppUser(
      id: 'google-user',
      displayName: 'Nico Galdames',
      email: 'nico@example.com',
    );
    final repository = _FakeNotesRepository(isEncrypted: true);
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(user: user),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('connection-status-button')));
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión'), findsOneWidget);

    final syncCard = tester.getRect(
      find.byKey(const ValueKey('sync-status-row')),
    );
    final syncDetails = tester.getRect(
      find.byKey(const ValueKey('sync-status-details')),
    );
    expect(syncDetails.left, closeTo(syncCard.left + 14, 1));
    expect(syncDetails.right, closeTo(syncCard.right - 14, 1));

    repository.emitRealtime(const RealtimeConnectionAttemptStarted());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Conectando…'), findsOneWidget);
    expect(find.text('Estableciendo…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('connection-status-dialog')),
      findsOneWidget,
    );

    repository.emitRealtime(const RealtimeConnectionChanged(true));
    await tester.pumpAndSettle();
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Al día'), findsOneWidget);
  });

  testWidgets('keeps account deletion inside profile, not in the menu', (
    tester,
  ) async {
    const user = AppUser(
      id: 'google-user',
      displayName: 'Nico Galdames',
      email: 'nico@example.com',
    );
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(user: user),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drawer-profile-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-account-button')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drawer-profile-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Perfil'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-account-button')), findsOneWidget);
  });

  testWidgets('requires confirmation before deleting an account', (
    tester,
  ) async {
    const user = AppUser(
      id: 'google-user',
      displayName: 'Nico Galdames',
      email: 'nico@example.com',
    );
    final authRepository = _FakeAuthRepository(user: user);
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(isConnected: true),
        authRepository: authRepository,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final deleteAccountButton = find.byKey(
      const ValueKey('delete-account-button'),
    );
    await tester.ensureVisible(deleteAccountButton);
    await tester.pump();
    await tester.tap(deleteAccountButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
    expect(authRepository.didDeleteAccount, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-account-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(authRepository.didDeleteAccount, isTrue);
  });

  testWidgets('asks guests to sign in before sharing a list', (tester) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('share-list-button')));
    await tester.pumpAndSettle();

    expect(find.text('Inicia sesión para compartir'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-sign-in-button')), findsOneWidget);
  });

  testWidgets('invites a collaborator by email from a signed-in list', (
    tester,
  ) async {
    const user = AppUser(
      id: 'google-user',
      displayName: 'Nico',
      email: 'nico@example.com',
    );
    final repository = _FakeNotesRepository();
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(user: user),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('share-list-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('collaborators-dialog')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('send-invitation-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('collaborator-email-field')),
      'correo-invalido',
    );
    await tester.pump();

    expect(find.text('Escribe un correo válido'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('send-invitation-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('collaborator-email-field')),
      'ana@example.com',
    );
    await tester.pump();

    expect(find.text('Escribe un correo válido'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('send-invitation-button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('send-invitation-button')));
    await tester.pumpAndSettle();

    expect(repository.invitedEmail, 'ana@example.com');
    expect(find.text('Invitación enviada a ana@example.com.'), findsOneWidget);
  });

  testWidgets('owner confirms before removing a collaborator', (tester) async {
    const user = AppUser(
      id: 'google-user',
      displayName: 'Nico',
      email: 'nico@example.com',
    );
    final repository = _FakeNotesRepository(withInvitedPeople: true);
    await tester.pumpWidget(
      NockNockApp(
        repository: repository,
        authRepository: _FakeAuthRepository(user: user),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('share-list-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('remove-collaborator-person-ana')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remove-collaborator-owner-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('remove-collaborator-person-ana')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('remove-collaborator-dialog')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Las notas de la lista no se eliminarán'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirm-remove-collaborator')));
    await tester.pumpAndSettle();

    expect(repository.removedCollaboratorUid, 'person-ana');
    expect(find.text('Ana Torres ya no tiene acceso.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remove-collaborator-person-ana')),
      findsNothing,
    );
  });

  testWidgets('adds depth and parallax to the app bar while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(noteCount: 12),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final background = find.byKey(const ValueKey('appbar-parallax-background'));
    final header = find.byKey(const ValueKey('board-header-parallax'));
    final bottomFade = find.byKey(const ValueKey('appbar-bottom-fade'));
    final contentFade = find.byKey(const ValueKey('appbar-content-fade'));
    final appBar = find.byKey(const ValueKey('parallax-app-bar'));
    expect(bottomFade, findsOneWidget);
    expect(contentFade, findsOneWidget);
    expect(
      tester.getBottomLeft(bottomFade).dy,
      closeTo(tester.getBottomLeft(appBar).dy, 0.1),
    );
    final initialDecoration =
        tester.widget<DecoratedBox>(background).decoration as BoxDecoration;
    final initialHeaderOffset = tester
        .widget<Transform>(header)
        .transform
        .getTranslation()
        .y;
    final initialTitleTop = tester.getTopLeft(find.text('Mis notas')).dy;

    expect(initialHeaderOffset, 0);
    await tester.drag(
      find.descendant(
        of: find.byKey(const ValueKey('notes-grid')),
        matching: find.byType(SingleChildScrollView),
      ),
      const Offset(0, -72),
    );
    await tester.pump();

    final scrolledDecoration =
        tester.widget<DecoratedBox>(background).decoration as BoxDecoration;
    final scrolledHeaderOffset = tester
        .widget<Transform>(header)
        .transform
        .getTranslation()
        .y;
    final scrolledTitleTop = tester.getTopLeft(find.text('Mis notas')).dy;

    expect(scrolledHeaderOffset, greaterThan(6));
    expect(scrolledTitleTop, lessThan(initialTitleTop - 45));
    expect(
      scrolledDecoration.color!.a,
      greaterThan(initialDecoration.color!.a),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the final card scrolls completely above the floating action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(noteCount: 3),
        authRepository: _FakeAuthRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-mode-list')));
    await tester.pumpAndSettle();

    final list = find.byType(ReorderableListView);
    await tester.fling(list, const Offset(0, -1600), 2400);
    await tester.pumpAndSettle();

    final lastCard = tester.getRect(
      find.byKey(const ValueKey('note-surface-note-3')),
    );
    final floatingAction = tester.getRect(
      find.byKey(const ValueKey('new-note-fab')),
    );

    expect(lastCard.bottom, lessThan(floatingAction.top - 12));
    expect(lastCard.bottom, lessThan(tester.view.physicalSize.height));
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.user});

  final AppUser? user;
  bool didDeleteAccount = false;

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser => user;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  @override
  Future<void> deleteAccount() async => didDeleteAccount = true;

  @override
  Future<void> signOut() async {}
}

class _FakeNotesRepository implements NotesRepository, LocalNotesDataCleaner {
  _FakeNotesRepository({
    this.isConnected = false,
    this.isEncrypted = false,
    this.withInvitedPeople = false,
    this.initiallyCompleted = false,
    this.noteCount = 1,
    this.collaboratorPhotoUrl,
    this.initialAssigneeUid,
    this.withPinnedAcrossLists = false,
    this.withRemindersAcrossLists = false,
    this.initialContent = 'Para la reunión de mañana',
    String? initialContentDelta,
    NoteCategory category = NoteCategory.general,
    List<NoteChecklistItem> checklist = const [],
    List<NoteReaction> reactions = const [],
    DateTime? initialReminderAt,
  }) : _note = Note(
         id: 'note-1',
         boardId: 'home',
         title: 'Comprar café',
         content: initialContent,
         contentDelta: initialContentDelta,
         color: NoteColor.yellow,
         category: category,
         checklist: checklist,
         reactions: reactions,
         authorName: 'Nico',
         assigneeUid:
             initialAssigneeUid ?? (withInvitedPeople ? 'person-ana' : null),
         isCompleted: initiallyCompleted,
         isPinned: withPinnedAcrossLists,
         positionX: 0,
         positionY: 0,
         reminderAt: initialReminderAt,
         createdAt: DateTime(2026),
         updatedAt: DateTime(2026),
       ),
       _lists = [
         NoteList(
           id: 'home',
           name: 'Mis notas',
           createdAt: DateTime(2026),
           updatedAt: DateTime(2026),
           collaborators: withInvitedPeople
               ? [
                   ListCollaborator(
                     uid: 'owner-1',
                     email: 'nico@example.com',
                     displayName: 'Nico',
                     role: ListMemberRole.owner,
                     joinedAt: DateTime(2026),
                   ),
                   ListCollaborator(
                     uid: 'person-ana',
                     email: 'ana@example.com',
                     displayName: 'Ana Torres',
                     photoUrl: collaboratorPhotoUrl,
                     role: ListMemberRole.editor,
                     joinedAt: DateTime(2026),
                   ),
                 ]
               : const [],
           pendingInvitations: withInvitedPeople
               ? [
                   ListPendingInvitation(
                     email: 'pedro@example.com',
                     invitedAt: DateTime(2026),
                   ),
                 ]
               : const [],
           encryption: isEncrypted
               ? const ListEncryption(version: 1)
               : const ListEncryption(),
         ),
         if (withPinnedAcrossLists || withRemindersAcrossLists)
           NoteList(
             id: 'work',
             name: 'Trabajo',
             createdAt: DateTime(2026),
             updatedAt: DateTime(2026),
           ),
       ];

  final bool isConnected;
  final bool isEncrypted;
  final bool withInvitedPeople;
  final bool initiallyCompleted;
  final int noteCount;
  final String? collaboratorPhotoUrl;
  final String? initialAssigneeUid;
  final bool withPinnedAcrossLists;
  final bool withRemindersAcrossLists;
  final String initialContent;
  final _realtimeController = StreamController<NotesRealtimeEvent>.broadcast();

  Note _note;
  final List<NoteList> _lists;
  bool didClearLocalData = false;
  String? invitedEmail;
  String? removedCollaboratorUid;
  Map<String, dynamic>? lastChanges;
  List<String>? reorderedListIds;
  NoteDraft? createdDraft;
  ListAppearance? lastAppearance;

  @override
  bool get isLocalDataActive => true;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents async* {
    if (isConnected) yield const RealtimeConnectionChanged(true);
    yield* _realtimeController.stream;
  }

  void emitRealtime(NotesRealtimeEvent event) => _realtimeController.add(event);

  @override
  Future<void> connect(String boardId) async {}

  @override
  void disconnect() {}

  @override
  Future<List<NoteList>> fetchLists() async => List.of(_lists);

  @override
  Future<NoteList> createList(String name) async {
    final list = NoteList(
      id: 'list-${_lists.length}',
      name: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    _lists.add(list);
    return list;
  }

  @override
  Future<NoteList> updateList(String listId, String name) async {
    final index = _lists.indexWhere((list) => list.id == listId);
    final updated = _lists[index].copyWith(
      name: name,
      updatedAt: DateTime(2026, 1, 2),
    );
    _lists[index] = updated;
    return updated;
  }

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) async {
    final listsById = {for (final list in _lists) list.id: list};
    if (orderedIds.length != _lists.length ||
        orderedIds.toSet().length != orderedIds.length ||
        !listsById.keys.toSet().containsAll(orderedIds)) {
      throw const NotesPersistenceFailure();
    }
    reorderedListIds = List.of(orderedIds);
    final reordered = orderedIds.map((id) => listsById[id]!).toList();
    _lists
      ..clear()
      ..addAll(reordered);
    return List.of(_lists);
  }

  @override
  Future<void> deleteList(String listId) async {
    _lists.removeWhere((list) => list.id == listId);
  }

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    invitedEmail = email;
    return _lists.firstWhere((list) => list.id == listId);
  }

  @override
  Future<NoteList> removeCollaborator(
    String listId,
    String collaboratorUid,
  ) async {
    removedCollaboratorUid = collaboratorUid;
    final index = _lists.indexWhere((list) => list.id == listId);
    final current = _lists[index];
    final updated = NoteList(
      id: current.id,
      name: current.name,
      createdAt: current.createdAt,
      updatedAt: DateTime(2026, 1, 2),
      currentUserRole: current.currentUserRole,
      collaborators: current.collaborators
          .where((person) => person.uid != collaboratorUid)
          .toList(),
      pendingInvitations: current.pendingInvitations,
      appearance: current.appearance,
    );
    _lists[index] = updated;
    return updated;
  }

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) async {
    lastAppearance = appearance;
    final index = _lists.indexWhere((list) => list.id == listId);
    final updated = _lists[index].copyWith(appearance: appearance);
    _lists[index] = updated;
    return updated;
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    if (boardId != 'home' || didClearLocalData) return [];
    return List.generate(noteCount, (index) {
      if (index == 0) return _note;
      return Note(
        id: 'note-${index + 1}',
        boardId: _note.boardId,
        title: 'Nota ${index + 1}',
        content: _note.content,
        color: NoteColor.values[index % NoteColor.values.length],
        authorName: _note.authorName,
        isCompleted: false,
        sortOrder: index,
        positionX: 0,
        positionY: index.toDouble(),
        createdAt: _note.createdAt,
        updatedAt: _note.updatedAt,
      );
    });
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    if (!withPinnedAcrossLists || didClearLocalData) return const [];
    return [
      _note,
      Note(
        id: 'note-pinned-work',
        boardId: 'work',
        title: 'Preparar lanzamiento',
        content: 'Revisar los últimos detalles',
        color: NoteColor.blue,
        authorName: 'Nico',
        isCompleted: false,
        isPinned: true,
        positionX: 0,
        positionY: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026, 1, 2),
      ),
    ];
  }

  @override
  Future<List<Note>> fetchReminderNotes() async {
    if (didClearLocalData) return const [];
    return [
      if (_note.reminderAt != null) _note,
      if (withRemindersAcrossLists)
        Note(
          id: 'note-reminder-work',
          boardId: 'work',
          title: 'Recordar lanzamiento',
          content: 'Revisar la publicación',
          color: NoteColor.blue,
          authorName: 'Nico',
          isCompleted: false,
          positionX: 0,
          positionY: 0,
          reminderAt: DateTime(2026, 8, 20, 9),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026, 1, 2),
        ),
    ];
  }

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    createdDraft = draft;
    return _note;
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async => orderedIds.contains(_note.id) ? [_note] : const [];

  @override
  Future<void> deleteNote(String id) async {}

  @override
  Future<void> clearLocalData() async {
    didClearLocalData = true;
    _lists.removeWhere((list) => list.id != 'home');
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    lastChanges = Map.of(changes);
    final existing = _note;
    _note = Note(
      id: existing.id,
      boardId: existing.boardId,
      title: changes['title'] as String? ?? existing.title,
      content: changes['content'] as String? ?? existing.content,
      contentDelta: changes.containsKey('contentDelta')
          ? changes['contentDelta'] as String?
          : existing.contentDelta,
      color: changes['color'] == null
          ? existing.color
          : NoteColor.values.byName(changes['color'] as String),
      category: changes['category'] == null
          ? existing.category
          : NoteCategory.values.byName(changes['category'] as String),
      checklist: changes['checklist'] == null
          ? existing.checklist
          : (changes['checklist'] as List<dynamic>)
                .map(
                  (item) => NoteChecklistItem.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(),
      reactions: existing.reactions,
      authorName: changes['authorName'] as String? ?? existing.authorName,
      assigneeUid: changes.containsKey('assigneeUid')
          ? changes['assigneeUid'] as String?
          : existing.assigneeUid,
      isCompleted: changes['isCompleted'] as bool? ?? existing.isCompleted,
      isPinned: changes['isPinned'] as bool? ?? existing.isPinned,
      sortOrder: (changes['sortOrder'] as num?)?.toInt() ?? existing.sortOrder,
      positionX:
          (changes['positionX'] as num?)?.toDouble() ?? existing.positionX,
      positionY:
          (changes['positionY'] as num?)?.toDouble() ?? existing.positionY,
      reminderAt: changes.containsKey('reminderAt')
          ? DateTime.tryParse(changes['reminderAt'] as String? ?? '')
          : existing.reminderAt,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    return _note;
  }

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    const userUid = 'owner-1';
    final reactions = [..._note.reactions];
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    final users = index == -1 ? <String>{} : reactions[index].userUids.toSet();
    active ? users.add(userUid) : users.remove(userUid);
    if (users.isEmpty) {
      if (index != -1) reactions.removeAt(index);
    } else {
      final reaction = NoteReaction(emoji: emoji, userUids: users.toList());
      if (index == -1) {
        reactions.add(reaction);
      } else {
        reactions[index] = reaction;
      }
    }
    _note = _note.copyWith(reactions: reactions, updatedAt: DateTime.now());
    return _note;
  }

  @override
  void dispose() {
    unawaited(_realtimeController.close());
  }
}
