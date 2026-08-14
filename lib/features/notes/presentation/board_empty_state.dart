part of 'board_page.dart';

/// Empty, loading, and template actions for the board.

class _NoteTemplate {
  const _NoteTemplate({
    required this.label,
    required this.description,
    required this.icon,
    required this.title,
    this.content = '',
    this.category = NoteCategory.general,
    this.checklist = const [],
  });

  final String label;
  final String description;
  final IconData icon;
  final String title;
  final String content;
  final NoteCategory category;
  final List<String> checklist;
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.templateActions = const [],
    this.onTemplateSelected,
    this.signInHint,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<_NoteTemplate> templateActions;
  final ValueChanged<_NoteTemplate>? onTemplateSelected;
  final String? signInHint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 58,
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 7),
              Text(detail, textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (templateActions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Empieza con una plantilla',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface.withValues(alpha: 0.84),
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columnCount = constraints.maxWidth >= 440 ? 3 : 2;
                      final cardWidth =
                          (constraints.maxWidth - ((columnCount - 1) * 10)) /
                          columnCount;
                      return Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final template in templateActions)
                            SizedBox(
                              width: cardWidth,
                              child: _TemplateQuickAction(
                                template: template,
                                onPressed: onTemplateSelected == null
                                    ? null
                                    : () => onTemplateSelected!(template),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              if (signInHint != null) ...[
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    signInHint!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateQuickAction extends StatelessWidget {
  const _TemplateQuickAction({required this.template, required this.onPressed});

  final _NoteTemplate template;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = NoteCategoryStyle.baseColor(template.category);
    final foreground = NoteCategoryStyle.foregroundColor(template.category);
    return Semantics(
      button: true,
      label: 'Crear con plantilla: ${template.label}',
      child: Material(
        color: Color.lerp(colorScheme.surfaceContainerHigh, accent, 0.22),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('template-action-${template.label}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(template.icon, size: 21, color: foreground),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        template.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
