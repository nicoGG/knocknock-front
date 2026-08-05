import 'package:flutter/material.dart';
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
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(pinRect.center.dy, lessThan(cardRect.top));
    expect(pinRect.bottom, greaterThan(cardRect.top));

    await tester.tap(find.byKey(const ValueKey('pin-note-note-1')));
    await tester.pumpAndSettle();
    expect(repository.lastChanges, containsPair('isPinned', true));
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);

    await tester.tap(find.text('Lista grande'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-large-list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-note-button')));
    await tester.pumpAndSettle();

    expect(find.text('Nueva nota'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('note-title-field')), findsOneWidget);
  });

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
    final realtimeLabel = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data?.toLowerCase().contains('tiempo real') ?? false),
    );
    final listOptionsButtonRect = tester.getRect(listOptionsButton);
    final realtimeLabelRect = tester.getRect(realtimeLabel);
    final verticalCenterDelta =
        listOptionsButtonRect.center.dy - realtimeLabelRect.center.dy;
    expect(
      verticalCenterDelta.abs(),
      lessThan(1),
      reason:
          'button=$listOptionsButtonRect, label=$realtimeLabelRect, delta=$verticalCenterDelta',
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
    await tester.enterText(fields.at(0), 'Preparar pauta');
    await tester.enterText(fields.at(1), 'Confirmar asistentes');

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
    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderable.onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    final reordered = repository.lastChanges?['checklist'] as List<dynamic>;
    expect(reordered.map((item) => item['id']), ['task-2', 'task-3', 'task-1']);
    expect(reordered.first['indent'], 0);
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
    expect(find.text('Mis notas'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    final contentViewer = tester.widget<NoteRichTextViewer>(
      find.byType(NoteRichTextViewer),
    );
    expect(contentViewer.plainText, 'Para la reunión de mañana');
    expect(find.text('Agregar recordatorio'), findsOneWidget);
    expect(find.text('Creada por'), findsOneWidget);
    expect(find.text('Nico'), findsNWidgets(2));
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

  testWidgets('keeps the note content editor compact on a phone', (
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

    final dialogSurface = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first;
    expect(tester.getSize(dialogSurface).height, lessThan(600));
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

    await tester.tap(find.byKey(const ValueKey('detail-color-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-color-blue')));
    await tester.pumpAndSettle();
    expect(find.text('Azul'), findsOneWidget);
    expect(repository.lastChanges?['color'], 'blue');

    await tester.tap(find.byKey(const ValueKey('detail-category-row')));
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

    await tester.tap(find.byKey(const ValueKey('detail-reminder-row')));
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

  testWidgets('shows accepted and pending invited people in note detail', (
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

    expect(find.text('Persona invitada'), findsOneWidget);
    expect(find.text('Ana Torres\nana@example.com'), findsOneWidget);
    expect(find.text('Invitación pendiente'), findsOneWidget);
    expect(find.text('pedro@example.com'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('view-mode-largeList')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('assignee-note-1')), findsOneWidget);
    expect(find.byTooltip('Responsable: Ana Torres'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const ValueKey('assignee-avatar-note-1')),
    );
    expect(avatar.foregroundImage, isA<NetworkImage>());
    expect((avatar.foregroundImage! as NetworkImage).url, photoUrl);
    final authorAvatar = tester.widget<CircleAvatar>(
      find.byKey(const ValueKey('author-avatar-note-1')),
    );
    expect(authorAvatar.foregroundImage, isA<NetworkImage>());
    expect((authorAvatar.foregroundImage! as NetworkImage).url, authorPhotoUrl);
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

  testWidgets('can leave an assigned task without a responsible person', (
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
    await tester.tap(find.byKey(const ValueKey('detail-assignee-row')));
    await tester.pumpAndSettle();

    final assigneeField = find.byKey(const ValueKey('note-assignee-field'));
    await tester.ensureVisible(assigneeField);
    await tester.tap(assigneeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin responsable').last);
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('save-note-button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.lastChanges, containsPair('assigneeUid', null));
    expect(find.text('Sin responsable'), findsOneWidget);
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
      findsNothing,
    );
    expect(
      find.descendant(
        of: assignedCard,
        matching: find.byKey(const ValueKey('assignee-note-1')),
      ),
      findsOneWidget,
    );
    final grid = tester.widget<GridView>(
      find.descendant(
        of: find.byKey(const ValueKey('notes-grid')),
        matching: find.byType(GridView),
      ),
    );
    expect(grid.gridDelegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    final gridCardSize = tester.getSize(
      find.byKey(const ValueKey('reorder-grid-note-1')),
    );
    expect(gridCardSize.width / gridCardSize.height, closeTo(0.86, 0.01));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('view-mode-list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('view-mode-largeList')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-large-list')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('filter-mode-completed')));
    await tester.pumpAndSettle();
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

    expect(find.byKey(const ValueKey('google-sign-in-button')), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(
      find.textContaining('Tus cambios se guardan en este dispositivo'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-list-button')));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const ValueKey('settings-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('VISTA DEL TABLERO'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-view-list')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-list')), findsOneWidget);
  });

  testWidgets('shows notes assigned to the current user from the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      NockNockApp(
        repository: _FakeNotesRepository(withInvitedPeople: true),
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

  testWidgets('changes the whole app to dark mode from settings', (
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

    expect(find.text('APARIENCIA'), findsOneWidget);
    expect(find.text('Usar configuración del sistema'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(themeController.themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Modo oscuro'))).brightness,
      Brightness.dark,
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
        repository: _FakeNotesRepository(isConnected: true),
        authRepository: _FakeAuthRepository(user: user),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-photo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('connected-status-indicator')),
      findsOneWidget,
    );
    expect(find.text('En vivo'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pumpAndSettle();

    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Nico Galdames'), findsOneWidget);
    expect(find.text('nico@example.com'), findsOneWidget);
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-account-button')));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
    expect(authRepository.didDeleteAccount, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-account-button')),
    );
    await tester.pumpAndSettle();

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
    this.withInvitedPeople = false,
    this.initiallyCompleted = false,
    this.collaboratorPhotoUrl,
    this.initialAssigneeUid,
    NoteCategory category = NoteCategory.general,
    List<NoteChecklistItem> checklist = const [],
    DateTime? initialReminderAt,
  }) : _note = Note(
         id: 'note-1',
         boardId: 'home',
         title: 'Comprar café',
         content: 'Para la reunión de mañana',
         color: NoteColor.yellow,
         category: category,
         checklist: checklist,
         authorName: 'Nico',
         assigneeUid:
             initialAssigneeUid ?? (withInvitedPeople ? 'person-ana' : null),
         isCompleted: initiallyCompleted,
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
         ),
       ];

  final bool isConnected;
  final bool withInvitedPeople;
  final bool initiallyCompleted;
  final String? collaboratorPhotoUrl;
  final String? initialAssigneeUid;

  Note _note;
  final List<NoteList> _lists;
  bool didClearLocalData = false;
  String? invitedEmail;
  Map<String, dynamic>? lastChanges;
  NoteDraft? createdDraft;
  ListAppearance? lastAppearance;

  @override
  bool get isLocalDataActive => true;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => isConnected
      ? Stream.value(const RealtimeConnectionChanged(true))
      : const Stream.empty();

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
  Future<void> deleteList(String listId) async {
    _lists.removeWhere((list) => list.id == listId);
  }

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    invitedEmail = email;
    return _lists.firstWhere((list) => list.id == listId);
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
  Future<List<Note>> fetchNotes(String boardId) async =>
      boardId == 'home' && !didClearLocalData ? [_note] : [];

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
  void dispose() {}
}
