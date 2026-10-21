import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/sync_conflicts_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';

class SyncPresentation {
  const SyncPresentation(this.title, this.detail, this.icon);
  final String title;
  final String detail;
  final IconData icon;
  factory SyncPresentation.fromState(NotesState state) {
    if (!state.syncStateKnown) {
      return const SyncPresentation(
        'Comprobando cambios…',
        'Estamos comprobando si este dispositivo tiene cambios pendientes.',
        Icons.sync_rounded,
      );
    }
    if (state.syncConflictCount > 0) {
      return SyncPresentation(
        state.syncConflictCount == 1
            ? '1 cambio necesita revisión'
            : '${state.syncConflictCount} cambios necesitan revisión',
        'Hay dos versiones de una nota. Compáralas antes de elegir cuál conservar.',
        Icons.sync_problem_rounded,
      );
    }
    if (state.pendingSyncCount > 0) {
      return SyncPresentation(
        state.isSyncingOfflineChanges
            ? 'Enviando cambios…'
            : '${state.pendingSyncCount} ${state.pendingSyncCount == 1 ? 'cambio pendiente' : 'cambios pendientes'}',
        'Guardados en este dispositivo. Se enviarán automáticamente cuando sea posible.',
        Icons.cloud_upload_rounded,
      );
    }
    if (state.isSaving ||
        state.isSavingList ||
        state.isSavingAppearance ||
        state.isInviting ||
        state.isRemovingCollaborator ||
        state.isSyncingOfflineChanges) {
      return const SyncPresentation(
        'Guardando cambios…',
        'Espera un momento mientras confirmamos el guardado.',
        Icons.cloud_sync_rounded,
      );
    }
    if (state.status != NotesStatus.ready || state.isRealtimeConnecting) {
      return const SyncPresentation(
        'Actualizando…',
        'Comprobando la conexión y los cambios disponibles.',
        Icons.sync_rounded,
      );
    }
    if (!state.isRealtimeConnected) {
      return const SyncPresentation(
        'Sin cambios pendientes',
        'La copia de este dispositivo está guardada. Actualizaremos la cuenta al recuperar la conexión.',
        Icons.cloud_off_rounded,
      );
    }
    return const SyncPresentation(
      'Todo guardado',
      'No hay cambios pendientes de enviar desde este dispositivo.',
      Icons.cloud_done_rounded,
    );
  }
}

Future<void> showSyncActivitySheet({
  required BuildContext context,
  required NotesCubit cubit,
  required ListProtectionController protection,
}) => showLiquidBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  builder: (_) => _SyncActivitySheet(cubit: cubit, protection: protection),
);

class _SyncActivitySheet extends StatefulWidget {
  const _SyncActivitySheet({required this.cubit, required this.protection});
  final NotesCubit cubit;
  final ListProtectionController protection;
  @override
  State<_SyncActivitySheet> createState() => _SyncActivitySheetState();
}

