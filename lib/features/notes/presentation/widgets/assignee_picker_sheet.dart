import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'assignee_picker_style.dart';

class AssigneeSelection {
  const AssigneeSelection({this.uids = const [], this.customNames = const []});

  final List<String> uids;
  String? get uid => uids.firstOrNull;
  final List<String> customNames;
  String? get customName => customNames.firstOrNull;
}

class AssigneePickerSheet extends StatefulWidget {
  const AssigneePickerSheet({
    super.key,
    required this.selectedUids,
    required this.customNames,
    this.optionPrefix = 'preview-assignee',
    this.nameFieldKey = 'custom-assignee-name-field',
    required this.assignees,
  });

  final List<String> selectedUids;
  final List<String> customNames;
  String? get customName => customNames.firstOrNull;
  final String optionPrefix;
  final String nameFieldKey;
  final List<ListCollaborator> assignees;

  @override
  State<AssigneePickerSheet> createState() => AssigneePickerSheetState();
}

class AssigneePickerSheetState extends State<AssigneePickerSheet> {
  late final Set<String> _selected = widget.selectedUids.toSet();
  late final List<String> _customNames = List.of(widget.customNames);
  int get _count => _selected.length + _customNames.length;
  String? get customName => _customNames.firstOrNull;

  List<ListCollaborator> get assignees => widget.assignees;

  Future<void> _pickCustomName(BuildContext context) async {
    if (_count >= 3) {
      return;
    }
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Responsable personalizado'),
        content: TextFormField(
          key: ValueKey(widget.nameFieldKey),
          initialValue: enteredName,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej. Camila',
            helperText: 'No necesita tener una cuenta en NockNock.',
          ),
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) {
              Navigator.pop(dialogContext, normalized);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('save-custom-assignee-button'),
            onPressed: () {
              final normalized = enteredName.trim();
              if (normalized.isNotEmpty) {
                Navigator.pop(dialogContext, normalized);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!context.mounted || name == null) return;
    if (_customNames.any(
      (entry) => entry.toLowerCase() == name.toLowerCase(),
    )) {
      return;
    }
    setState(() => _customNames.add(name));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                const AssigneePickerHeader(),
                ListTile(
                  key: ValueKey('${widget.optionPrefix}-unassigned'),
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_off_outlined),
                  ),
                  title: const Text('Sin responsable'),
                  trailing: _count == 0
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () =>
                      Navigator.pop(context, const AssigneeSelection()),
                ),
                ListTile(
                  key: ValueKey('${widget.optionPrefix}-custom'),
                  leading: const CircleAvatar(
                    child: Icon(Icons.manage_accounts_outlined),
                  ),
                  title: const Text('Responsable personalizado'),
                  subtitle: const Text(
                    'Agrega a alguien aunque no use NockNock.',
                  ),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => _pickCustomName(context),
                ),
                for (final name in _customNames)
                  AssigneePickerPerson(
                    key: ValueKey('custom-assignee-$name'),
                    avatar: CircleAvatar(
                      child: Text(name.characters.first.toUpperCase()),
                    ),
                    label: name,
                    email: 'Personalizado · Toca para quitar',
                    selected: true,
                    onTap: () => setState(() => _customNames.remove(name)),
                  ),
                if (assignees.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.group_add_outlined),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Aún no hay personas en esta lista. Invita colaboradores para poder asignarles la nota.',
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final person in assignees)
                  AssigneePickerPerson(
                    key: ValueKey('${widget.optionPrefix}-${person.uid}'),
                    avatar: CircleAvatar(
                      foregroundImage:
                          person.photoUrl?.trim().isNotEmpty == true
                          ? NetworkImage(person.photoUrl!.trim())
                          : null,
                      onForegroundImageError:
                          person.photoUrl?.trim().isNotEmpty == true
                          ? (_, _) {}
                          : null,
                      child: Text(_collaboratorInitial(person)),
                    ),
                    label: _collaboratorLabel(person),
                    email: person.email.trim().isEmpty
                        ? null
                        : person.email.trim(),
                    selected: _selected.contains(person.uid),
                    onTap: () {
                      if (!_selected.contains(person.uid) && _count >= 3) {
                        return;
                      }
                      setState(() {
                        if (!_selected.add(person.uid)) {
                          _selected.remove(person.uid);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          if (_count >= 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('assignee-limit-warning'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Máximo 3 personas. Quita una selección para asignar a alguien más.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          AssigneePickerFooter(
            count: _count,
            onSave: () {
              if (_count > 3) return;
              Navigator.pop(
                context,
                AssigneeSelection(
                  uids: _selected.toList(),
                  customNames: List.of(_customNames),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

String _collaboratorLabel(ListCollaborator person) =>
    person.displayName.trim().isEmpty ? person.email : person.displayName;
String _collaboratorInitial(ListCollaborator person) =>
    _collaboratorLabel(person).characters.firstOrNull?.toUpperCase() ?? '?';
