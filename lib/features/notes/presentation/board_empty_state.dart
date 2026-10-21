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
    this.onActionLongPress,
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
  final VoidCallback? onActionLongPress;
  final List<_NoteTemplate> templateActions;
  final ValueChanged<_NoteTemplate>? onTemplateSelected;
  final String? signInHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: const ValueKey('board-empty-state-entrance'),
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - progress)),
          child: child,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _EmptyBoardIllustration(icon: icon),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onAction,
                      onLongPress: onActionLongPress,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(192, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(actionLabel!),
                        ],
                      ),
                    ),
                  ],
                  if (templateActions.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'O empieza con una plantilla',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface.withValues(alpha: 0.84),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final template in templateActions)
                          _TemplateQuickAction(
                            template: template,
                            onPressed: onTemplateSelected == null
                                ? null
                                : () => onTemplateSelected!(template),
                          ),
                      ],
                    ),
                  ],
                  if (signInHint != null) ...[
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        signInHint!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBoardIllustration extends StatelessWidget {
  const _EmptyBoardIllustration({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: 112,
        height: 100,
        child: FittedBox(
          child: SizedBox(
            width: 156,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors.primary.withValues(alpha: 0.16),
                        colors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(-15, -6),
                  child: Transform.rotate(
                    angle: -0.16,
                    child: Container(
                      width: 86,
                      height: 96,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: 0.07,
                  child: Container(
                    width: 88,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.surfaceContainerHigh,
                          colors.surfaceContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 42, color: colors.primary),
                  ),
                ),
                Positioned(
                  right: 15,
                  top: 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: colors.onPrimaryContainer,
                    ),
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
      child: Tooltip(
        message: template.description,
        child: Material(
          color: colorScheme.surfaceContainer.withValues(alpha: 0.82),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('template-action-${template.label}'),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(template.icon, size: 18, color: foreground),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    template.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
