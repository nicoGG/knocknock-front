import 'package:flutter/material.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:uuid/uuid.dart';

class NoteChecklistEditor extends StatefulWidget {
  const NoteChecklistEditor({
    required this.items,
    required this.onChanged,
    super.key,
  });

  final List<NoteChecklistItem> items;
  final ValueChanged<List<NoteChecklistItem>> onChanged;

  @override
  State<NoteChecklistEditor> createState() => _NoteChecklistEditorState();
}

class _NoteChecklistEditorState extends State<NoteChecklistEditor> {
  final _newItemFocusNode = FocusNode();
  String? _focusedNewItemId;

  List<NoteChecklistItem> get items => widget.items;
  ValueChanged<List<NoteChecklistItem>> get onChanged => widget.onChanged;

  @override
  void dispose() {
    _newItemFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Subtareas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('add-checklist-item'),
              onPressed: _addItem,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar'),
            ),
          ],
        ),
        Text(
          'Arrastra desde los puntos para ordenar. Usa las flechas para crear subtareas.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          InkWell(
            key: const ValueKey('empty-checklist-add'),
            onTap: _addItem,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_box_outlined),
                  SizedBox(width: 10),
                  Expanded(child: Text('Crear la primera subtarea')),
                ],
              ),
            ),
          )
        else
          ReorderableListView.builder(
            key: const ValueKey('checklist-editor'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) => _ChecklistDragProxy(
              key: const ValueKey('checklist-editor-drag-proxy'),
              animation: animation,
              backgroundColor: colorScheme.surfaceContainerHigh,
              foregroundColor: colorScheme.onSurface,
              child: child,
            ),
            itemCount: items.length,
            onReorderStart: (_) {
              // Selection handles cannot follow a field while its row moves
              // into the reorder overlay.
              FocusManager.instance.primaryFocus?.unfocus();
            },
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final item = items[index];
              return _ChecklistEditorRow(
                key: ValueKey('checklist-editor-${item.id}'),
                item: item,
                index: index,
                canIndent: index > 0 && item.indent < 2,
                canOutdent: item.indent > 0,
                onChanged: (updated) => _replace(index, updated),
                onIndent: () =>
                    _replace(index, item.copyWith(indent: item.indent + 1)),
                onOutdent: () =>
                    _replace(index, item.copyWith(indent: item.indent - 1)),
                onDelete: () => _remove(index),
                focusNode: item.id == _focusedNewItemId
                    ? _newItemFocusNode
                    : null,
                onSubmitted: (text) => _addItemAfter(index, text),
              );
            },
          ),
      ],
    );
  }

  void _addItem() {
    final item = NoteChecklistItem(id: const Uuid().v4(), text: '');
    _focusAfterBuild(item.id);
    onChanged([...items, item]);
  }

  void _addItemAfter(int index, String text) {
    if (text.trim().isEmpty) return;
    final item = NoteChecklistItem(id: const Uuid().v4(), text: '');
    final updated = [...items]..insert(index + 1, item);
    _focusAfterBuild(item.id);
    onChanged(updated);
  }

  void _focusAfterBuild(String itemId) {
    _focusedNewItemId = itemId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _newItemFocusNode.requestFocus();
    });
  }

  void _replace(int index, NoteChecklistItem item) {
    final updated = [...items]..[index] = item;
    onChanged(updated);
  }

  void _remove(int index) {
    final updated = [...items]..removeAt(index);
    onChanged(updated);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final updated = [...items];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    onChanged(updated);
  }
}

class _ChecklistEditorRow extends StatelessWidget {
  const _ChecklistEditorRow({
    required this.item,
    required this.index,
    required this.canIndent,
    required this.canOutdent,
    required this.onChanged,
    required this.onIndent,
    required this.onOutdent,
    required this.onDelete,
    required this.onSubmitted,
    this.focusNode,
    super.key,
  });

