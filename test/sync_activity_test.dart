import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/sync_activity_sheet.dart';
import 'package:nocknock/features/notes/presentation/sync_conflicts_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final date = DateTime(2026, 10, 21, 12);
Note note(String title) => Note(
  id: 'n',
  boardId: 'home',
  title: title,
  content: 'Contenido de $title',
  color: NoteColor.blue,
  authorName: 'Ana',
  isCompleted: false,
  positionX: 0,
  positionY: 0,
  createdAt: date,
  updatedAt: date,
);

void main() {
  setUpAll(() async => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('saved status never claims a pending or disconnected change is saved in the account', () {
    const ready = NotesState(
      syncStateKnown: true,
      status: NotesStatus.ready,
      isRealtimeConnected: true,
    );
    expect(
      SyncPresentation.fromState(
        const NotesState(status: NotesStatus.ready, isRealtimeConnected: true),
      ).title,
      'Comprobando cambios…',
    );
    expect(SyncPresentation.fromState(ready).title, 'Todo guardado');
    expect(
      SyncPresentation.fromState(ready.copyWith(isSaving: true)).title,
      'Guardando cambios…',
    );
    expect(
      SyncPresentation.fromState(ready.copyWith(pendingSyncCount: 1)).title,
      '1 cambio pendiente',
    );
    expect(
      SyncPresentation.fromState(ready.copyWith(isRealtimeConnected: false))
          .title,
      'Sin cambios pendientes',
    );
    expect(
      SyncPresentation.fromState(ready.copyWith(syncConflictCount: 1)).title,
      '1 cambio necesita revisión',
    );
  });

  testWidgets('activity lists pending notes and updates after retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = _SyncCubit(conflict: false);
    final protection = ListProtectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSyncActivitySheet(
                context: context,
                cubit: cubit,
                protection: protection,
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Mi edición'), findsOneWidget);
    expect(find.text('1 cambio pendiente'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-activity-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Todo guardado'), findsOneWidget);
    expect(find.text('Mi edición'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
    protection.dispose();
  });

  testWidgets(
    'conflicts compare changed titles and require confirmation, and protected lists stay hidden',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cubit = _SyncCubit(conflict: true);
      final protection = ListProtectionController();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSyncConflictsSheet(
                  context: context,
                  cubit: cubit,
                  protection: protection,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Mi edición'), findsOneWidget);
      expect(find.text('Edición de Ana'), findsOneWidget);
      final remote = find.byKey(const ValueKey('keep-remote-c'));
      await tester.ensureVisible(remote);
      await tester.tap(remote);
      await tester.pumpAndSettle();
      expect(cubit.decisions, 0);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(cubit.decisions, 0);
      await tester.ensureVisible(remote);
      await tester.tap(remote);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-sync-resolution')));
      await tester.pumpAndSettle();
      expect(cubit.decisions, 1);
      expect(find.text('No quedan versiones por comparar.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(cubit.close);
      protection.dispose();

      SharedPreferences.setMockInitialValues({
        'protected_note_list_ids_v1': ['home'],
      });
      final preferences = (await tester.runAsync(
        SharedPreferences.getInstance,
      ))!;
      final locked = ListProtectionController(preferences: preferences);
      final protectedCubit = _SyncCubit(conflict: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSyncConflictsSheet(
                  context: context,
                  cubit: protectedCubit,
                  protection: locked,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Mi edición'), findsNothing);
      expect(find.text('Edición de Ana'), findsNothing);
      expect(
        find.text('Desbloquea la lista para comparar sus cambios.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(protectedCubit.close);
      locked.dispose();
    },
  );
}

class _Repository extends Fake implements NotesRepository {
  @override
  void dispose() {}
}

class _SyncCubit extends NotesCubit {
  _SyncCubit({required bool conflict}) : super(_Repository()) {
    changes = [
      PendingNoteChange(
        id: 'c',
        boardId: 'home',
        kind: OfflineMutationKind.update,
        createdAt: date,
        needsReview: conflict,
        canCompare: conflict,
        note: note('Mi edición'),
      ),
    ];
    conflicts = conflict
        ? [
            NoteSyncConflict(
              mutationId: 'c',
              kind: OfflineMutationKind.update,
              localNote: note('Mi edición'),
              remoteNote: note('Edición de Ana'),
            ),
          ]
        : [];
    emit(
      NotesState(
        status: NotesStatus.ready,
        syncStateKnown: true,
        isRealtimeConnected: true,
        lists: [
          NoteList(id: 'home', name: 'Casa', createdAt: date, updatedAt: date),
        ],
        pendingSyncCount: conflict ? 0 : 1,
        syncConflictCount: conflict ? 1 : 0,
      ),
    );
  }
  late List<PendingNoteChange> changes;
  late List<NoteSyncConflict> conflicts;
  int decisions = 0;
  @override
  Future<List<PendingNoteChange>> fetchPendingChanges() async => changes;
  @override
  Future<List<NoteSyncConflict>> fetchSyncConflicts() async => conflicts;
  @override
  Future<void> retryOfflineSync() async {
    changes = [];
    emit(state.copyWith(pendingSyncCount: 0));
  }

  @override
  Future<void> resolveSyncConflict(
    String mutationId,
    NoteConflictResolution resolution,
  ) async {
    decisions++;
    conflicts = [];
    changes = [];
    emit(state.copyWith(syncConflictCount: 0));
  }
}
