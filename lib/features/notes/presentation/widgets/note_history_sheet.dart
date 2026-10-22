import 'package:nocknock/features/notes/presentation/widgets/note_version_preview.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';

Future<bool> showNoteHistorySheet({
  required BuildContext context,
  required Note Function() currentNote,
  required Future<List<NoteVersion>> Function() load,
  required Future<void> Function(Note, NoteVersion) restore,
  required Listenable protectionChanges,
  required bool Function() canAccess,
}) async {
  final restored = await showLiquidBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => _NoteHistorySheet(
      currentNote: currentNote,
      load: load,
      restore: restore,
      protectionChanges: protectionChanges,
      canAccess: canAccess,
    ),
  );
  return restored ?? false;
}

String noteEditAttribution(Note note) {
  final name = note.lastEditedByName?.trim();
  final who = name == null || name.isEmpty ? 'Última edición' : 'Editó $name';
  return '$who · ${DateFormat('d MMM, HH:mm', 'es').format((note.lastEditedAt ?? note.updatedAt).toLocal())}';
}

class _NoteHistorySheet extends StatefulWidget {
  const _NoteHistorySheet({
    required this.currentNote,
    required this.load,
    required this.restore,
    required this.protectionChanges,
    required this.canAccess,
  });
  final Note Function() currentNote;
  final Future<List<NoteVersion>> Function() load;
  final Future<void> Function(Note, NoteVersion) restore;
  final Listenable protectionChanges;
  final bool Function() canAccess;
  @override
  State<_NoteHistorySheet> createState() => _NoteHistorySheetState();
}

class _NoteHistorySheetState extends State<_NoteHistorySheet> {
  late Future<List<NoteVersion>> _versions = widget.load();
  bool _saving = false;
  String? _error;
  Future<void> _restore(NoteVersion version) async {
    if (!widget.canAccess() || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => LiquidAlertDialog(
        icon: const Icon(Icons.restore_rounded),
        title: const Text('¿Recuperar esta versión?'),
        content: Text(
          widget.currentNote().financialEntry != null ||
                  version.note.financialEntry != null
              ? 'Se recuperarán los datos financieros y los abonos de esta versión. Los responsables y adjuntos actuales se conservan. Si recuperas un registro cerrado, se cancelará su alerta. La versión actual quedará en el historial.'
              : 'Se recuperarán el texto, el dibujo, la lista de tareas y el estilo. Los responsables, recordatorios y adjuntos actuales se conservan. La versión actual quedará en el historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-restore-version'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recuperar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !widget.canAccess()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.restore(widget.currentNote(), version);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = notesErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: widget.protectionChanges,
      builder: (context, _) => PopScope(
        canPop: !_saving,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .80,
          child: Stack(
            children: [
              const Positioned.fill(child: AmbientPageBackground()),
              Padding(
                key: const ValueKey('note-history-sheet'),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 20),
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
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: .16),
                            ),
                          ),
                          child: Icon(
                            Icons.history_rounded,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Historial',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Cada cambio tiene su historia',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar historial',
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: colors.surface.withValues(
                              alpha: .35,
                            ),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 21),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (!widget.canAccess())
                      const Expanded(
                        child: _HistoryMessage(
                          icon: Icons.lock_rounded,
                          title: 'Tu historial está protegido',
                          detail: 'Desbloquea la lista para ver el historial.',
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colors.primary.withValues(
                                alpha: dark ? .12 : .08,
                              ),
                              colors.surface.withValues(
                                alpha: dark ? .28 : .45,
                              ),
                            ],
                          ),
                          border: Border.all(
                            color: colors.outlineVariant.withValues(alpha: .30),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.sticky_note_2_rounded,
                              color: colors.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.currentNote().title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    noteEditAttribution(widget.currentNote()),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'VERSIONES ANTERIORES',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Text(
                              'Últimas 10',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      Expanded(
                        child: FutureBuilder<List<NoteVersion>>(
                          future: _versions,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const _HistoryLoading();
                            }
                            if (snapshot.hasError) {
                              return _HistoryMessage(
                                icon: Icons.cloud_off_rounded,
                                title: 'No pudimos cargar los cambios',
                                detail:
                                    'Revisa tu conexión e inténtalo de nuevo.',
                                action: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _versions = widget.load()),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Reintentar'),
                                ),
                              );
                            }
                            final versions = snapshot.data ?? const [];
                            if (versions.isEmpty) {
                              return const _HistoryMessage(
                                icon: Icons.auto_awesome_rounded,
                                title: 'Una historia por empezar',
                                detail: 'Aquí aparecerán las próximas ediciones.\nLas versiones anteriores a esta función no están disponibles.',
                              );
                            }
                            return ScrollEdgeFade(
                              child: ListView.separated(
                                padding: EdgeInsets.only(
                                  top: 2,
                                  bottom:
                                      20 + MediaQuery.paddingOf(context).bottom,
                                ),
                                itemCount: versions.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final version = versions[index];
                                  final name = version.editorName?.trim();
                                  final initials = name == null || name.isEmpty
                                      ? null
                                      : name
                                            .split(RegExp(r'\s+'))
                                            .take(2)
                                            .map(
                                              (word) => word.characters.first,
                                            )
                                            .join()
                                            .toUpperCase();
                                  return Container(
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          colors.surfaceContainerHigh
                                              .withValues(
                                                alpha: dark ? .48 : .65,
                                              ),
                                          colors.surface.withValues(alpha: .25),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: colors.outlineVariant.withValues(
                                          alpha: .28,
                                        ),
                                      ),
                                    ),
                                    child: ExpansionTile(
                                      key: ValueKey(
                                        'note-version-${version.revision}',
                                      ),
                                      shape: const Border(),
                                      collapsedShape: const Border(),
                                      iconColor: colors.primary,
                                      collapsedIconColor:
                                          colors.onSurfaceVariant,
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      childrenPadding:
                                          const EdgeInsets.fromLTRB(
                                            12,
                                            0,
                                            12,
                                            12,
                                          ),
                                      leading: Container(
                                        width: 42,
                                        height: 42,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: colors.primary.withValues(
                                            alpha: .12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                        ),
                                        child: initials == null
                                            ? Icon(
                                                Icons.person_rounded,
                                                color: colors.primary,
                                                size: 22,
                                              )
                                            : Text(
                                                initials,
                                                style: theme
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      color: colors.primary,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                      ),
                                      title: Text(
                                        name?.isNotEmpty == true
                                            ? name!
                                            : 'Editor no registrado',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          DateFormat(
                                            'd MMM yyyy · HH:mm',
                                            'es',
                                          ).format(version.savedAt.toLocal()),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      children: [
                                        NoteVersionPreview(note: version.note),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton.tonalIcon(
                                            key: ValueKey(
                                              'restore-version-${version.revision}',
                                            ),
                                            onPressed: _saving
                                                ? null
                                                : () => _restore(version),
                                            style: FilledButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.restore_rounded,
                                              size: 18,
                                            ),
                                            label: Text(
                                              _saving
                                                  ? 'Recuperando…'
                                                  : 'Recuperar versión',
                                            ),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando historial',
    child: ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          3,
          (index) => Container(
            height: 88,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Theme.of(context).colorScheme.surfaceContainerHigh
                  .withValues(alpha: .30),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: .07),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FractionallySizedBox(
                        widthFactor: .65,
                        child: Container(
                          height: 10,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: .07),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FractionallySizedBox(
                        widthFactor: .4,
                        child: Container(
                          height: 8,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: .05),
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
    ),
  );
}
