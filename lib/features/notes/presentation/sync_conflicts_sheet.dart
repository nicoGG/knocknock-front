import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';

Future<void> showSyncConflictsSheet({
  required BuildContext context,
  required NotesCubit cubit,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _SyncConflictsSheet(cubit: cubit),
);

class _SyncConflictsSheet extends StatefulWidget {
  const _SyncConflictsSheet({required this.cubit});

  final NotesCubit cubit;

  @override
  State<_SyncConflictsSheet> createState() => _SyncConflictsSheetState();
}

class _SyncConflictsSheetState extends State<_SyncConflictsSheet> {
  late Future<List<NoteSyncConflict>> _conflicts = widget.cubit
      .fetchSyncConflicts();
  String? _resolvingId;

  Future<void> _resolve(
    NoteSyncConflict conflict,
    NoteConflictResolution resolution,
  ) async {
    setState(() => _resolvingId = conflict.mutationId);
    try {
      await widget.cubit.resolveSyncConflict(conflict.mutationId, resolution);
      if (!mounted) return;
      setState(() {
        _resolvingId = null;
        _conflicts = widget.cubit.fetchSyncConflicts();
      });
    } on Object {
      if (!mounted) return;
      setState(() => _resolvingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos aplicar esa decisión. El cambio sigue guardado.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Revisar cambios',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'Otra persona o dispositivo modificó estas notas mientras tenías cambios locales. Elige qué versión conservar.',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<NoteSyncConflict>>(
              future: _conflicts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ConflictLoadFailure(
                    onRetry: () => setState(
                      () => _conflicts = widget.cubit.fetchSyncConflicts(),
                    ),
                  );
                }
                final conflicts = snapshot.data ?? const [];
                if (conflicts.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No quedan cambios comparables. Si aparece un cambio pendiente, intenta sincronizar nuevamente.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  key: const ValueKey('sync-conflicts-list'),
                  padding: const EdgeInsets.all(16),
                  itemCount: conflicts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final conflict = conflicts[index];
                    final resolving = _resolvingId == conflict.mutationId;
                    return _ConflictCard(
                      conflict: conflict,
                      isResolving: resolving,
                      onKeepLocal: () =>
                          _resolve(conflict, NoteConflictResolution.keepLocal),
                      onKeepRemote: () =>
                          _resolve(conflict, NoteConflictResolution.keepRemote),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConflictLoadFailure extends StatelessWidget {
  const _ConflictLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sync_problem_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          const Text(
            'No pudimos cargar las versiones. Tus cambios siguen guardados en este dispositivo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.isResolving,
    required this.onKeepLocal,
    required this.onKeepRemote,
  });

  final NoteSyncConflict conflict;
  final bool isResolving;
  final VoidCallback onKeepLocal;
  final VoidCallback onKeepRemote;

  @override
  Widget build(BuildContext context) {
    final deleteConflict = conflict.kind == OfflineMutationKind.delete;
    return Card(
      key: ValueKey('sync-conflict-${conflict.mutationId}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflict.remoteNote.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _VersionBlock(
              label: deleteConflict ? 'Tu acción' : 'Tu versión',
              text: deleteConflict
                  ? 'Eliminar esta nota'
                  : _summary(conflict.localNote.content),
            ),
            const SizedBox(height: 8),
            _VersionBlock(
              label: 'Versión sincronizada',
              text: _summary(conflict.remoteNote.content),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isResolving ? null : onKeepRemote,
                    child: const Text('Usar sincronizada'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: isResolving ? null : onKeepLocal,
                    child: Text(
                      deleteConflict
                          ? 'Eliminar igualmente'
                          : 'Conservar la mía',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _summary(String content) =>
      content.trim().isEmpty ? 'Sin contenido adicional' : content.trim();
}

class _VersionBlock extends StatelessWidget {
  const _VersionBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(text, maxLines: 4, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
