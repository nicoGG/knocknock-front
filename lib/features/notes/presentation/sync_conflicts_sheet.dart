import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_version_preview.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';

Future<void> showSyncConflictsSheet({
  required BuildContext context,
  required NotesCubit cubit,
  ListProtectionController? protection,
}) => showLiquidBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  builder: (_) => _SyncConflictsSheet(cubit: cubit, protection: protection),
);

class _SyncConflictsSheet extends StatefulWidget {
  const _SyncConflictsSheet({required this.cubit, this.protection});
  final NotesCubit cubit;
  final ListProtectionController? protection;
  @override
  State<_SyncConflictsSheet> createState() => _SyncConflictsSheetState();
}

class _SyncConflictsSheetState extends State<_SyncConflictsSheet> {
  late Future<List<NoteSyncConflict>> _conflicts = widget.cubit
      .fetchSyncConflicts();
  String? _resolvingId;
  String? _message;
  bool _accessible(NoteSyncConflict conflict) {
    final list = widget.cubit.state.lists
        .where((list) => list.id == conflict.localNote.boardId)
        .firstOrNull;
    return list != null &&
        !list.isEncryptionKeyPending &&
        (widget.protection?.canAccess(list.id) ?? true);
  }

  Future<void> _resolve(
    NoteSyncConflict conflict,
    NoteConflictResolution resolution,
  ) async {
    if (_resolvingId != null || !_accessible(conflict)) return;
    final keepLocal = resolution == NoteConflictResolution.keepLocal;
    final deleting = keepLocal && conflict.kind == OfflineMutationKind.delete;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => LiquidAlertDialog(
        icon: Icon(
          deleting
              ? Icons.delete_outline_rounded
              : Icons.compare_arrows_rounded,
        ),
        title: Text(
          deleting
              ? '¿Eliminar la nota actualizada?'
              : keepLocal
              ? '¿Conservar tu versión?'
              : '¿Usar la versión de la cuenta?',
        ),
        content: Text(
          deleting
              ? 'La nota cambió en otro dispositivo. Se enviará tu decisión de eliminarla.'
              : keepLocal
              ? 'Tu cambio pendiente se enviará sobre la versión de la cuenta. Revisa las dos versiones antes de continuar.'
              : 'Se descartará este cambio pendiente de tu dispositivo y se conservará la versión de la cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-sync-resolution'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              deleting
                  ? 'Eliminar igualmente'
                  : keepLocal
                  ? 'Conservar la mía'
                  : 'Usar la de la cuenta',
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_accessible(conflict)) return;
    setState(() {
      _resolvingId = conflict.mutationId;
      _message = null;
    });
    try {
      await widget.cubit.resolveSyncConflict(conflict.mutationId, resolution);
      if (mounted) {
        setState(() {
          _conflicts = widget.cubit.fetchSyncConflicts();
          _message = widget.cubit.state.pendingSyncCount > 0
              ? 'Decisión guardada. Aún hay cambios por enviar.'
              : 'Decisión guardada.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'No pudimos aplicar esa decisión. El cambio sigue guardado en este dispositivo.',
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.protection ?? const AlwaysStoppedAnimation(false),
    builder: (context, _) => BlocBuilder<NotesCubit, NotesState>(
      bloc: widget.cubit,
      builder: (context, state) {
        final colors = Theme.of(context).colorScheme;
        return PopScope(
          canPop: _resolvingId == null,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .85,
            child: Stack(
              children: [
                const Positioned.fill(child: AmbientPageBackground()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 18),
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.onSurface.withValues(alpha: .28),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.compare_arrows_rounded,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Revisar cambios',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: _resolvingId == null
                                ? () => Navigator.pop(context)
                                : null,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Esta nota cambió en otro dispositivo. Tus cambios siguen guardados aquí: compara las versiones y elige cuál conservar.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _message!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: FutureBuilder<List<NoteSyncConflict>>(
                          future: _conflicts,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: TextButton(
                                  onPressed: () => setState(
                                    () => _conflicts = widget.cubit
                                        .fetchSyncConflicts(),
                                  ),
                                  child: const Text(
                                    'No pudimos cargar las versiones. Reintentar',
                                  ),
                                ),
                              );
                            }
                            final conflicts = snapshot.data ?? const [];
                            if (conflicts.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        state.syncConflictCount > 0
                                            ? Icons.sync_problem_rounded
                                            : Icons.task_alt_rounded,
                                        size: 40,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        state.syncConflictCount > 0
                                            ? 'Algunos cambios no tienen una versión disponible para comparar. Vuelve a Tus cambios para reintentarlos.'
                                            : 'No quedan versiones por comparar.',
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return ScrollEdgeFade(
                              child: ListView.separated(
                                key: const ValueKey('sync-conflicts-list'),
                                padding: EdgeInsets.only(
                                  bottom:
                                      24 + MediaQuery.paddingOf(context).bottom,
                                ),
                                itemCount: conflicts.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final conflict = conflicts[index];
                                  if (!_accessible(conflict)) {
                                    return Container(
                                      padding: const EdgeInsets.all(20),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.lock_rounded),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Desbloquea la lista para comparar sus cambios.',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Container(
                                    key: ValueKey(
                                      'sync-conflict-${conflict.mutationId}',
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: colors.surface.withValues(
                                        alpha: .35,
                                      ),
                                      borderRadius: BorderRadius.circular(26),
                                      border: Border.all(
                                        color: colors.outlineVariant.withValues(
                                          alpha: .3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _VersionBlock(
                                          label:
                                              conflict.kind ==
                                                  OfflineMutationKind.delete
                                              ? 'Tu acción: eliminar esta nota'
                                              : 'Tu versión · guardada aquí',
                                          note: conflict.localNote,
                                          state: state,
                                        ),
                                        const SizedBox(height: 16),
                                        _VersionBlock(
                                          label: 'Versión de la cuenta',
                                          note: conflict.remoteNote,
                                          state: state,
                                        ),
                                        const SizedBox(height: 14),
                                        OutlinedButton(
                                          key: ValueKey(
                                            'keep-remote-${conflict.mutationId}',
                                          ),
                                          onPressed: _resolvingId != null
                                              ? null
                                              : () => _resolve(
                                                  conflict,
                                                  NoteConflictResolution
                                                      .keepRemote,
                                                ),
                                          child: const Text(
                                            'Usar la de la cuenta',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        FilledButton.tonal(
                                          key: ValueKey(
                                            'keep-local-${conflict.mutationId}',
                                          ),
                                          onPressed: _resolvingId != null
                                              ? null
                                              : () => _resolve(
                                                  conflict,
                                                  NoteConflictResolution
                                                      .keepLocal,
                                                ),
                                          child: Text(
                                            _resolvingId == conflict.mutationId
                                                ? 'Aplicando…'
                                                : conflict.kind ==
                                                      OfflineMutationKind.delete
                                                ? 'Eliminar igualmente'
                                                : 'Conservar la mía',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _VersionBlock extends StatelessWidget {
  const _VersionBlock({
    required this.label,
    required this.note,
    required this.state,
  });
  final String label;
  final Note note;
  final NotesState state;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final collaborators =
        state.lists
            .where((list) => list.id == note.boardId)
            .firstOrNull
            ?.collaborators ??
        const [];
    final names = [
      ...note.assignedUserIds.map(
        (id) =>
            collaborators
                .where((person) => person.uid == id)
                .firstOrNull
                ?.displayName ??
            'Persona asignada',
      ),
      ...note.assignedCustomNames,
    ];
    final editor = note.lastEditedByName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: colors.primary),
        ),
        const SizedBox(height: 4),
        Text(
          '${editor?.isNotEmpty == true ? editor : 'Último cambio'} · ${DateFormat('dd-MM-yyyy · HH:mm', 'es').format((note.lastEditedAt ?? note.updatedAt).toLocal())}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        NoteVersionPreview(note: note),
        const SizedBox(height: 8),
        Text(
          '${NoteCategoryStyle.label(note.category)} · ${note.isCompleted ? 'Completada' : 'Pendiente'}${note.isPinned ? ' · Anclada' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (names.isNotEmpty)
          Text(
            'Responsables: ${names.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (note.reminderAt != null)
          Text(
            'Recordatorio: ${DateFormat('dd-MM-yyyy · HH:mm', 'es').format(note.reminderAt!.toLocal())}${note.reminderRecurrence != null ? ' · Recurrente' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (final attachment in note.photoAttachments)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Adjunto: ${attachment.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