class _SyncActivitySheetState extends State<_SyncActivitySheet> {
  List<PendingNoteChange> _changes = [];
  bool _loading = true;
  bool _failed = false;
  bool _retrying = false;
  int _generation = 0;
  late final StreamSubscription<NotesState> _subscription;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _subscription = widget.cubit.stream.listen((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final changes = await widget.cubit.fetchPendingChanges();
      if (mounted && generation == _generation) {
        setState(() {
          _changes = changes;
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _retry([String? id]) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      if (id == null) {
        await widget.cubit.retryOfflineSync();
      } else {
        await widget.cubit.retryPendingChange(id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El cambio sigue guardado. No pudimos enviarlo todavía.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
        await _load();
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.protection,
    builder: (context, _) => BlocBuilder<NotesCubit, NotesState>(
      bloc: widget.cubit,
      builder: (context, state) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final status = SyncPresentation.fromState(state);
        final hasChanges = state.pendingSyncCount + state.syncConflictCount > 0;
        return SizedBox(
          height:
              MediaQuery.sizeOf(context).height *
              (MediaQuery.textScalerOf(context).scale(1) > 1.2 ? .9 : .76),
          child: Stack(
            children: [
              const Positioned.fill(child: AmbientPageBackground()),
              Padding(
                key: const ValueKey('sync-activity-sheet'),
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
                        Icon(Icons.cloud_sync_rounded, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tus cambios',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar sincronización',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: .16),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(status.icon, color: colors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  status.detail,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasChanges)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            if (state.pendingSyncCount > 0)
                              Text(
                                '${state.pendingSyncCount} por enviar',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (state.pendingSyncCount > 0 &&
                                state.syncConflictCount > 0)
                              const SizedBox(width: 16),
                            if (state.syncConflictCount > 0)
                              Text(
                                '${state.syncConflictCount} por revisar',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    if (state.syncConflictCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: FilledButton.tonalIcon(
                          key: const ValueKey('sync-activity-review'),
                          onPressed: () async {
                            await showSyncConflictsSheet(
                              context: context,
                              cubit: widget.cubit,
                              protection: widget.protection,
                            );
                            if (mounted) await _load();
                          },
                          icon: const Icon(Icons.compare_arrows_rounded),
                          label: const Text('Comparar versiones'),
                        ),
                      ),
                    if (state.pendingSyncCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          key: const ValueKey('sync-activity-retry'),
                          onPressed: _retrying || state.isSyncingOfflineChanges
                              ? null
                              : () => _retry(),
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: Text(
                            _retrying || state.isSyncingOfflineChanges
                                ? 'Enviando…'
                                : 'Intentar ahora',
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : !state.syncStateKnown
                          ? Center(
                              child: TextButton(
                                onPressed: _retrying ? null : () => _retry(),
                                child: const Text(
                                  'Comprobar cambios pendientes',
                                ),
                              ),
                            )
                          : _failed
                          ? Center(
                              child: TextButton(
                                onPressed: _load,
                                child: const Text(
                                  'No pudimos leer los cambios. Reintentar',
                                ),
                              ),
                            )
                          : _changes.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  hasChanges
                                      ? 'Tus cambios siguen guardados. Actualiza el panel para ver el detalle.'
                                      : 'Puedes seguir con tus notas con tranquilidad.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : ScrollEdgeFade(
                              child: ListView.separated(
                                padding: EdgeInsets.only(
                                  bottom:
                                      20 + MediaQuery.paddingOf(context).bottom,
                                ),
                                itemCount: _changes.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final change = _changes[index];
                                  final list = state.lists
                                      .where(
                                        (list) => list.id == change.boardId,
                                      )
                                      .firstOrNull;
                                  final locked = !widget.protection.canAccess(
                                    change.boardId,
                                  );
                                  final accessible =
                                      !locked &&
                                      list != null &&
                                      !list.isEncryptionKeyPending;
                                  return Container(
                                    key: ValueKey(
                                      'pending-change-${change.id}',
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: colors.surface.withValues(
                                        alpha: .4,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: colors.outlineVariant.withValues(
                                          alpha: .25,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              accessible
                                                  ? _kindIcon(change.kind)
                                                  : Icons.lock_rounded,
                                              size: 20,
                                              color: colors.primary,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                accessible
                                                    ? change.note?.title ??
                                                          'Cambio en una lista'
                                                    : locked
                                                    ? 'Lista protegida'
                                                    : 'Lista no disponible',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            Icon(
                                              change.needsReview
                                                  ? Icons.info_outline_rounded
                                                  : Icons.schedule_rounded,
                                              size: 18,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          accessible
                                              ? '${_kindLabel(change.kind)} · ${list.name}'
                                              : locked
                                              ? 'Desbloquea la lista para ver el detalle.'
                                              : 'El cambio sigue guardado hasta recuperar el acceso.',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${change.needsReview ? 'Necesita revisión' : 'Guardado aquí'} · ${DateFormat('d MMM, HH:mm', 'es').format(change.createdAt.toLocal())}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                        if (change.needsReview &&
                                            !change.canCompare &&
                                            accessible)
                                          TextButton(
                                            onPressed: _retrying
                                                ? null
                                                : () => _retry(change.id),
                                            child: const Text(
                                              'Volver a intentar',
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

IconData _kindIcon(OfflineMutationKind kind) => switch (kind) {
  OfflineMutationKind.create => Icons.note_add_rounded,
  OfflineMutationKind.delete => Icons.delete_outline_rounded,
  OfflineMutationKind.reaction => Icons.emoji_emotions_outlined,
  OfflineMutationKind.reorder => Icons.swap_vert_rounded,
  OfflineMutationKind.update => Icons.edit_note_rounded,
};
String _kindLabel(OfflineMutationKind kind) => switch (kind) {
  OfflineMutationKind.create => 'Nota nueva',
  OfflineMutationKind.update => 'Edición',
  OfflineMutationKind.delete => 'Eliminación',
  OfflineMutationKind.reaction => 'Reacción',
  OfflineMutationKind.reorder => 'Cambio de orden',
};
