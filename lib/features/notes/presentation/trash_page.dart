import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({required this.cubit, super.key});

  final NotesCubit cubit;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  late Future<List<Note>> _trashFuture = widget.cubit.fetchTrash();
  final Set<String> _restoringIds = {};

  void _reload() {
    setState(() => _trashFuture = widget.cubit.fetchTrash());
  }

  Future<void> _restore(Note note) async {
    if (_restoringIds.contains(note.id)) return;
    setState(() => _restoringIds.add(note.id));
    try {
      final restored = await widget.cubit.restoreNoteFromTrash(note);
      if (!mounted) return;
      setState(() {
        _restoringIds.remove(note.id);
        _trashFuture = widget.cubit.fetchTrash();
      });
      final listName = _listName(restored.boardId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nota restaurada en “$listName”.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _restoringIds.remove(note.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notesErrorMessage(error))));
    }
  }

  String _listName(String boardId) {
    for (final list in widget.cubit.state.lists) {
      if (list.id == boardId) return list.name;
    }
    return 'su lista original';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Papelera')),
      body: FutureBuilder<List<Note>>(
        future: _trashFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _TrashLoadingState();
          }
          if (snapshot.hasError) {
            return _TrashMessage(
              icon: Icons.cloud_off_outlined,
              title: 'No pudimos abrir la papelera',
              detail: notesErrorMessage(snapshot.error!),
              actionLabel: 'Reintentar',
              onAction: _reload,
            );
          }
          final notes = snapshot.data ?? const <Note>[];
          if (notes.isEmpty) {
            return const _TrashMessage(
              icon: Icons.delete_sweep_outlined,
              title: 'La papelera está vacía',
              detail: 'Las notas eliminadas aparecerán aquí durante 7 días.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Container(
                  key: const ValueKey('trash-retention-notice'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.72,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Las notas se eliminan definitivamente 7 días después de enviarlas a la papelera.',
                          style: TextStyle(
                            color: colorScheme.onSecondaryContainer,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final note in notes) ...[
                  _TrashNoteCard(
                    note: note,
                    listName: _listName(note.boardId),
                    isRestoring: _restoringIds.contains(note.id),
                    onRestore: () => _restore(note),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrashLoadingState extends StatefulWidget {
  const _TrashLoadingState();

  @override
  State<_TrashLoadingState> createState() => _TrashLoadingStateState();
}

class _TrashLoadingStateState extends State<_TrashLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.42;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando papelera',
    liveRegion: true,
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth > 720
                ? (constraints.maxWidth - 680) / 2
                : 16.0;
            return ListView(
              key: const ValueKey('trash-loading-state'),
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                28,
              ),
              children: [
                _TrashLoadingHeading(progress: _controller.value),
                const SizedBox(height: 20),
                _TrashLoadingNotice(progress: _controller.value),
                const SizedBox(height: 14),
                for (var index = 0; index < 3; index++) ...[
                  _TrashLoadingCard(index: index, progress: _controller.value),
                  if (index < 2) const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _TrashLoadingHeading extends StatelessWidget {
  const _TrashLoadingHeading({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulse = 1 - (((progress * 2) - 1).abs());
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: colorScheme.onSecondaryContainer,
                size: 28,
              ),
              Transform.translate(
                offset: Offset(7, -8 - (pulse * 2)),
                child: Transform.rotate(
                  angle: -0.16,
                  child: Container(
                    width: 13,
                    height: 15,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: colorScheme.secondaryContainer,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revisando la papelera…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                'Buscando notas que aún puedes recuperar',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrashLoadingNotice extends StatelessWidget {
  const _TrashLoadingNotice({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            color: colorScheme.onSecondaryContainer.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TrashLoadingBlock(
                  progress: progress,
                  widthFactor: 0.94,
                  height: 9,
                ),
                const SizedBox(height: 8),
                _TrashLoadingBlock(
                  progress: progress,
                  widthFactor: 0.68,
                  height: 9,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashLoadingCard extends StatelessWidget {
  const _TrashLoadingCard({required this.index, required this.progress});

  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final phase = (progress + (index * 0.12)) % 1;
    final shimmerStart = -2.2 + (phase * 4.4);
    return Container(
      key: ValueKey('trash-loading-card-$index'),
      height: 104,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment(shimmerStart, -1),
          end: Alignment(shimmerStart + 1.15, 1),
          colors: [
            colorScheme.surfaceContainerLow,
            colorScheme.surfaceContainerHighest,
            colorScheme.surfaceContainerLow,
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TrashLoadingBlock(
                  progress: phase,
                  widthFactor: index.isEven ? 0.78 : 0.64,
                  height: 14,
                ),
                const SizedBox(height: 10),
                _TrashLoadingBlock(
                  progress: phase,
                  widthFactor: index.isEven ? 0.48 : 0.58,
                  height: 8,
                ),
                const SizedBox(height: 8),
                _TrashLoadingBlock(
                  progress: phase,
                  widthFactor: 0.56,
                  height: 8,
                  accent: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 92,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Center(
              child: Icon(
                Icons.restore_rounded,
                size: 19,
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashLoadingBlock extends StatelessWidget {
  const _TrashLoadingBlock({
    required this.progress,
    required this.widthFactor,
    required this.height,
    this.accent = false,
  });

  final double progress;
  final double widthFactor;
  final double height;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulse =
        0.12 + ((1 - (((progress * 2) - 1).abs())) * (accent ? 0.1 : 0.08));
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: (accent ? colorScheme.error : colorScheme.onSurface)
              .withValues(alpha: pulse),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _TrashNoteCard extends StatelessWidget {
  const _TrashNoteCard({
    required this.note,
    required this.listName,
    required this.isRestoring,
    required this.onRestore,
  });

  final Note note;
  final String listName;
  final bool isRestoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('trash-note-${note.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title.trim().isEmpty ? 'Nota sin título' : note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    listName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _remainingLabel(note.deletedAt),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: ValueKey('restore-note-${note.id}'),
              onPressed: isRestoring ? null : onRestore,
              icon: isRestoring
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded, size: 19),
              label: const Text('Restaurar'),
            ),
          ],
        ),
      ),
    );
  }

  String _remainingLabel(DateTime? deletedAt) {
    if (deletedAt == null) return 'Se eliminará automáticamente';
    final remaining = deletedAt
        .add(const Duration(days: 7))
        .difference(DateTime.now());
    if (remaining <= Duration.zero) return 'Se eliminará pronto';
    final days = (remaining.inMinutes / Duration.minutesPerDay).ceil();
    return days == 1 ? 'Se elimina en 1 día' : 'Se elimina en $days días';
  }
}

class _TrashMessage extends StatelessWidget {
  const _TrashMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
