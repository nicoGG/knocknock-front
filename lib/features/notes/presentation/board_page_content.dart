part of 'board_page.dart';

/// Coordinates board-specific commands, derived content, and navigation.
///
/// It stays in the private board library so it can use the page state without
/// expanding the public presentation API.
extension _BoardPageContent on _BoardPageState {
  Widget _contentSliver(
    NotesState state,
    List<Note> notes,
    NoteCategory? selectedCategory,
    String? selectedAssigneeUid,
  ) {
    if ((_scope == _BoardScope.assignedToMe && state.isLoadingAssigned) ||
        (_scope == _BoardScope.pinned && state.isLoadingPinned) ||
        (_scope == _BoardScope.withReminder && state.isLoadingReminderNotes) ||
        state.status == NotesStatus.loading ||
        state.status == NotesStatus.initial) {
      return const SliverFillRemaining(child: BoardLoadingState());
    }
    if (state.status == NotesStatus.failure && state.notes.isEmpty) {
      return SliverFillRemaining(
        child: _MessageState(
          icon: Icons.cloud_off_rounded,
          title: 'No pudimos abrir el tablero',
          detail: 'Enciende el backend y vuelve a intentarlo.',
          actionLabel: 'Reintentar',
          onAction: context.read<NotesCubit>().load,
        ),
      );
    }
    if (_scope == _BoardScope.list &&
        (state.selectedList?.isEncryptionKeyPending ?? false)) {
      return SliverFillRemaining(
        child: _MessageState(
          key: const ValueKey('board-encryption-key-recovery'),
          icon: Icons.key_rounded,
          title: 'Recuperando la llave de esta lista',
          detail:
              'Tus notas siguen cifradas y seguras. Mantén NockNock abierto aquí '
              'y abre la lista en otro dispositivo o desde la cuenta de otra '
              'persona que ya tenga acceso.',
          actionLabel: 'Reintentar',
          onAction: context.read<NotesCubit>().load,
        ),
      );
    }
    final Widget content;
    if (notes.isEmpty) {
      final isUnfiltered =
          _filter == NoteFilter.all &&
          selectedCategory == null &&
          selectedAssigneeUid == null;
      final isFirstListEmpty = _scope == _BoardScope.list && isUnfiltered;
      final isGuest = context.read<AuthRepository>().currentUser == null;
      content = SliverFillRemaining(
        key: ValueKey(
          'board-empty-${_scope.name}-${_filter.name}'
          '${selectedCategory == null ? '' : '-${selectedCategory.name}'}'
          '${selectedAssigneeUid == null ? '' : '-assignee-$selectedAssigneeUid'}',
        ),
        child: _MessageState(
          icon: switch (_scope) {
            _BoardScope.pinned => Icons.push_pin_outlined,
            _BoardScope.withReminder => Icons.alarm_outlined,
            _BoardScope.list ||
            _BoardScope.assignedToMe => Icons.sticky_note_2_outlined,
          },
          title: switch (_scope) {
            _BoardScope.assignedToMe =>
              isUnfiltered
                  ? 'No tienes notas asignadas'
                  : 'No hay notas asignadas en este filtro',
            _BoardScope.pinned =>
              isUnfiltered
                  ? 'Todavía no tienes notas ancladas'
                  : 'No hay notas ancladas en este filtro',
            _BoardScope.withReminder =>
              isUnfiltered
                  ? 'Todavía no tienes notas con recordatorio'
                  : 'No hay notas con recordatorio en este filtro',
            _BoardScope.list =>
              isUnfiltered
                  ? 'Tu lista está lista'
                  : 'No hay notas en este filtro',
          },
          detail: switch (_scope) {
            _BoardScope.assignedToMe =>
              'Cuando te asignen una nota, aparecerá aquí.',
            _BoardScope.pinned =>
              'Ancla una nota en cualquier lista y aparecerá aquí.',
            _BoardScope.withReminder =>
              'Agrega un recordatorio a una nota y aparecerá aquí.',
            _BoardScope.list =>
              isUnfiltered
                  ? 'Crea una nota y empieza a organizar lo que importa.'
                  : 'Prueba otro filtro o crea una nota nueva.',
          },
          actionLabel: isFirstListEmpty ? 'Crear una nota' : null,
          onAction: isFirstListEmpty ? _openNewNoteEditor : null,
          templateActions: isFirstListEmpty ? _noteTemplates : const [],
          onTemplateSelected: isFirstListEmpty ? _openTemplate : null,
          signInHint: isFirstListEmpty && isGuest
              ? 'Inicia sesión para respaldar, sincronizar y colaborar en tus notas.'
              : null,
        ),
      );
    } else {
      content = KeyedSubtree(
        key: ValueKey(
          'board-notes-${_viewMode.name}-${_filter.name}'
          '${selectedCategory == null ? '' : '-${selectedCategory.name}'}'
          '${selectedAssigneeUid == null ? '' : '-assignee-$selectedAssigneeUid'}',
        ),
        child: switch (_viewMode) {
          BoardViewMode.grid => _NotesGrid(
            key: const ValueKey('notes-grid'),
            notes: notes,
            groupCompleted: _filter == NoteFilter.all,
            completedSectionExpanded: _completedSectionExpanded,
            animateEntrances: _animateNoteEntrances,
            showOriginList:
                _scope == _BoardScope.assignedToMe ||
                _scope == _BoardScope.pinned ||
                _scope == _BoardScope.withReminder,
            buildCard: _buildCard,
            onReorder: _reorderNotes,
            onCompletedSectionExpansionChanged:
                _changeCompletedSectionExpansion,
          ),
          BoardViewMode.list => _NotesList(
            key: const ValueKey('notes-list'),
            notes: notes,
            groupCompleted: _filter == NoteFilter.all,
            completedSectionExpanded: _completedSectionExpanded,
            animateEntrances: _animateNoteEntrances,
            layout: PostItCardLayout.compact,
            itemHeight: 55,
            maxWidth: 980,
            buildCard: _buildCard,
            onReorder: _reorderNotes,
            onCompletedSectionExpansionChanged:
                _changeCompletedSectionExpansion,
          ),
        },
      );
    }
    return _RetiringSliverFadeTransition(
      key: const ValueKey('board-content-fade'),
      opacity: _contentOpacity,
      sliver: content,
    );
  }