  final NoteChecklistItem item;
  final int index;
  final bool canIndent;
  final bool canOutdent;
  final ValueChanged<NoteChecklistItem> onChanged;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;
  final VoidCallback onDelete;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: item.indent * 24, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: 'Arrastrar subtarea',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 17,
                  ),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.48),
                  ),
                ),
              ),
            ),
            Checkbox(
              value: item.isCompleted,
              onChanged: (value) =>
                  onChanged(item.copyWith(isCompleted: value ?? false)),
            ),
            Expanded(
              child: TextFormField(
                key: ValueKey('checklist-text-${item.id}'),
                initialValue: item.text,
                focusNode: focusNode,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [InitialUppercaseTextFormatter()],
                textInputAction: TextInputAction.next,
                autofocus: item.text.isEmpty,
                decoration: const InputDecoration(
                  hintText: 'Escribe una subtarea',
                  counterText: '',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (text) => onChanged(
                  item.copyWith(text: capitalizeInitialLetter(text)),
                ),
                onFieldSubmitted: (text) =>
                    onSubmitted(capitalizeInitialLetter(text)),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opciones de subtarea',
              constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
              onSelected: (value) {
                switch (value) {
                  case 'indent':
                    onIndent();
                  case 'outdent':
                    onOutdent();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'indent',
                  enabled: canIndent,
                  child: const _ChecklistMenuItem(
                    icon: Icons.subdirectory_arrow_right_rounded,
                    label: 'Convertir en subtarea',
                  ),
                ),
                PopupMenuItem(
                  value: 'outdent',
                  enabled: canOutdent,
                  child: const _ChecklistMenuItem(
                    icon: Icons.subdirectory_arrow_left_rounded,
                    label: 'Subir un nivel',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: _ChecklistMenuItem(
                    icon: Icons.delete_outline_rounded,
                    label: 'Eliminar',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistMenuItem extends StatelessWidget {
  const _ChecklistMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class NoteChecklistPreview extends StatefulWidget {
  const NoteChecklistPreview({
    required this.items,
    required this.foregroundColor,
    required this.onToggle,
    this.maxItems = 4,
    this.showOpenHint = false,
    this.completedExpanded,
    this.onCompletedExpansionChanged,
    super.key,
  });

  final List<NoteChecklistItem> items;
  final Color foregroundColor;
  final ValueChanged<NoteChecklistItem> onToggle;
  final int maxItems;
  final bool showOpenHint;
  final bool? completedExpanded;
  final ValueChanged<bool>? onCompletedExpansionChanged;

  @override
  State<NoteChecklistPreview> createState() => _NoteChecklistPreviewState();
}

class _NoteChecklistPreviewState extends State<NoteChecklistPreview> {
  bool _locallyCompletedExpanded = true;

  bool get _completedExpanded =>
      widget.completedExpanded ?? _locallyCompletedExpanded;

  @override
  void didUpdateWidget(covariant NoteChecklistPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.completedExpanded != null) return;
    final previousCompletedCount = oldWidget.items
        .where((item) => item.isCompleted)
        .length;
    final completedCount = widget.items
        .where((item) => item.isCompleted)
        .length;
    if (completedCount == 0 || previousCompletedCount == 0) {
      _locallyCompletedExpanded = true;
    }
  }

  void _toggleCompletedSection() {
    final expanded = !_completedExpanded;
    if (widget.onCompletedExpansionChanged case final onChanged?) {
      onChanged(expanded);
      return;
    }
    setState(() => _locallyCompletedExpanded = expanded);
  }

  @override
  Widget build(BuildContext context) {
    final pendingItems = widget.items
        .where((item) => !item.isCompleted)
        .toList();
    final completedItems = widget.items
        .where((item) => item.isCompleted)
        .toList();
    final completedExpanded = _completedExpanded;
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalVisibleCandidates =
            pendingItems.length +
            (completedExpanded ? completedItems.length : 0);
        var visibleCapacity = totalVisibleCandidates < widget.maxItems
            ? totalVisibleCandidates
            : widget.maxItems;
        if (constraints.maxHeight.isFinite) {
          final completedHeaderHeight = completedItems.isEmpty ? 0.0 : 44.0;
          final availableHeight = constraints.maxHeight - completedHeaderHeight;
          final rowCapacity = availableHeight <= 0
              ? 0
              : (availableHeight / 30).floor();
          if (visibleCapacity > rowCapacity) visibleCapacity = rowCapacity;
          if (totalVisibleCandidates > visibleCapacity) {
            final capacityWithSummary = availableHeight <= 20
                ? 0
                : ((availableHeight - 20) / 30).floor();
            if (visibleCapacity > capacityWithSummary) {
              visibleCapacity = capacityWithSummary;
            }
          }
        }

        var pendingVisibleCount = pendingItems.length < visibleCapacity
            ? pendingItems.length
            : visibleCapacity;
        var completedVisibleCount = 0;
        if (completedExpanded &&
            completedItems.isNotEmpty &&
            visibleCapacity > 0) {
          final remainingCapacity = visibleCapacity - pendingVisibleCount;
          if (remainingCapacity > 0) {
            completedVisibleCount = completedItems.length < remainingCapacity
                ? completedItems.length
                : remainingCapacity;
          } else if (pendingVisibleCount > 0) {
            pendingVisibleCount -= 1;
            completedVisibleCount = 1;
          }
        }

        final visiblePending = pendingItems.take(pendingVisibleCount).toList();
        final visibleCompleted = completedItems
            .take(completedVisibleCount)
            .toList();
        final hiddenPendingCount = pendingItems.length - visiblePending.length;
        final completedLabel = completedItems.length == 1
            ? '1 elemento completado'
            : '${completedItems.length} elementos completados';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in visiblePending)
              _ChecklistPreviewRow(
                item: item,
                foregroundColor: widget.foregroundColor,
                onToggle: widget.onToggle,
              ),
            if (hiddenPendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 35, top: 2),
                child: Text(
                  widget.showOpenHint
                      ? '$hiddenPendingCount más'
                      : '+$hiddenPendingCount más',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: widget.foregroundColor.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (completedItems.isNotEmpty) ...[
              Container(
                height: 1,
                margin: const EdgeInsets.only(top: 7, bottom: 2),
                color: widget.foregroundColor.withValues(alpha: 0.28),
              ),
              Semantics(
                button: true,
                label: completedLabel,
                hint: completedExpanded
                    ? 'Contraer elementos completados'
                    : 'Expandir elementos completados',
                child: InkWell(
                  key: const ValueKey('preview-completed-section-toggle'),
                  onTap: _toggleCompletedSection,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: animationDuration,
                          child: Icon(
                            completedExpanded
                                ? Icons.expand_more_rounded
                                : Icons.chevron_right_rounded,
                            key: ValueKey(completedExpanded),
                            size: 24,
                            color: widget.foregroundColor.withValues(
                              alpha: 0.76,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            completedLabel,
                            key: const ValueKey(
                              'preview-completed-section-label',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: widget.foregroundColor.withValues(
                                    alpha: 0.76,
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: animationDuration,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: completedExpanded
                      ? Column(
                          key: const ValueKey(
                            'preview-completed-section-items',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final item in visibleCompleted)
                              _ChecklistPreviewRow(
                                item: item,
                                foregroundColor: widget.foregroundColor,
                                onToggle: widget.onToggle,
                              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ChecklistPreviewRow extends StatelessWidget {
  const _ChecklistPreviewRow({
    required this.item,
    required this.foregroundColor,
    required this.onToggle,
  });

  final NoteChecklistItem item;
  final Color foregroundColor;
  final ValueChanged<NoteChecklistItem> onToggle;

  @override
  Widget build(BuildContext context) {
    final itemColor = item.isCompleted
        ? foregroundColor.withValues(alpha: 0.72)
        : foregroundColor;
    return Padding(
      padding: EdgeInsets.only(left: item.indent * 18, bottom: 2),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 27,
            child: Checkbox(
              key: ValueKey('preview-check-${item.id}'),
              value: item.isCompleted,
              onChanged: (_) => onToggle(item),
              activeColor: itemColor,
              checkColor: Colors.black87,
              side: BorderSide(color: itemColor, width: 1.5),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              item.text.isEmpty ? 'Subtarea sin nombre' : item.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: itemColor,
                decoration: item.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NoteChecklistDetail extends StatefulWidget {
  const NoteChecklistDetail({
    required this.items,
    required this.isSaving,
    required this.onChanged,
    required this.onEdit,
    this.backgroundColor,
    this.foregroundColor,
    this.dragProxyColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    super.key,
  });

  final List<NoteChecklistItem> items;
  final bool isSaving;
  final ValueChanged<List<NoteChecklistItem>> onChanged;
  final VoidCallback onEdit;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? dragProxyColor;
  final BorderRadius borderRadius;

  @override
  State<NoteChecklistDetail> createState() => _NoteChecklistDetailState();
}

class _NoteChecklistDetailState extends State<NoteChecklistDetail> {
  final _newItemController = TextEditingController();
  final _newItemFocusNode = FocusNode();

  @override
  void dispose() {
    _newItemController.dispose();
    _newItemFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveForeground = widget.foregroundColor ?? colorScheme.onSurface;
    final checkboxCheckColor =
        ThemeData.estimateBrightnessForColor(effectiveForeground) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Material(
      key: const ValueKey('note-checklist-detail'),
      color: widget.backgroundColor ?? colorScheme.surfaceContainerLow,
      borderRadius: widget.borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.checklist_rounded,
                    size: 20,
                    color: effectiveForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Subtareas',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: effectiveForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => _ChecklistDragProxy(
                key: const ValueKey('detail-checklist-drag-proxy'),
                animation: animation,
                backgroundColor:
                    widget.dragProxyColor ?? colorScheme.surfaceContainerHigh,
                foregroundColor: effectiveForeground,
                child: child,
              ),
              itemCount: widget.items.length,
              onReorderItem: widget.isSaving ? (_, _) {} : _reorder,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return Padding(
                  key: ValueKey('detail-checklist-${item.id}'),
                  padding: EdgeInsets.only(
                    left: item.indent * 24,
                    right: 4,
                    bottom: 2,
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        enabled: !widget.isSaving,
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: effectiveForeground.withValues(alpha: 0.56),
                          ),
                        ),
                      ),
                      Checkbox(
                        key: ValueKey('detail-check-${item.id}'),
                        value: item.isCompleted,
                        activeColor: effectiveForeground,
                        checkColor: checkboxCheckColor,
                        side: BorderSide(
                          color: effectiveForeground,
                          width: 1.5,
                        ),
                        onChanged: widget.isSaving
                            ? null
                            : (value) => _replace(
                                index,
                                item.copyWith(isCompleted: value ?? false),
                              ),
                      ),
                      Expanded(
                        child: Text(
                          item.text,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: effectiveForeground,
                                decoration: item.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey(
                          'delete-detail-checklist-item-${item.id}',
                        ),
                        tooltip: 'Eliminar subtarea',
                        onPressed: widget.isSaving
                            ? null
                            : () => _confirmRemove(item),
                        color: effectiveForeground.withValues(alpha: 0.74),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(40, 40),
                          maximumSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
              child: TextField(
                key: const ValueKey('detail-new-checklist-item'),
                controller: _newItemController,
                focusNode: _newItemFocusNode,
                enabled: !widget.isSaving,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [InitialUppercaseTextFormatter()],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'Agregar subtarea',
                  hintStyle: TextStyle(
                    color: effectiveForeground.withValues(alpha: 0.62),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: effectiveForeground.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: effectiveForeground.withValues(alpha: 0.14),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: effectiveForeground.withValues(alpha: 0.14),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: effectiveForeground.withValues(alpha: 0.58),
                      width: 1.5,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.add_rounded,
                    color: effectiveForeground,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 88,
                    minHeight: 40,
                  ),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _newItemController,
                    builder: (context, value, child) {
                      final hasText = value.text.trim().isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const ValueKey(
                                'cancel-detail-new-checklist-item',
                              ),
                              tooltip: 'Cancelar subtarea',
                              onPressed: widget.isSaving
                                  ? null
                                  : _cancelNewItem,
                              color: effectiveForeground,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(36, 36),
                                maximumSize: const Size(36, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const ValueKey(
                                'confirm-detail-new-checklist-item',
                              ),
                              tooltip: 'Agregar subtarea',
                              onPressed: widget.isSaving || !hasText
                                  ? null
                                  : _submitNewItem,
                              color: checkboxCheckColor,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(36, 36),
                                maximumSize: const Size(36, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: effectiveForeground,
                                disabledBackgroundColor: effectiveForeground
                                    .withValues(alpha: 0.14),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 20),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                cursorColor: effectiveForeground,
                style: TextStyle(
                  color: effectiveForeground,
                  fontWeight: FontWeight.w600,
                ),
                onSubmitted: (_) => _submitNewItem(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _replace(int index, NoteChecklistItem item) {
    final updated = [...widget.items]..[index] = item;
    widget.onChanged(updated);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final updated = [...widget.items];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    widget.onChanged(updated);
  }

  Future<void> _confirmRemove(NoteChecklistItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: ValueKey('delete-detail-checklist-dialog-${item.id}'),
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('¿Eliminar subtarea?'),
        content: Text(
          'Se eliminará “${item.text}”. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-delete-detail-checklist-item'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-detail-checklist-item'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || widget.isSaving) return;
    final updated = widget.items
        .where((candidate) => candidate.id != item.id)
        .toList();
    if (updated.length == widget.items.length) return;
    widget.onChanged(updated);
  }

  void _submitNewItem() {
    final text = capitalizeInitialLetter(_newItemController.text.trim());
    if (text.isEmpty || widget.isSaving) return;
    widget.onChanged([
      ...widget.items,
      NoteChecklistItem(id: const Uuid().v4(), text: text),
    ]);
    _newItemController.clear();
    _newItemFocusNode.requestFocus();
  }

  void _cancelNewItem() {
    _newItemController.clear();
    _newItemFocusNode.unfocus();
  }
}

class _ChecklistDragProxy extends StatelessWidget {
  const _ChecklistDragProxy({
    required this.animation,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final lift = disableAnimations
            ? 1.0
            : Curves.easeOutCubic.transform(
                animation.value.clamp(0.0, 1.0).toDouble(),
              );
        final proxyColor = Color.alphaBlend(
          foregroundColor.withValues(alpha: 0.06),
          backgroundColor,
        );
        return Transform.scale(
          scale: 1 + (0.018 * lift),
          child: Material(
            key: const ValueKey('checklist-drag-proxy-surface'),
            color: proxyColor,
            surfaceTintColor: Colors.transparent,
            elevation: 12 * lift,
            shadowColor: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: foregroundColor.withValues(alpha: 0.2),
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
