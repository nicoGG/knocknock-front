import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:uuid/uuid.dart';

class NoteChecklistEditor extends StatelessWidget {
  const NoteChecklistEditor({
    required this.items,
    required this.onChanged,
    super.key,
  });

  final List<NoteChecklistItem> items;
  final ValueChanged<List<NoteChecklistItem>> onChanged;

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
              );
            },
          ),
      ],
    );
  }

  void _addItem() {
    onChanged([...items, NoteChecklistItem(id: const Uuid().v4(), text: '')]);
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
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Escribe una subtarea',
                  counterText: '',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (text) => onChanged(item.copyWith(text: text)),
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

class NoteChecklistPreview extends StatelessWidget {
  const NoteChecklistPreview({
    required this.items,
    required this.foregroundColor,
    required this.onToggle,
    this.maxItems = 4,
    super.key,
  });

  final List<NoteChecklistItem> items;
  final Color foregroundColor;
  final ValueChanged<NoteChecklistItem> onToggle;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var visibleCount = items.length.clamp(0, maxItems);
        if (constraints.maxHeight.isFinite) {
          final rowCapacity = (constraints.maxHeight / 30).floor();
          if (visibleCount > rowCapacity) visibleCount = rowCapacity;
          if (items.length > visibleCount) {
            final capacityWithSummary = ((constraints.maxHeight - 20) / 30)
                .floor();
            visibleCount = capacityWithSummary < 1
                ? 1
                : visibleCount.clamp(1, capacityWithSummary);
          }
        }
        final visible = items.take(visibleCount).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in visible)
              Padding(
                padding: EdgeInsets.only(left: item.indent * 18, bottom: 2),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 27,
                      child: Checkbox(
                        key: ValueKey('preview-check-${item.id}'),
                        value: item.isCompleted,
                        onChanged: (_) => onToggle(item),
                        activeColor: foregroundColor,
                        checkColor: Colors.black87,
                        side: BorderSide(color: foregroundColor, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item.text.isEmpty ? 'Subtarea sin nombre' : item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                          decoration: item.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (items.length > visible.length)
              Padding(
                padding: const EdgeInsets.only(left: 35, top: 2),
                child: Text(
                  '+${items.length - visible.length} más',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foregroundColor.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class NoteChecklistDetail extends StatelessWidget {
  const NoteChecklistDetail({
    required this.items,
    required this.isSaving,
    required this.onChanged,
    required this.onEdit,
    super.key,
  });

  final List<NoteChecklistItem> items;
  final bool isSaving;
  final ValueChanged<List<NoteChecklistItem>> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('note-checklist-detail'),
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
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
                  const Icon(Icons.checklist_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Subtareas',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: isSaving ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: isSaving ? (_, _) {} : _reorder,
              itemBuilder: (context, index) {
                final item = items[index];
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
                        enabled: !isSaving,
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.46,
                            ),
                          ),
                        ),
                      ),
                      Checkbox(
                        key: ValueKey('detail-check-${item.id}'),
                        value: item.isCompleted,
                        onChanged: isSaving
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
                                decoration: item.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _replace(int index, NoteChecklistItem item) {
    final updated = [...items]..[index] = item;
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
