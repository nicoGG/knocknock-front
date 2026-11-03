import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/features/assistant/assistant_client.dart';
import 'package:nocknock/features/assistant/nock_face.dart';
import 'package:nocknock/features/assistant/assistant_excerpt.dart';
import 'package:nocknock/features/assistant/assistant_page.dart';
import 'package:nocknock/features/assistant/assistant_view.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends Fake implements AuthRepository {
  @override
  AppUser get currentUser => const AppUser(
    id: 'alice',
    displayName: 'Ana',
    email: 'private@example.com',
  );
  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async =>
      'firebase-token';
}

void main() {
  final now = DateTime(2026, 11, 3);
  final list = NoteList(
    id: 'home',
    name: 'Casa',
    createdAt: now,
    updatedAt: now,
  );
  final note = Note(
    id: 'private-id',
    boardId: 'home',
    title: 'Comprar pan',
    content: 'Integral',
    color: NoteColor.yellow,
    authorName: 'private-author',
    isCompleted: false,
    positionX: 0,
    positionY: 0,
    createdAt: now,
    updatedAt: now,
    reminderAt: now,
    checklist: const [
      NoteChecklistItem(id: 'private-subtask', text: 'Visitar panadería'),
    ],
    assigneeUid: 'private-uid',
    attachments: const [
      NoteAttachment(
        id: 'private-photo',
        name: 'secret.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 3,
        dataBase64: 'private-bytes',
      ),
    ],
  );

  test('only accessible notes and the allowlisted fields can enter a partial excerpt', () async {
    final state = NotesState(
      lists: [list],
      notes: [
        note,
        Note.fromJson({
          ...note.toJson(),
          'boardId': 'other',
          'title': 'Other list',
        }),
        Note.fromJson({
          ...note.toJson(),
          'deletedAt': now.toIso8601String(),
          'title': 'Deleted note',
        }),
        ...List.generate(
          13,
          (i) => Note.fromJson({...note.toJson(), 'title': 'Extra $i'}),
        ),
      ],
      hasMoreNotes: true,
    );
    final excerpt = assistantExcerpt(list, state);
    expect(excerpt, contains('12 de 14'));
    expect(excerpt, contains('Visitar panadería'));
    for (final secret in [
      'Extra 12',
      'private-',
      'secret.pdf',
      'Other list',
      'Deleted note',
    ]) {
      expect(excerpt, isNot(contains(secret)));
    }
    SharedPreferences.setMockInitialValues({
      'protected_note_list_ids_v1': ['home'],
    });
    final protection = ListProtectionController(
      preferences: await SharedPreferences.getInstance(),
    );
    expect(assistantList(state, 'home', protection), isNull);
    final unprotected = ListProtectionController();
    expect(assistantList(state, 'home', unprotected), list);
    expect(assistantList(state, null, unprotected), isNull);
    expect(
      assistantList(
        state.copyWith(lists: [list.copyWith(isEncryptionKeyPending: true)]),
        'home',
        unprotected,
      ),
      isNull,
    );
  });

  test('a pending reminder survives the excerpt limit even when it is last on the board', () {
    final state = NotesState(
      notes: [
        ...List.generate(
          20,
          (i) => Note.fromJson({
            ...note.toJson(),
            'title': 'Terminada $i',
            'isCompleted': true,
          }),
        ),
        note,
      ],
    );
    expect(
      assistantExcerpt(list, state).split('• ').elementAt(1),
      startsWith('Comprar pan'),
    );
  });

  test('financial excerpts distinguish the outstanding total from the next installment and omit counterparties', () {
    final entry = FinancialEntry(
      amountMinor: 10001,
      currency: 'CLP',
      counterparty: 'Comercio privado',
      date: now,
      dueDate: now,
      paymentMethod: 'credit',
      installments: 3,
      payments: [FinancialPayment(id: 'payment', amountMinor: 3500, date: now)],
    );
    final record = Note.fromJson({
      ...note.toJson(),
      'financialData': entry.encoded,
    });
    final expenses = list.copyWith(
      configuration: const ListConfiguration(type: NoteListType.expenses),
    );
    final text = assistantExcerpt(expenses, NotesState(notes: [record]));
    expect(text, contains('saldo ${FinancialEntry.formatAmount(6501, 'CLP')}'));
    expect(
      text,
      contains('próxima cuota 2: ${FinancialEntry.formatAmount(3168, 'CLP')}'),
    );
    expect(text, isNot(contains(entry.counterparty)));
  });

  test('Today excludes protected, revoked and key-pending lists from counts and suggested actions', () async {
    final now = DateTime.now();
    NoteList make(String id) =>
        NoteList(id: id, name: id, createdAt: now, updatedAt: now);
    final sources = [
      list,
      make('secret'),
      make('revoked'),
      make('pending').copyWith(isEncryptionKeyPending: true),
    ];
    final results = [
      for (final l in sources)
        NoteSearchResult(
          list: l,
          note: Note.fromJson({
            ...note.toJson(),
            'id': 'note-${l.id}',
            'boardId': l.id,
            'title': 'Tarea ${l.id}',
            'reminderAt': now
                .subtract(const Duration(days: 1))
                .toIso8601String(),
          }),
        ),
    ];
    SharedPreferences.setMockInitialValues({
      'protected_note_list_ids_v1': ['secret'],
    });
    final protection = ListProtectionController(
      preferences: await SharedPreferences.getInstance(),
    );
    final view = AssistantView.today(
      results,
      NotesState(lists: [sources[0], sources[1], sources[3]]),
      protection,
      'alice',
    );
    expect(view.excerpt, contains('Atrasadas: 1'));
    expect(view.suggestion, contains('atrasadas'));
    expect(view.excerpt, contains('Tarea home'));
    for (final id in ['secret', 'revoked', 'pending']) {
      expect(view.excerpt, isNot(contains(id)));
    }
  });

  test('budget uses the selected month and currency and separates proposed from saved limits', () {
    final expenses = list.copyWith(
      configuration: const ListConfiguration(type: NoteListType.expenses),
    );
    Note entry(
      String id,
      int amount,
      String currency,
      DateTime date, {
      bool budget = false,
      String status = 'pending',
      String board = 'home',
    }) => Note.fromJson({
      ...note.toJson(),
      'id': id,
      'boardId': board,
      'financialData': FinancialEntry(
        kind: budget ? 'budget' : 'entry',
        period: budget ? '2026-11' : 'all',
        date: date,
        counterparty: '',
        amountMinor: amount,
        currency: currency,
        status: status,
      ).encoded,
    });
    final state = NotesState(
      lists: [expenses],
      notes: [
        entry('budget', 10000, 'CLP', now, budget: true),
        entry('nov', 12000, 'CLP', now),
        entry('last', 90000, 'CLP', DateTime(2026, 10, 1)),
        entry('dollars', 50000, 'USD', now),
        entry('other', 20000, 'CLP', now, board: 'elsewhere'),
      ],
    );
    final v = AssistantView.budget(expenses, state, (
      currency: 'CLP',
      period: '2026-11',
      proposedLimit: 15000,
    ));
    expect(
      v.excerpt,
      contains('Exceso: ${FinancialEntry.formatAmount(2000, 'CLP')}'),
    );
    expect(
      v.excerpt,
      contains('sin guardar: ${FinancialEntry.formatAmount(15000, 'CLP')}'),
    );
    expect(v.suggestion, 'Entender el exceso');
  });

  testWidgets(
    'Nock docks above the create button, dismisses individual tips and remembers a drag',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalNotesRepository();
      await tester.runAsync(
        () => repo.createNote(
          'home',
          const NoteDraft(
            title: 'Compras',
            content: '',
            color: NoteColor.yellow,
            authorName: 'Ana',
          ),
        ),
      );
      final auth = _Auth();
      Widget app() => NockNockApp(
        repository: repo,
        authRepository: auth,
        preferences: prefs,
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final mascot = find.byKey(const ValueKey('nock-mascot'));
      final fab = tester.getRect(find.byKey(const ValueKey('new-note-fab')));
      final docked = tester.getRect(mascot);
      expect(docked.center.dx, closeTo(fab.center.dx, 1));
      expect(docked.bottom, closeTo(fab.top - 8, 1));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('¿Ordenamos tus pendientes?'), findsOneWidget);
      expect(
        tester.widget<NockFace>(find.byType(NockFace)).amount,
        greaterThan(0),
      );
      await tester.tap(find.byTooltip('Cerrar sugerencia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Keep the bubble mounted while its exit transition runs.
      expect(find.text('¿Ordenamos tus pendientes?'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('¿Ordenamos tus pendientes?'), findsNothing);
      expect(
        prefs.getStringList('nock_dismissed_tips_v1'),
        contains('priorities'),
      );
      await tester.pump(const Duration(seconds: 36));
      await tester.pumpAndSettle();
      await tester.tap(find.text('¿Preparamos una nota?'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('Quiero preparar una nota'),
      );
      await tester.tap(find.byTooltip('Cerrar chat'));
      await tester.pumpAndSettle();
      await tester.drag(mascot, const Offset(-150, -190));
      await tester.pumpAndSettle();
      final moved = tester.getCenter(mascot);
      expect(moved.dy, lessThan(docked.center.dy - 100));
      expect(prefs.getDouble('nock_position_y'), isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        NockNockApp(
          repository: LocalNotesRepository(),
          authRepository: auth,
          preferences: prefs,
        ),
      );
      await tester.pumpAndSettle();
      expect((tester.getCenter(mascot) - moved).distance, lessThan(1));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('¿Ordenamos tus pendientes?'), findsNothing);
      expect(find.text('¿Preparamos una nota?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'mascot drags, recognizes Today, and hands a list proposal to the normal creation flow',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repo = LocalNotesRepository();
      final sent = <Map<String, dynamic>>[];
      AssistantClient client() {
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (opt, handler) {
              sent.add(opt.data as Map<String, dynamic>);
              handler.resolve(
                Response(
                  requestOptions: opt,
                  data: <String, dynamic>{
                    'answer': 'Puedes agrupar los gastos de la mudanza.',
                    if (opt.data['question'].toString().contains('mudanza'))
                      'listDraft': {
                        'name': 'Traslado',
                        'listType': 'expenses',
                        'currency': 'USD',
                        'customTypeName': '',
                      },
                  },
                ),
              );
            },
          ),
        );
        return AssistantClient(dio: dio);
      }

      await tester.pumpWidget(
        NockNockApp(
          repository: repo,
          authRepository: _Auth(),
          createAssistantClient: client,
        ),
      );
      await tester.pumpAndSettle();
      final mascot = find.byKey(const ValueKey('nock-mascot'));
      final before = tester.getCenter(mascot);
      await tester.drag(mascot, const Offset(-110, -85));
      await tester.pumpAndSettle();
      final moved = tester.getCenter(mascot);
      expect(moved.dx, lessThan(before.dx - 30));
      final faceBeforeTap = tester.getTopLeft(find.byType(NockFace));
      await tester.tap(mascot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AssistantPage), findsNothing);
      expect(
        tester.getTopLeft(find.byType(NockFace)).dy,
        lessThan(faceBeforeTap.dy),
      );
      // Repeated taps during the bounce must still open only one chat.
      await tester.tap(mascot);
      await tester.pumpAndSettle();
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(find.text('Mis notas'), findsOneWidget);
      final closeDuration = ModalRoute.of(
        tester.element(find.byType(AssistantPage)),
      )!.reverseTransitionDuration;
      await tester.tap(find.byTooltip('Cerrar chat'));
      await tester.pump();
      await tester.pump(closeDuration + const Duration(milliseconds: 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(AssistantPage), findsNothing);
      final returnedFace = tester.getTopLeft(find.byType(NockFace));
      await tester.pumpAndSettle();
      expect(
        returnedFace.dy,
        lessThan(tester.getTopLeft(find.byType(NockFace)).dy),
      );
      await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-menu-button')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(mascot).dx, closeTo(moved.dx, 1));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.tap(find.text('¿Planeamos tu día?'));
      await tester.pumpAndSettle();
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Preparar mi día'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
      expect(find.text('Extracto adjunto'), findsOneWidget);
      expect(find.text('Texto que se enviará'), findsOneWidget);
      expect(sent, isEmpty);
      await tester.tap(find.byTooltip('Quitar extracto'));
      await tester.pumpAndSettle();
      expect(find.text('Texto que se enviará'), findsNothing);
      await tester.tap(find.text('Elegir tres tareas'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('hasta tres pendientes'),
      );
      expect(sent, isEmpty);
      expect(find.text('Extracto adjunto'), findsOneWidget);
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(sent.single['screen'], 'today');
      expect(sent.single['excerpt'], contains('Para hoy'));
      expect(find.text('Extracto adjunto'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        'Organiza mis gastos de mudanza en dólares',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent.last['mode'], 'chat');
      expect(sent.last['screen'], 'today');
      expect(sent.last.containsKey('excerpt'), isFalse);
      expect(sent.last['previousExchange'], contains('hasta tres pendientes'));
      await tester.tap(find.text('Revisar lista'));
      await tester.pumpAndSettle();
      expect(find.text('Traslado'), findsOneWidget);
      expect(
        (await repo.fetchLists()).any((l) => l.name == 'Traslado'),
        isFalse,
      );
      await tester.tap(
        find.byKey(const ValueKey('create-list-confirm-button')),
      );
      await tester.pumpAndSettle();
      final saved = (await repo.fetchLists()).singleWhere(
        (l) => l.name == 'Traslado',
      );
      expect(
        saved.configuration,
        const ListConfiguration(type: NoteListType.expenses, currency: 'USD'),
      );
    },
  );

  testWidgets(
    'the new-note editor applies AI subtasks without replacing the typed title or saving early',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repo = LocalNotesRepository();
      final auth = _Auth();
      AssistantClient client() {
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (opt, handler) {
              expect(opt.data['screen'], 'createNote');
              expect(opt.data['mode'], 'draft');
              handler.resolve(
                Response(
                  requestOptions: opt,
                  data: <String, dynamic>{
                    'answer': 'Revisa estos pasos.',
                    'draft': {
                      'title': 'Salida',
                      'content': 'Para mañana',
                      'checklist': ['Revisar pasajes'],
                    },
                  },
                ),
              );
            },
          ),
        );
        return AssistantClient(dio: dio);
      }

      await tester.pumpWidget(
        NockNockApp(
          repository: repo,
          authRepository: auth,
          createAssistantClient: client,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Crear una nota'));
      await tester.tap(find.text('Crear una nota'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-title-field')),
        'Mi viaje',
      );
      await tester.ensureVisible(find.text('Completar nota con Nock'));
      await tester.tap(find.text('Completar nota con Nock'));
      await tester.pumpAndSettle();
      expect(find.text('Mi viaje'), findsOneWidget);
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar propuesta'));
      await tester.pumpAndSettle();
      expect((await repo.fetchNotes('home')), isEmpty);
      await tester.tap(find.text('Crear nota'));
      await tester.pumpAndSettle();
      final saved = (await repo.fetchNotes('home')).single;
      expect(saved.title, 'Mi viaje');
      expect(saved.checklist.single.text, 'Revisar pasajes');
    },
  );

  testWidgets(
    'dictation preserves the draft, accepts corrections and never sends on its own',
    (tester) async {
      const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final messenger = tester.binding.defaultBinaryMessenger;
      var allowed = false;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' || 'has_permission' => allowed,
          'locales' => ['es_CL:Español de Chile'],
          'listen' => true,
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<void> native(String method, String data) async {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, data)),
          (_) {},
        );
        await tester.pump();
      }

      Future<void> words(String text, {bool finalResult = false}) => native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': text, 'confidence': .92},
          ],
          'resultType': finalResult ? 2 : 0,
        }),
      );

      final cubit = NotesCubit(LocalNotesRepository());
      addTearDown(cubit.close);
      final requests = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opt, handler) {
            requests.add(opt.data['question'] as String);
            handler.resolve(
              Response(requestOptions: opt, data: {'answer': 'Anotado.'}),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            cubit: cubit,
            protection: ListProtectionController(),
            listId: null,
            auth: _Auth(),
            userId: 'alice',
            createClient: () => AssistantClient(dio: dio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final microphone = find.byTooltip('Dictar mensaje');
      final field = find.byType(TextField);
      final draft = tester.widget<TextField>(field).controller!;
      await tester.enterText(field, 'Comprar algo mañana');
      draft.selection = const TextSelection(baseOffset: 8, extentOffset: 12);
      await tester.tap(microphone);
      await tester.pumpAndSettle();
      expect(find.textContaining('Permite el micrófono'), findsOneWidget);
      expect(draft.text, 'Comprar algo mañana');
      allowed = true;
      await tester.tap(microphone);
      await tester.pump();
      expect(
        calls.lastWhere((c) => c.method == 'listen').arguments['localeId'],
        'es_CL',
      );
      await native('notifyStatus', 'listening');
      await words('pa');
      expect(draft.text, 'Comprar pa mañana');
      await words('pan');
      expect(draft.text, 'Comprar pan mañana');
      await tester.tap(find.byTooltip('Terminar dictado'));
      await tester.pump();
      expect(calls.any((c) => c.method == 'stop'), isTrue);
      await words('pan integral', finalResult: true);
      await native('notifyStatus', 'done');
      await tester.pumpAndSettle();
      expect(draft.text, 'Comprar pan integral mañana');
      expect(requests, isEmpty);
      await tester.tap(microphone);
      await tester.pump();
      await native('notifyStatus', 'listening');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.any((c) => c.method == 'cancel'), isTrue);
      await words('resultado tardío');
      expect(draft.text, 'Comprar pan integral mañana');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(microphone);
      await tester.pump();
      await native('notifyStatus', 'listening');
      await native('notifyStatus', 'done');
      await native(
        'notifyError',
        jsonEncode({'errorMsg': 'error_unknown (300)', 'permanent': true}),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('El servicio de voz no pudo cargar'),
        findsOneWidget,
      );
      expect(draft.text, 'Comprar pan integral mañana');
      expect(requests, isEmpty);
      await tester.enterText(field, 'Comprar dos panes mañana');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(requests, ['Comprar dos panes mañana']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'receipt-only chat creates a reviewed expense in a new list and retains its image',
    (tester) async {
      tester.view.physicalSize = const Size(450, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repo = LocalNotesRepository(), cubit = NotesCubit(repo);
      addTearDown(cubit.close);
      await tester.runAsync(() async {
        await repo.createNote(
          'home',
          const NoteDraft(
            title: 'Compras de hoy',
            content: '',
            color: NoteColor.yellow,
            authorName: 'Ana',
          ),
        );
        await cubit.load();
      });
      const receipt = NoteAttachment(
        id: 'photo-test',
        name: 'boleta.png',
        mimeType: 'image/png',
        sizeBytes: 68,
        dataBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jmZkAAAAASUVORK5CYII=',
      );
      final requests = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opt, handler) {
            requests.add(opt.data as Map<String, dynamic>);
            handler.resolve(
              Response(
                requestOptions: opt,
                data: {
                  'answer': 'Revisa el gasto.',
                  'expenses': [
                    {
                      'title': 'Pan y verduras',
                      'merchant': 'Almacén',
                      'detail': 'Compra semanal',
                      'amountMinor': 12750,
                      'currency': 'CLP',
                      'date': '2026-11-03',
                      'status': 'paid',
                      'suggestedList': 'Despensa',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            auth: _Auth(),
            userId: 'alice',
            cubit: cubit,
            protection: ListProtectionController(),
            listId: 'home',
            pickReceipt: (_) async => [receipt],
            createClient: () => AssistantClient(dio: dio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjuntar boleta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Incluir extracto de la lista'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 680);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(find.text('2 adjuntos'), findsOneWidget);
      await tester.tap(find.text('2 adjuntos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar extracto'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(450, 1250);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      expect(find.text('Boleta adjunta'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(requests.single['actionVersion'], 1);
      expect(requests.single['receipt'], {
        'mimeType': 'image/png',
        'data': receipt.dataBase64,
      });
      expect(requests.single.containsKey('excerpt'), isFalse);
      await tester.tap(find.text('Crear lista «Despensa»'));
      await tester.pumpAndSettle();
      expect(
        (await repo.fetchLists()).any((l) => l.name == 'Despensa'),
        isFalse,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Crear lista'));
      await tester.pumpAndSettle();
      final list = (await repo.fetchLists()).singleWhere(
        (l) => l.name == 'Despensa',
      );
      expect(list.configuration.type, NoteListType.expenses);
      expect(await repo.fetchNotes(list.id), isEmpty);
      await tester.tap(find.text('Revisar gasto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Despensa · CLP'));
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('financial-amount'));
      expect(tester.widget<TextFormField>(amount).controller!.text, '12.750');
      await tester.enterText(amount, '12900');
      final save = find.byKey(const ValueKey('financial-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final note = (await repo.fetchNotes(list.id)).single;
      expect(note.financialEntry!.amountMinor, 12900);
      expect(note.financialEntry!.date, DateTime(2026, 11, 3));
      expect(note.financialEntry!.counterparty, 'Almacén');
      expect(note.photoAttachments.single.dataBase64, receipt.dataBase64);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Gasto guardado'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'chat edits the chosen note after review without overwriting unrelated fields or concurrent edits',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalNotesRepository(), cubit = NotesCubit(repo);
      addTearDown(cubit.close);
      late Note original;
      await tester.runAsync(() async {
        original = await repo.createNote(
          'home',
          const NoteDraft(
            title: 'Viaje',
            content: 'Plan original',
            authorName: 'Ana',
            color: NoteColor.green,
            checklist: [
              NoteChecklistItem(id: 'first', text: 'Comprar pasajes'),
            ],
          ),
        );
        await cubit.load();
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opt, h) => h.resolve(
            Response(
              requestOptions: opt,
              data: {
                'answer': 'Revisa tus cambios',
                'noteEdit': {
                  'targetTitle': 'Viaje',
                  'newTitle': 'Viaje al sur',
                  'addTasks': ['Reservar bus'],
                  'completeTasks': ['Comprar pasajes'],
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            auth: _Auth(),
            userId: 'alice',
            protection: ListProtectionController(),
            cubit: cubit,
            listId: 'home',
            noteId: original.id,
            createClient: () => AssistantClient(dio: dio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edita mi nota de viaje');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      final review = find.text('Revisar cambios');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect((await repo.fetchNotes('home')).single.title, 'Viaje');
      await repo.updateNote(original.id, {'content': 'Cambio de otra persona'});
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(find.textContaining('La nota cambió'), findsOneWidget);
      expect((await repo.fetchNotes('home')).single.checklist.length, 1);
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      final updated = (await repo.fetchNotes('home')).single;
      expect(updated.id, original.id);
      expect(updated.title, 'Viaje al sur');
      expect(updated.content, 'Cambio de otra persona');
      expect(updated.color, NoteColor.green);
      expect(updated.checklist.first.id, 'first');
      expect(updated.checklist.first.isCompleted, isTrue);
      expect(updated.checklist.last.text, 'Reservar bus');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the board menu opens the assistant without making a request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      NockNockApp(repository: LocalNotesRepository(), authRepository: _Auth()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appbar-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();
    expect(find.text('Asistente de NockNock'), findsOneWidget);
    expect(find.text('Tu consulta'), findsOneWidget);
  });

  testWidgets(
    'conversation scrolls behind the floating composer and its last row clears the keyboard and multiline input',
    (tester) async {
      tester.view.physicalSize = const Size(390, 744);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final cubit = NotesCubit(LocalNotesRepository());
      addTearDown(cubit.close);
      await tester.runAsync(cubit.load);
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api'));
      final response = List.filled(
        10,
        'Anota los precios de cada producto y compáralos antes de comprar.',
      ).join('\n\n');
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(requestOptions: options, data: {'answer': response}),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            auth: _Auth(),
            userId: 'alice',
            cubit: cubit,
            protection: ListProtectionController(),
            listId: 'home',
            createClient: () => AssistantClient(dio: dio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Ayúdame a comparar mis compras.',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      final transcript = find.byType(ListView);
      final composer = find.byKey(
        const ValueKey('assistant-floating-composer'),
      );
      expect(
        tester.getRect(find.byType(TextField)).width,
        greaterThan(tester.getRect(composer).width * .85),
      );
      expect(
        tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Enviar')).top),
      );
      final scroll = tester.widget<ListView>(transcript).controller!;
      Future<void> verifyEnd() async {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(transcript).bottom,
          greaterThan(tester.getRect(composer).bottom),
        );
        expect(
          tester.getRect(find.text('Ideas para esta vista')).bottom,
          lessThan(tester.getRect(composer).top),
        );
      }

      await verifyEnd();
      scroll.jumpTo(
        scroll.position.maxScrollExtent - tester.getRect(composer).height - 100,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text(response)).overlaps(tester.getRect(composer)),
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.view.padding = FakeViewPadding.zero;
      await tester.enterText(
        find.byType(TextField),
        'Un mensaje\nde varias\nlíneas',
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(744 - 280));
      await verifyEnd();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'authenticated questions, optional context, follow-up, review and save use the real editor',
    (tester) async {
      tester.view.physicalSize = const Size(450, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repo = LocalNotesRepository();
      final cubit = NotesCubit(repo);
      addTearDown(cubit.close);
      await tester.runAsync(() async {
        await repo.createNote(
          'home',
          const NoteDraft(
            title: 'Revisar factura',
            content: 'Texto de mi lista',
            color: NoteColor.yellow,
            authorName: 'Ana',
          ),
        );
        await cubit.load();
      });
      final requests = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(
              options.uri.toString(),
              'https://backend.test/api/assistant',
            );
            expect(options.headers['Authorization'], 'Bearer firebase-token');
            final body = options.data as Map<String, dynamic>;
            requests.add(body);
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{
                  'answer': 'Empieza por la factura.',
                  if (body['mode'] == 'draft')
                    'draft': {
                      'title': 'Plan sugerido',
                      'content': 'Para mañana',
                      'checklist': ['Llamar'],
                    },
                },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: AssistantPage(
            auth: _Auth(),
            userId: 'alice',
            cubit: cubit,
            protection: ListProtectionController(),
            listId: 'home',
            createClient: () => AssistantClient(dio: dio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> send(String text) async {
        await tester.enterText(find.byType(TextField).first, text);
        await tester.ensureVisible(find.byTooltip('Enviar'));
        await tester.pump();
        await tester.tap(find.byTooltip('Enviar'));
        await tester.pumpAndSettle();
      }

      await send('Cómo creo una nota');
      expect(requests.single.containsKey('excerpt'), isFalse);
      await send('Explícame el último paso');
      expect(requests.last['previousExchange'], contains('Cómo creo una nota'));
      await send('Dame un ejemplo');
      expect(
        requests.last['previousExchange'],
        allOf(
          contains('Cómo creo una nota'),
          contains('Explícame el último paso'),
        ),
      );
      expect(find.text('Cómo creo una nota'), findsOneWidget);
      await tester.ensureVisible(find.text('Incluir extracto de la lista'));
      await tester.tap(find.text('Incluir extracto de la lista'));
      await tester.pumpAndSettle();
      await send('Resume la lista');
      expect(requests.last['excerpt'], contains('Revisar factura'));
      expect(requests.last.containsKey('previousExchange'), isFalse);
      await tester.tap(find.text('Incluir extracto de la lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear borrador'));
      await tester.pumpAndSettle();
      await send('Prepara un plan');
      expect(requests.last.containsKey('excerpt'), isFalse);
      expect(requests.last.containsKey('previousExchange'), isFalse);
      final count = cubit.state.notes.length;
      await tester.tap(find.textContaining('Revisar nota en'));
      await tester.pumpAndSettle();
      expect(cubit.state.notes.length, count);
      expect(find.text('Crear nota'), findsOneWidget);
      await tester.tap(find.text('Crear nota'));
      await tester.pumpAndSettle();
      expect(cubit.state.notes.length, count + 1);
      expect(
        cubit.state.notes
            .firstWhere((n) => n.title == 'Plan sugerido')
            .checklist
            .single
            .text,
        'Llamar',
      );
      expect(find.text('Nota guardada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
