import 'package:nocknock/features/notes/presentation/note_assignee.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_link.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

Future<NoteSearchResult?> showGlobalNoteSearch({
  required BuildContext context,
  required NotesCubit cubit,
  bool Function(String listId)? canShowList,
}) => showModalBottomSheet<NoteSearchResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _GlobalNoteSearchSheet(
    cubit: cubit,
    canShowList: canShowList ?? (_) => true,
  ),
);

class _GlobalNoteSearchSheet extends StatefulWidget {
  const _GlobalNoteSearchSheet({
    required this.cubit,
    required this.canShowList,
  });

  final NotesCubit cubit;
  final bool Function(String listId) canShowList;

  @override
  State<_GlobalNoteSearchSheet> createState() => _GlobalNoteSearchSheetState();
}

class _GlobalNoteSearchSheetState extends State<_GlobalNoteSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<NoteSearchResult> _results = const [];
  bool _isLoading = false;
  String? _error;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _generation++;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _isLoading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 260), () => _search(query));
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await widget.cubit.searchNotes(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results
            .where((result) => widget.canShowList(result.list.id))
            .toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isLoading = false;
        _error =
            'No pudimos completar la búsqueda. Puedes intentarlo nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Material(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Buscar en NockNock',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  key: const ValueKey('global-note-search-field'),
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _scheduleSearch,
                  decoration: InputDecoration(
                    hintText: 'Título, contenido o subtarea',
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.65),
                      ),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _controller.clear();
                              _scheduleSearch('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.58,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Tus listas, una búsqueda privada',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    if (!_isLoading && _results.isNotEmpty)
                      Text(
                        '${_results.length} resultados',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colorScheme.primary),
                      ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const _SearchLoadingState();
    }
    if (_error case final error?) {
      return _SearchMessage(
        icon: Icons.cloud_off_outlined,
        title: 'No pudimos buscar',
        message: error,
        actionLabel: 'Reintentar',
        onAction: () => _search(_controller.text.trim()),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return const _SearchMessage(
        icon: Icons.manage_search_rounded,
        title: 'Todo lo que buscas, aquí',
        message:
            'Encuentra información en todas tus listas sin enviarla a un buscador externo.',
      );
    }
    if (_results.isEmpty) {
      return const _SearchMessage(
        icon: Icons.search_off_rounded,
        title: 'Probemos con otras palabras',
        message: 'No encontramos notas que coincidan con tu búsqueda.',
      );
    }
    return ListView.separated(
      key: const ValueKey('global-note-search-results'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final result = _results[index];
        final note = result.note;
        final detail = note.content.trim().isNotEmpty
            ? note.content.trim()
            : note.checklist
                  .map((item) => noteChecklistDisplayText(item.text))
                  .join(' · ');
        final subtitle = detail.isEmpty
            ? result.list.name
            : '${result.list.name} · $detail';
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final cardHeight = 88 + (48 * (textScale - 1).clamp(0.0, 1.0));
        return SizedBox(
          key: ValueKey('global-note-search-result-${note.id}'),
          height: cardHeight,
          child: PostItCard(
            note: note,
            layout: PostItCardLayout.compact,
            compactSubtitle: subtitle,
            assignee: resolveNoteAssignee(note, result.list.collaborators),
            assignees: resolveNoteAssignees(note, result.list.collaborators),
            compactReadOnly: true,
            compactOpenIndicator: true,
            showPin: false,
            enableHero: false,
            onToggle: () {},
            onPin: () {},
            onOpen: () => Navigator.pop(context, result),
            onChecklistToggle: (_) {},
          ),
        );
      },
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.message,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(alpha: 0.18),
                      colors.primary.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Icon(icon, size: 42, color: colors.primary),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchLoadingState extends StatefulWidget {
  const _SearchLoadingState();

  @override
  State<_SearchLoadingState> createState() => _SearchLoadingStateState();
}

class _SearchLoadingStateState extends State<_SearchLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _pulse = Tween<double>(
    begin: 0.45,
    end: 0.9,
  ).animate(CurvedAnimation(parent: _motion, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 1;
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: 'Buscando en tus notas',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          key: const ValueKey('global-note-search-loader'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const SizedBox(height: 12),
            Center(
              child: RepaintBoundary(
                child: SizedBox(
                  width: 150,
                  height: 126,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 126,
                        height: 126,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              colors.primary.withValues(alpha: 0.17),
                              colors.primary.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: -0.14,
                        child: Container(
                          width: 66,
                          height: 80,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colors.shadow.withValues(alpha: 0.1),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _line(colors, 5),
                              const SizedBox(height: 8),
                              _line(colors, 5),
                              const SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.6,
                                child: _line(colors, 5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _motion,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(19),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            size: 32,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        builder: (context, child) => Transform.translate(
                          offset: Offset(
                            30 + 8 * _motion.value,
                            20 - 10 * _motion.value,
                          ),
                          child: Transform.rotate(
                            angle: -0.08 + 0.16 * _motion.value,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Buscando en tus notas…',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Un momento, estamos encontrando coincidencias.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            for (var index = 0; index < 3; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: 0.7 - index * 0.1,
                              child: _line(colors, 12),
                            ),
                            const SizedBox(height: 10),
                            _line(colors, 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(ColorScheme colors, double height) => FadeTransition(
    opacity: _pulse,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}
