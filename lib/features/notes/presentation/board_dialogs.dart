part of 'board_page.dart';

/// List-management and collaboration dialogs.

class _CollaboratorsDialog extends StatefulWidget {
  const _CollaboratorsDialog({required this.initialList});

  final NoteList initialList;

  @override
  State<_CollaboratorsDialog> createState() => _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends State<_CollaboratorsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _removingCollaboratorUid;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesCubit, NotesState>(
      builder: (context, state) {
        final list = state.lists.firstWhere(
          (item) => item.id == widget.initialList.id,
          orElse: () => widget.initialList,
        );
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          key: const ValueKey('collaborators-dialog'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.1),
            colorScheme.surfaceContainerHigh,
          ),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.36),
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.diversity_3_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.canInvite
                          ? 'Comparte esta lista'
                          : 'Personas de la lista',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: state.isInviting || state.isRemovingCollaborator
                    ? null
                    : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.14),
                          colorScheme.primary.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          list.canInvite
                              ? Icons.auto_awesome_rounded
                              : Icons.info_outline_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            list.canInvite
                                ? 'Invita a otras personas. La lista aparecerá '
                                      'cuando ingresen con ese correo.'
                                : 'Aquí puedes ver quiénes participan. Solo la '
                                      'persona propietaria gestiona los accesos.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (list.canInvite) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Form(
                            key: _formKey,
                            child: TextFormField(
                              key: const ValueKey('collaborator-email-field'),
                              controller: _emailController,
                              enabled:
                                  !state.isInviting &&
                                  !state.isRemovingCollaborator,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.send,
                              autocorrect: false,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                hintText: 'nombre@correo.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                              validator: _validateEmail,
                              onChanged: (_) => setState(() {}),
                              onFieldSubmitted: (_) => _sendInvitation(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const ValueKey('send-invitation-button'),
                              onPressed:
                                  state.isInviting ||
                                      state.isRemovingCollaborator ||
                                      !_hasValidEmail
                                  ? null
                                  : _sendInvitation,
                              icon: state.isInviting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.person_add_rounded),
                              label: Text(
                                state.isInviting
                                    ? 'Enviando invitación…'
                                    : 'Invitar a esta lista',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'PERSONAS CON ACCESO',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (list.collaborators.isEmpty)
                    Text(
                      'Aún no hay personas con acceso a esta lista.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  else
                    ...list.collaborators.map(
                      (person) => ListTile(
                        key: ValueKey('collaborator-${person.uid}'),
                        contentPadding: EdgeInsets.zero,
                        leading: _CollaboratorAvatar(person: person),
                        title: Text(
                          person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          person.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: person.role == ListMemberRole.owner
                            ? Text(
                                'Propietario',
                                style: Theme.of(context).textTheme.labelSmall,
                              )
                            : list.canInvite
                            ? IconButton(
                                key: ValueKey(
                                  'remove-collaborator-${person.uid}',
                                ),
                                tooltip:
                                    'Quitar a ${person.displayName} de la lista',
                                onPressed:
                                    state.isRemovingCollaborator ||
                                        state.isInviting
                                    ? null
                                    : () => _confirmRemoveCollaborator(
                                        list,
                                        person,
                                      ),
                                icon:
                                    _removingCollaboratorUid == person.uid &&
                                        state.isRemovingCollaborator
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_remove_outlined),
                              )
                            : Text(
                                'Puede editar',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                      ),
                    ),
                  if (list.pendingInvitations.isNotEmpty) ...[
                    const Divider(height: 28),
                    const Text(
                      'INVITACIONES POR ACEPTAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...list.pendingInvitations.map(
                      (invitation) => ListTile(
                        key: ValueKey('pending-${invitation.email}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.schedule_send_outlined),
                        ),
                        title: Text(
                          invitation.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text(
                          'Tendrá acceso cuando inicie sesión',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Escribe el correo de la persona';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Escribe un correo válido';
    }
    return null;
  }

  bool get _hasValidEmail => _validateEmail(_emailController.text) == null;

  Future<void> _sendInvitation() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final sent = await context.read<NotesCubit>().inviteCollaborator(
      _emailController.text,
    );
    if (sent && mounted) {
      _emailController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _confirmRemoveCollaborator(
    NoteList list,
    ListCollaborator person,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('remove-collaborator-dialog'),
        title: const Text('Quitar acceso'),
        content: Text(
          '${person.displayName} dejará de ver y editar “${list.name}”. '
          'Las notas de la lista no se eliminarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-remove-collaborator'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingCollaboratorUid = person.uid);
    await context.read<NotesCubit>().removeCollaborator(person.uid);
    if (mounted) setState(() => _removingCollaboratorUid = null);
  }
}

class _CollaboratorAvatar extends StatelessWidget {
  const _CollaboratorAvatar({required this.person});

  final ListCollaborator person;

  @override
  Widget build(BuildContext context) {
    final initial = person.displayName.trim().isEmpty
        ? '?'
        : person.displayName.trim()[0].toUpperCase();
    final photoUrl = person.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return CircleAvatar(
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.13),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (hasPhoto)
            ClipOval(
              child: Image.network(
                photoUrl,
                cacheWidth: _avatarCacheSize(
                  context,
                  _CollaboratorAvatarStack._avatarSize,
                ),
                cacheHeight: _avatarCacheSize(
                  context,
                  _CollaboratorAvatarStack._avatarSize,
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateListDialog extends StatefulWidget {
  const _CreateListDialog();

  @override
  State<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends State<_CreateListDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(32);

    return Dialog(
      key: const ValueKey('create-list-glass-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: 620,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: isDark ? 0.42 : 0.28,
                ),
                blurRadius: 38,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.12),
                blurRadius: 28,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              key: const ValueKey('create-list-dialog-glass-blur'),
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                key: const ValueKey('create-list-dialog-glass-surface'),
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.24 : 0.56),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.12 : 0.38),
                      colorScheme.surfaceContainerHigh.withValues(
                        alpha: isDark ? 0.68 : 0.62,
                      ),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nueva lista',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const ValueKey('list-name-field'),
                          controller: _controller,
                          autofocus: true,
                          maxLength: 50,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: const [
                            InitialUppercaseTextFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Nombre de la lista',
                            hintText: 'Ej. Trabajo, Viaje o Casa',
                            filled: true,
                            fillColor: colorScheme.surface.withValues(
                              alpha: isDark ? 0.28 : 0.34,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.22 : 0.48,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Escribe un nombre para la lista'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              key: const ValueKey('create-list-confirm-button'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: _submit,
                              child: const Text('Crear lista'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, capitalizeInitialLetter(_controller.text.trim()));
    }
  }
}

class _EditListNameDialog extends StatefulWidget {
  const _EditListNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditListNameDialog> createState() => _EditListNameDialogState();
}

class _EditListNameDialogState extends State<_EditListNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar nombre de la lista'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('edit-list-name-field'),
          controller: _controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: const [InitialUppercaseTextFormatter()],
          decoration: const InputDecoration(labelText: 'Nombre de la lista'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Escribe un nombre para la lista'
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('save-list-name-button'),
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, capitalizeInitialLetter(_controller.text.trim()));
    }
  }
}
