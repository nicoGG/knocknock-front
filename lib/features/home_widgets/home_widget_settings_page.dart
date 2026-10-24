import 'package:nocknock/features/home_widgets/home_widget_kind.dart';
import 'package:nocknock/features/finance/financial_style.dart';
import 'package:nocknock/core/widgets/liquid_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nocknock/features/home_widgets/home_widget_controller.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

class HomeWidgetSettingsPage extends StatefulWidget {
  const HomeWidgetSettingsPage({
    required this.controller,
    required this.lists,
    super.key,
  });
  final HomeWidgetController controller;
  final List<NoteList> lists;
  @override
  State<HomeWidgetSettingsPage> createState() => _HomeWidgetSettingsPageState();
}

class _HomeWidgetSettingsPageState extends State<HomeWidgetSettingsPage> {
  late final _lists = widget.lists
      .where(
        (list) =>
            !widget.controller.protection.isProtected(list.id) &&
            !list.isEncryptionKeyPending,
      )
      .toList();
  late String _source =
      _lists.any((list) => list.id == widget.controller.listId)
      ? widget.controller.listId!
      : '';
  late String _capture =
      _lists.any((list) => list.id == widget.controller.captureListId)
      ? widget.controller.captureListId!
      : '';
  late bool _hidden = widget.controller.hideContent;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.configure(
        source: _source.isEmpty ? null : _source,
        capture: _capture.isEmpty ? null : _capture,
        hidden: _hidden,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudieron guardar los ajustes. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addWidget(HomeWidgetKind kind) async {
    final requested = await widget.controller.requestPin(kind: kind);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          requested ? 'Confirma ${kind.label} en tu pantalla de inicio.' : 'Mantén pulsada la pantalla de inicio, abre Widgets y busca NockNock.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Widgets de inicio')),
    body: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.primary.withValues(alpha: .08),
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FinancialSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FinancialIconBadge(icon: Icons.widgets_rounded, size: 52),
                const SizedBox(height: 16),
                Text(
                  'Tus listas, a mano',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Elige el widget que más te sirva. Cada lista permite seleccionar su contenido desde el botón de ajustes del widget. Mantén pulsado un widget y arrastra sus bordes para cambiar el tamaño.',
                ),
                const SizedBox(height: 16),
                if (defaultTargetPlatform == TargetPlatform.android)
                  ...HomeWidgetKind.values.map(
                    (kind) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: .15),
                          ),
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary
                                  .withValues(alpha: .10),
                              Theme.of(context).colorScheme.secondary
                                  .withValues(alpha: .04),
                            ],
                          ),
                        ),
                        child: ListTile(
                          key: ValueKey('add-home-widget-${kind.name}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          leading: Icon(switch (kind) {
                            HomeWidgetKind.capture => Icons.add_box_outlined,
                            HomeWidgetKind.summary => Icons.dashboard_outlined,
                            HomeWidgetKind.upcoming =>
                              Icons.view_agenda_outlined,
                            HomeWidgetKind.list => Icons.checklist_rounded,
                            HomeWidgetKind.expanded => Icons.view_list_rounded,
                          }, color: Theme.of(context).colorScheme.primary),
                          title: Text(
                            '${kind.label} · ${kind.sizeLabel}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          subtitle: Text(kind.description),
                          trailing: const Icon(
                            Icons.add_circle_outline_rounded,
                          ),
                          onTap: () => _addWidget(kind),
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'En iPhone: mantén pulsada la pantalla de inicio, toca Editar → Agregar widget y busca NockNock.',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FinancialSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LiquidDropdownFormField<String>(
                  key: const ValueKey('widget-source'),
                  initialValue: _source,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mostrar pendientes de',
                    prefixIcon: Icon(Icons.view_list_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Hoy')),
                    ..._lists.map(
                      (list) => DropdownMenuItem(
                        value: list.id,
                        child: Text(list.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _source = value!),
                ),
                const SizedBox(height: 20),
                LiquidDropdownFormField<String>(
                  key: const ValueKey('widget-capture-list'),
                  initialValue: _capture,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Guardar capturas en',
                    prefixIcon: Icon(Icons.note_add_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Última lista utilizada'),
                    ),
                    ..._lists.map(
                      (list) => DropdownMenuItem(
                        value: list.id,
                        child: Text(list.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _capture = value!),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ocultar contenido'),
                  subtitle: const Text(
                    'Muestra solo accesos para abrir la app o capturar una nota.',
                  ),
                  value: _hidden,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _hidden = value),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Las listas protegidas con biometría siempre quedan ocultas. En Android, el widget conserva los títulos, subtareas y resúmenes de las listas visibles en este dispositivo.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FinancialSurface(
            child: Text(
              'Marca una tarea para guardarla como completada en el widget. Se sincronizará al abrir NockNock. Los recordatorios recurrentes se gestionan dentro de la app. La captura abre directamente un editor compacto.',
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar ajustes'),
          ),
        ],
      ),
    ),
  );
}
