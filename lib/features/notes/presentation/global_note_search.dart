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
    return FractionallySizedBox(
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
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
            const SizedBox(height: 12),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error case final error?) {
      return _SearchMessage(
        icon: Icons.cloud_off_outlined,
        message: error,
        actionLabel: 'Reintentar',
        onAction: () => _search(_controller.text.trim()),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return const _SearchMessage(
        icon: Icons.manage_search_rounded,
        message:
            'Encuentra información en todas tus listas sin enviarla a un buscador externo.',
      );
    }
    if (_results.isEmpty) {
      return const _SearchMessage(
        icon: Icons.search_off_rounded,
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
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