  bool _handleBoardScroll(ScrollNotification notification) {
    _updateAppBarParallax(notification);
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 480 &&
        _scope == _BoardScope.list) {
      final cubit = context.read<NotesCubit>();
      if (cubit.state.hasMoreNotes && !cubit.state.isLoadingMoreNotes) {
        unawaited(cubit.loadMoreNotes());
      }
    }
    return false;
  }

  bool _updateAppBarParallax(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final progress = (notification.metrics.pixels / 96).clamp(0.0, 1.0);
    if ((_appBarScrollProgress.value - progress).abs() > 0.001) {
      _appBarScrollProgress.value = progress;
    }
    return false;
  }

  Widget _buildCard(
    Note note,
    PostItCardLayout layout, {
    bool? completedChecklistExpanded,
    ValueChanged<bool>? onCompletedChecklistExpansionChanged,
  }) {
    final state = context.read<NotesCubit>().state;
    final noteList = state.lists
        .where((list) => list.id == note.boardId)
        .firstOrNull;
    final collaborators = noteList?.collaborators ?? const [];
    final assignee = resolveNoteAssignee(note, collaborators);
    final normalizedAuthorName = note.authorName.trim().toLowerCase();
    final author = collaborators
        .where(
          (person) =>
              person.displayName.trim().toLowerCase() == normalizedAuthorName,
        )
        .firstOrNull;
    final currentUser = context.read<AuthRepository>().currentUser;
    final currentUserPhoto =
        currentUser?.displayName.trim().toLowerCase() == normalizedAuthorName
        ? currentUser?.photoUrl?.trim()
        : null;
    final collaboratorPhoto = author?.photoUrl?.trim();
    return _NoteCompletionTransition(
      key: ValueKey('note-completion-transition-${note.id}'),
      note: note,
      removesFromCurrentFilter: switch (_filter) {
        NoteFilter.all => false,
        NoteFilter.pending => !note.isCompleted,
        NoteFilter.completed => note.isCompleted,
      },
      onToggle: () => context.read<NotesCubit>().toggleNote(note),
      builder: (context, displayedNote, onToggle) => PostItCard(
        note: displayedNote,
        layout: layout,
        originListName:
            _scope == _BoardScope.assignedToMe ||
                _scope == _BoardScope.pinned ||
                _scope == _BoardScope.withReminder
            ? noteList?.name ?? 'Lista desconocida'
            : null,
        assignee: assignee,
        authorPhotoUrl: currentUserPhoto?.isNotEmpty == true
            ? currentUserPhoto
            : collaboratorPhoto,
        onToggle: onToggle,
        onPin: () {
          _playBoardTapSound();
          HapticFeedback.lightImpact();
          context.read<NotesCubit>().togglePin(note);
        },
        onOpen: () {
          unawaited(_openNotePreview(note));
        },
        onChecklistToggle: (item) {
          HapticFeedback.selectionClick();
          context.read<NotesCubit>().toggleChecklistItem(note, item);
        },
        attachmentLoader: note.photoAttachments.isEmpty
            ? null
            : (attachmentId) =>
                  context.read<NotesCubit>().loadAttachment(note, attachmentId),
        completedChecklistExpanded: completedChecklistExpanded,
        onCompletedChecklistExpansionChanged:
            onCompletedChecklistExpansionChanged,
      ),
    );
  }

  List<Note> _filtered(List<Note> notes) {
    return switch (_filter) {
      NoteFilter.all => notes,
      NoteFilter.pending => notes.where((note) => !note.isCompleted).toList(),
      NoteFilter.completed => notes.where((note) => note.isCompleted).toList(),
    };
  }

  Map<NoteCategory, int> _categoryCounts(List<Note> notes) {
    final visibleCategories = notes.map((note) => note.category).toSet();
    final unorderedCounts = <NoteCategory, int>{
      for (final category in visibleCategories) category: 0,
    };
    for (final note in notes) {
      if (note.isCompleted) continue;
      unorderedCounts.update(
        note.category,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      for (final category in NoteCategory.values)
        if (visibleCategories.contains(category))
          category: unorderedCounts[category]!,
    };
  }

  List<_AssigneeFilterOption> _assigneeFilters(
    List<Note> notes,
    List<NoteList> lists,
  ) {
    final collaboratorsByUid = <String, ListCollaborator>{};
    for (final list in lists) {
      for (final collaborator in list.collaborators) {
        collaboratorsByUid.putIfAbsent(collaborator.uid, () => collaborator);
      }
    }

    final counts = <String, int>{};
    final customNamesByKey = <String, String>{};
    for (final note in notes) {
      final assigneeKey = noteAssigneeFilterKey(note);
      if (assigneeKey == null) continue;
      counts.putIfAbsent(assigneeKey, () => 0);
      if (!note.isCompleted) {
        counts.update(assigneeKey, (count) => count + 1);
      }
      final customName = note.customAssigneeName?.trim();
      if (customName != null && customName.isNotEmpty) {
        customNamesByKey.putIfAbsent(assigneeKey, () => customName);
      }
    }

    return counts.entries
        .map((entry) {
          final collaborator = collaboratorsByUid[entry.key];
          final customName = customNamesByKey[entry.key];
          final displayName = collaborator?.displayName.trim();
          final email = collaborator?.email.trim();
          return _AssigneeFilterOption(
            uid: entry.key,
            displayName: displayName?.isNotEmpty == true
                ? displayName!
                : email?.isNotEmpty == true
                ? email!.split('@').first
                : customName?.isNotEmpty == true
                ? customName!
                : 'Usuario asignado',
            photoUrl: collaborator?.photoUrl,
            count: entry.value,
          );
        })
        .toList(growable: false);
  }

  List<Note> _assignedToCurrentUser(List<Note> notes) {
    final userId = context.read<AuthRepository>().currentUser?.id;
    return notes
        .where((note) => userId != null && note.assigneeUid == userId)
        .toList();
  }

  int _pendingScopeCount(Iterable<Note> notes) => {
    for (final note in notes)
      if (!note.isCompleted &&
          widget.listProtectionController.canAccess(note.boardId))
        note.id,
  }.length;

  Future<void> _openGlobalSearch() async {
    _playBoardTapSound();
    final cubit = context.read<NotesCubit>();
    final result = await showGlobalNoteSearch(
      context: context,
      cubit: cubit,
      canShowList: widget.listProtectionController.canAccess,
    );
    if (!mounted || result == null) return;
    unawaited(_openNotePreview(result.note));
  }

  Future<bool> _selectList(String listId) async {
    final cubit = context.read<NotesCubit>();
    final targetList = cubit.state.lists
        .where((list) => list.id == listId)
        .firstOrNull;
    if (targetList != null) {
      final result = await widget.listProtectionController.unlock(
        listId,
        listName: targetList.name,
      );
      _automaticUnlockAttemptedListIds.add(listId);
      if (result != ListProtectionResult.success || !mounted) return false;
    }
    final previousListId = cubit.state.selectedListId;
    if (previousListId != listId) {
      widget.listProtectionController.lock(previousListId);
    }
    if (_scope != _BoardScope.list ||
        _categoryFilter != null ||
        _assigneeFilterUid != null) {
      _update(() {
        _scope = _BoardScope.list;
        _categoryFilter = null;
        _assigneeFilterUid = null;
      });
    }
    await cubit.selectList(listId);
    unawaited(_listShortcutsController.recordOpened(listId));
    if (!mounted) return false;
    _restoreBoardPreferences(listId);
    _scheduleActiveListProtectionSync(cubit.state);
    return true;
  }

  Future<void> _openAssignedToMe() async {
    final authRepository = context.read<AuthRepository>();
    if (authRepository.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión para ver las notas asignadas a ti.'),
        ),
      );
      _openProfile();
      return;
    }
    widget.listProtectionController
      ..setActiveList(null)
      ..lockAll();
    _update(() {
      _scope = _BoardScope.assignedToMe;
      _categoryFilter = null;
      _assigneeFilterUid = null;
    });
    _scheduleActiveListProtectionSync(context.read<NotesCubit>().state);
    await context.read<NotesCubit>().loadAssignedNotes();
  }

  Future<void> _openPinned() async {
    widget.listProtectionController
      ..setActiveList(null)
      ..lockAll();
    _update(() {
      _scope = _BoardScope.pinned;
      _categoryFilter = null;
      _assigneeFilterUid = null;
    });
    await context.read<NotesCubit>().loadPinnedNotes();
  }

  Future<void> _openWithReminder() async {
    widget.listProtectionController
      ..setActiveList(null)
      ..lockAll();
    _update(() {
      _scope = _BoardScope.withReminder;
      _categoryFilter = null;
      _assigneeFilterUid = null;
    });
    await context.read<NotesCubit>().loadReminderNotes();
  }

  void _reorderNotes(List<String> orderedIds) {
    if (_scope != _BoardScope.list) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ordena estas notas dentro de su lista original.'),
        ),
      );
      return;
    }
    context.read<NotesCubit>().reorderVisibleNotes(orderedIds);
  }

  void _openNote(Note note) {
    final cubit = context.read<NotesCubit>();
    final currentUser = context.read<AuthRepository>().currentUser;
    final sourceList = cubit.state.lists
        .where((list) => list.id == note.boardId)
        .firstOrNull;
    Navigator.of(context).push(
      buildNoteDetailRoute(
        context: context,
        builder: (_) => BlocProvider<NotesCubit>.value(
          value: cubit,
          child: NoteDetailPage(
            noteId: note.id,
            initialNote: note,
            listName:
                sourceList?.name ??
                cubit.state.selectedList?.name ??
                'Mis notas',
            defaultAuthorName: currentUser?.displayName ?? note.authorName,
            heroTag: noteHeroTag(
              note.id,
              variant: switch (_viewMode) {
                BoardViewMode.grid => PostItCardLayout.grid.name,
                BoardViewMode.list => PostItCardLayout.compact.name,
              },
            ),
            currentUserId: currentUser?.id,
            currentUserPhotoUrl: currentUser?.photoUrl,
          ),
        ),
      ),
    );
  }

  Future<void> _openNotePreview(Note initialNote) async {
    _playBoardTapSound();
    HapticFeedback.lightImpact();
    final cubit = context.read<NotesCubit>();
    final currentUser = context.read<AuthRepository>().currentUser;

    Note latestNote(NotesState state) =>
        [
          ...state.notes,
          ...state.pinnedNotes,
          ...state.reminderNotes,
        ].where((note) => note.id == initialNote.id).firstOrNull ??
        initialNote;

    final shouldOpen = await showNotePreviewDialog(
      context: context,
      noteProvider: () => latestNote(cubit.state),
      assigneesProvider: () {
        final note = latestNote(cubit.state);
        return cubit.state.lists
                .where((list) => list.id == note.boardId)
                .firstOrNull
                ?.collaborators ??
            const <ListCollaborator>[];
      },
      onSave: (note, draft) => cubit.editNote(note, draft),
      onDelete: cubit.deleteNote,
      cardBuilder:
          (
            dialogContext,
            editAssignee,
            editAttachment,
            editTarget,
            saveInline,
          ) => BlocBuilder<NotesCubit, NotesState>(
            bloc: cubit,
            buildWhen: (previous, current) {
              final previousNote = latestNote(previous);
              final currentNote = latestNote(current);
              final previousList = previous.lists
                  .where((list) => list.id == previousNote.boardId)
                  .firstOrNull;
              final currentList = current.lists
                  .where((list) => list.id == currentNote.boardId)
                  .firstOrNull;
              return previousNote != currentNote ||
                  previousList != currentList ||
                  previous.isSaving != current.isSaving;
            },
            builder: (context, state) {
              final note = latestNote(state);
              final sourceList = state.lists
                  .where((list) => list.id == note.boardId)
                  .firstOrNull;
              final collaborators =
                  sourceList?.collaborators ?? const <ListCollaborator>[];
              final signedInUserId = currentUser?.id;
              final reactionAuthorNames = <String, String>{
                for (final person in collaborators)
                  person.uid: person.displayName.trim().isNotEmpty
                      ? person.displayName.trim()
                      : person.email.trim(),
                ?signedInUserId: 'Tú',
                localNoteReactionUserId: 'Tú',
              };
              final assignee = resolveNoteAssignee(note, collaborators);
              final normalizedAuthorName = note.authorName.trim().toLowerCase();
              final author = collaborators
                  .where(
                    (person) =>
                        person.displayName.trim().toLowerCase() ==
                        normalizedAuthorName,
                  )
                  .firstOrNull;
              final currentUserPhoto =
                  currentUser?.displayName.trim().toLowerCase() ==
                      normalizedAuthorName
                  ? currentUser?.photoUrl?.trim()
                  : null;
              final collaboratorPhoto = author?.photoUrl?.trim();
              return PostItCard(
                note: note,
                layout: PostItCardLayout.large,
                enableHero: false,
                originListName: sourceList?.name,
                assignee: assignee,
                authorPhotoUrl: currentUserPhoto?.isNotEmpty == true
                    ? currentUserPhoto
                    : collaboratorPhoto,
                currentUserId: signedInUserId,
                reactionAuthorNames: reactionAuthorNames,
                isSavingReaction: state.isSaving,
                onToggleReaction: (emoji) {
                  HapticFeedback.selectionClick();
                  return cubit.toggleReaction(note, emoji, signedInUserId);
                },
                onToggle: () {
                  HapticFeedback.selectionClick();
                  cubit.toggleNote(note);
                },
                onPin: () {
                  _playBoardTapSound();
                  HapticFeedback.lightImpact();
                  cubit.togglePin(note);
                },
                onOpen: () {},
                onAssigneeTap: editAssignee,
                attachmentLoader: note.photoAttachments.isEmpty
                    ? null
                    : (attachmentId) =>
                          cubit.loadAttachment(note, attachmentId),
                inlineEditTarget: editTarget,
                onInlineSave: saveInline,
                onChecklistToggle: (item) {
                  HapticFeedback.selectionClick();
                  cubit.toggleChecklistItem(note, item);
                },
              );
            },
          ),
    );
    if (!mounted || !shouldOpen) return;
    _openNote(latestNote(cubit.state));
  }

  Future<void> _openEditor({Note? note, Note? initialNote}) async {
    final currentUser = context.read<AuthRepository>().currentUser;
    final assignees = context
        .read<NotesCubit>()
        .state
        .selectedList
        ?.collaborators;
    final defaultAuthorName = currentUser == null
        ? 'Invitado'
        : currentUser.displayName.trim().isNotEmpty
        ? currentUser.displayName.trim()
        : currentUser.email.trim();
    final availableAssignees = assignees ?? const <ListCollaborator>[];
    final draft = note == null
        ? await showCreateNoteDialog(
            context: context,
            defaultAuthorName: defaultAuthorName,
            showAuthorField: currentUser == null,
            assignees: availableAssignees,
            initialNote: initialNote,
          )
        : await showNoteEditor(
            context,
            note: note,
            defaultAuthorName: defaultAuthorName,
            showAuthorField: currentUser == null,
            assignees: availableAssignees,
          );
    if (draft == null || !mounted) return;
    final cubit = context.read<NotesCubit>();
    if (note == null) {
      await cubit.createNote(draft);
    } else {
      await cubit.editNote(note, draft);
    }
  }

  void _openNewNoteEditor() {
    _playBoardTapSound();
    unawaited(_openEditor());
  }

  List<_NoteTemplate> get _noteTemplates => const [
    _NoteTemplate(
      label: 'Tarea',
      description: 'Organiza pendientes',
      icon: Icons.task_alt_rounded,
      title: 'Nueva tarea',
      category: NoteCategory.work,
    ),
    _NoteTemplate(
      label: 'Compra',
      description: 'No olvides nada',
      icon: Icons.shopping_cart_outlined,
      title: 'Lista de compras',
      category: NoteCategory.shopping,
      checklist: ['Producto', 'Producto'],
    ),
    _NoteTemplate(
      label: 'Idea',
      description: 'Captúrala al vuelo',
      icon: Icons.lightbulb_outline_rounded,
      title: 'Nueva idea',
      category: NoteCategory.ideas,
    ),
    _NoteTemplate(
      label: 'Reunión',
      description: 'Objetivo y acuerdos',
      icon: Icons.groups_2_outlined,
      title: 'Reunión',
      content: 'Objetivo:\n\nNotas:\n\nPróximos pasos:',
      category: NoteCategory.work,
    ),
    _NoteTemplate(
      label: 'Checklist',
      description: 'Paso a paso',
      icon: Icons.checklist_rounded,
      title: 'Checklist',
      checklist: ['Pendiente'],
    ),
  ];

  void _openTemplate(_NoteTemplate template) {
    _playBoardTapSound();
    final now = DateTime.now();
    final author = context.read<AuthRepository>().currentUser;
    final authorName = author == null
        ? 'Invitado'
        : author.displayName.trim().isNotEmpty
        ? author.displayName.trim()
        : author.email.trim();
    unawaited(
      _openEditor(
        initialNote: Note(
          id: 'new-note-template',
          boardId: '',
          title: template.title,
          content: template.content,
          color: NoteColor.none,
          authorName: authorName,
          category: template.category,
          checklist: [
            for (var index = 0; index < template.checklist.length; index++)
              NoteChecklistItem(
                id: 'template-$index',
                text: template.checklist[index],
                isCompleted: false,
              ),
          ],
          isCompleted: false,
          positionX: 0,
          positionY: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
  }

  Future<void> _createList() async {
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => const _CreateListDialog(),
    );
    if (name == null || !mounted) return;
    widget.listProtectionController.lockAll();
    await context.read<NotesCubit>().createList(name);
    if (mounted && (_categoryFilter != null || _assigneeFilterUid != null)) {
      _update(() {
        _categoryFilter = null;
        _assigneeFilterUid = null;
      });
    }
  }

  Future<void> _openListReorder() async {
    final cubit = context.read<NotesCubit>();
    final lists = List<NoteList>.of(cubit.state.lists);
    if (lists.length < 2) return;
    final orderedIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (_) => _ReorderListsSheet(
        lists: lists,
        selectedListId: cubit.state.selectedListId,
      ),
    );
    if (orderedIds == null || !mounted) return;
    await cubit.reorderLists(orderedIds);
  }

  Future<void> _openCollaborators(NoteList? list) async {
    if (list == null) return;
    final authRepository = context.read<AuthRepository>();
    if (authRepository.currentUser == null) {
      final openProfile = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Inicia sesión para compartir'),
          content: const Text(
            'Conecta tu cuenta de Google para invitar por correo y mantener '
            'la lista sincronizada entre todos los colaboradores.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ahora no'),
            ),
            FilledButton.icon(
              key: const ValueKey('share-sign-in-button'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
      if (openProfile == true && mounted) _openProfile();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<NotesCubit>.value(
        value: context.read<NotesCubit>(),
        child: _CollaboratorsDialog(initialList: list),
      ),
    );
  }

  Future<void> _openBackgroundPicker() async {
    final cubit = context.read<NotesCubit>();
    final list = cubit.state.selectedList;
    if (_scope == _BoardScope.list && list == null) return;
    final aggregateScope = switch (_scope) {
      _BoardScope.assignedToMe => AggregateBoardScope.assignedToMe,
      _BoardScope.pinned => AggregateBoardScope.pinned,
      _BoardScope.withReminder => AggregateBoardScope.withReminder,
      _BoardScope.list => null,
    };
    final appearance = await showListBackgroundPicker(
      context,
      initialAppearance: switch (_scope) {
        _BoardScope.assignedToMe =>
          cubit.state.aggregateBoardAppearances.assignedToMe,
        _BoardScope.pinned => cubit.state.aggregateBoardAppearances.pinned,
        _BoardScope.withReminder =>
          cubit.state.aggregateBoardAppearances.withReminder,
        _BoardScope.list => list!.appearance,
      },
    );
    if (appearance == null || !mounted) return;
    if (aggregateScope != null) {
      await cubit.updateAggregateBoardAppearance(aggregateScope, appearance);
      return;
    }
    await cubit.updateListAppearance(appearance);
  }

  Future<void> _renameList() async {
    final cubit = context.read<NotesCubit>();
    final list = cubit.state.selectedList;
    if (list == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditListNameDialog(initialName: list.name),
    );
    if (name == null || !mounted) return;
    await cubit.updateSelectedList(name);
  }

  Future<void> _deleteList() async {
    final cubit = context.read<NotesCubit>();
    final list = cubit.state.selectedList;
    if (list == null) return;
    final isOnlyList = cubit.state.lists.length == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text(
          'Se eliminará “${list.name}” junto con todas sus notas. '
          'Esta acción no se puede deshacer.'
          '${isOnlyList ? ' Como es tu única lista, se creará una lista vacía para que puedas seguir usando NockNock.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-list-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final deleted = await cubit.deleteSelectedList();
      if (deleted) {
        unawaited(widget.viewModeController.forgetList(list.id));
        await widget.listProtectionController.forgetList(list.id);
        if (mounted &&
            (_categoryFilter != null || _assigneeFilterUid != null)) {
          _update(() {
            _categoryFilter = null;
            _assigneeFilterUid = null;
          });
        }
      }
    }
  }

  void _openSettings() {
    final authRepository = context.read<AuthRepository>();
    final notesCubit = context.read<NotesCubit>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          authRepository: authRepository,
          onOpenProfile: _openProfile,
          onClearLocalData: notesCubit.clearLocalData,
          notificationsController: widget.notificationsController,
          onOpenNotifications: widget.notificationsController == null
              ? null
              : _openNotifications,
        ),
      ),
    );
  }

  void _openTrash() {
    final cubit = context.read<NotesCubit>();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => TrashPage(cubit: cubit)));
  }

  void _restoreBoardPreferences([String? listId]) {
    if (!mounted) return;
    final activeListId =
        listId ?? context.read<NotesCubit>().state.selectedListId;
    final restoredFilter = widget.viewModeController.filterFor(activeListId);
    final restoredViewMode = widget.viewModeController.viewModeFor(
      activeListId,
    );
    final restoredCompletedSectionExpanded = widget.viewModeController
        .completedSectionExpandedFor(activeListId);
    _activePreferenceListId = activeListId;
    if (_filter == restoredFilter &&
        _viewMode == restoredViewMode &&
        _completedSectionExpanded == restoredCompletedSectionExpanded) {
      return;
    }
    _update(() {
      _filter = restoredFilter;
      _viewMode = restoredViewMode;
      _completedSectionExpanded = restoredCompletedSectionExpanded;
    });
  }

  void _restoreListProtectionState() {
    if (mounted) _update(() {});
  }

  void _scheduleActiveListProtectionSync(NotesState _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentState = context.read<NotesCubit>().state;
      final showsSelectedList = _scope == _BoardScope.list;
      final list = showsSelectedList ? currentState.selectedList : null;
      widget.listProtectionController.setActiveList(list?.id, name: list?.name);
    });
  }

  void _scheduleAutomaticUnlock(NoteList list) {
    if (!_automaticUnlockAttemptedListIds.add(list.id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.listProtectionController.canAccess(list.id)) {
        return;
      }
      await widget.listProtectionController.unlock(
        list.id,
        listName: list.name,
      );
    });
  }

  Future<void> _toggleListProtection() async {
    final list = context.read<NotesCubit>().state.selectedList;
    if (list == null) return;
    final wasProtected = widget.listProtectionController.isProtected(list.id);
    final result = await widget.listProtectionController.setProtection(
      list.id,
      enabled: !wasProtected,
      listName: list.name,
    );
    if (!mounted) return;
    final platform = Theme.of(context).platform;
    if (result == ListProtectionResult.success) {
      _automaticUnlockAttemptedListIds.add(list.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasProtected
                ? 'Protección biométrica desactivada.'
                : 'Lista protegida con ${listBiometricMethodLabel(platform)}.',
          ),
        ),
      );
      return;
    }
    if (result == ListProtectionResult.unavailable) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Biometría no disponible'),
          content: Text(
            '${listBiometricSetupInstruction(platform)} en los ajustes del '
            'dispositivo para proteger esta lista.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } else if (result == ListProtectionResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos comprobar tu identidad. Inténtalo nuevamente.',
          ),
        ),
      );
    }
  }

  void _changeFilter(NoteFilter value) {
    if (_filter == value &&
        _categoryFilter == null &&
        _assigneeFilterUid == null) {
      return;
    }
    _playBoardTapSound();
    _withoutNoteEntrances(
      () => _update(() {
        _filter = value;
        _categoryFilter = null;
        _assigneeFilterUid = null;
      }),
    );
    if (_scope == _BoardScope.list) {
      final listId = context.read<NotesCubit>().state.selectedListId;
      unawaited(widget.viewModeController.setFilter(listId, value));
    }
  }

  void _changeCompletedSectionExpansion(bool expanded) {
    if (_completedSectionExpanded == expanded) return;
    _playBoardTapSound();
    _update(() => _completedSectionExpanded = expanded);
    if (_scope == _BoardScope.list) {
      final listId = context.read<NotesCubit>().state.selectedListId;
      unawaited(
        widget.viewModeController.setCompletedSectionExpanded(listId, expanded),
      );
    }
  }

  void _changeCategoryFilter(NoteCategory? value) {
    if (_categoryFilter == value && _assigneeFilterUid == null) return;
    _playBoardTapSound();
    _withoutNoteEntrances(
      () => _update(() {
        _categoryFilter = value;
        _assigneeFilterUid = null;
      }),
    );
  }

  void _changeAssigneeFilter(String? uid) {
    if (_assigneeFilterUid == uid) return;
    _playBoardTapSound();
    _withoutNoteEntrances(() => _update(() => _assigneeFilterUid = uid));
  }

  void _clearFacetFilters() {
    if (_categoryFilter == null && _assigneeFilterUid == null) return;
    _playBoardTapSound();
    _withoutNoteEntrances(
      () => _update(() {
        _categoryFilter = null;
        _assigneeFilterUid = null;
      }),
    );
  }

  void _changeViewMode(BoardViewMode value) {
    if (_viewMode == value) return;
    _playBoardTapSound();
    _withoutNoteEntrances(() => _update(() => _viewMode = value));
    if (_scope == _BoardScope.list) {
      final listId = context.read<NotesCubit>().state.selectedListId;
      unawaited(widget.viewModeController.setViewMode(listId, value));
    }
  }

  void _withoutNoteEntrances(VoidCallback update) {
    _animateNoteEntrances = false;
    final epoch = ++_noteEntranceSuppressionEpoch;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (!disableAnimations) {
      _contentTransitionController.forward(from: 0);
    }
    update();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _noteEntranceSuppressionEpoch) return;
      _animateNoteEntrances = true;
      if (disableAnimations) {
        _contentTransitionController.value = 1;
      }
    });
  }

  void _openProfile() {
    final authRepository = context.read<AuthRepository>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RepositoryProvider<AuthRepository>.value(
          value: authRepository,
          child: ProfilePage(themeController: widget.themeController),
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    final controller = widget.notificationsController;
    if (controller == null) return;
    final notification = await Navigator.of(context).push<AppNotification>(
      MaterialPageRoute<AppNotification>(
        builder: (_) => NotificationsPage(controller: controller),
      ),
    );
    if (notification != null && mounted) {
      await _handleNotificationData(notification.data);
    }
  }

  Future<void> _handleNotificationData(Map<String, String> data) async {
    if (!mounted) return;
    final boardId = data['boardId'];
    if (boardId == null || boardId.isEmpty) return;
    final cubit = context.read<NotesCubit>();
    if (cubit.state.lists.isEmpty &&
        (cubit.state.status == NotesStatus.initial ||
            cubit.state.status == NotesStatus.loading)) {
      await cubit.stream
          .firstWhere(
            (state) =>
                state.status == NotesStatus.ready ||
                state.status == NotesStatus.failure,
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => cubit.state);
    }
    if (!mounted) return;
    final didOpenList = await _selectList(boardId);
    if (!didOpenList) return;
    if (!mounted) return;
    final noteId = data['noteId'];
    if (noteId == null || noteId.isEmpty) return;
    for (final note in cubit.state.notes) {
      if (note.id == noteId) {
        _openNote(note);
        return;
      }
    }
  }
}

class _RetiringSliverFadeTransition extends StatelessWidget {
  const _RetiringSliverFadeTransition({
    required this.opacity,
    required this.sliver,
    super.key,
  });

  final Animation<double> opacity;
  final Widget sliver;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: opacity,
    child: sliver,
    builder: (context, child) {
      final value = opacity.value.clamp(0.0, 1.0).toDouble();
      if (opacity.status == AnimationStatus.completed && value >= 1) {
        return child!;
      }
      return SliverOpacity(opacity: value, sliver: child!);
    },
  );
}
