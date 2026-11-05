import 'dart:convert';

import 'package:nocknock/features/assistant/assistant_action_review.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/features/assistant/assistant_chat_visuals.dart';
import 'package:nocknock/features/assistant/assistant_dictation.dart';
import 'package:nocknock/features/assistant/assistant_mascot.dart';
import 'package:nocknock/features/assistant/assistant_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/features/assistant/assistant_client.dart';
import 'package:nocknock/features/assistant/assistant_excerpt.dart';
import 'package:nocknock/features/assistant/assistant_view.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_preview_dialog.dart';
import 'package:uuid/uuid.dart';

typedef _Exchange = ({String question, AssistantReply reply});
typedef AssistantViewBuilder = AssistantView Function(NotesState state);

/// Only the current account and screen's chat is kept, in memory.
class AssistantChatMemory {
  String? _scope;
  String? manualExcerpt;
  // Earlier replies can quote the view even after a one-message attachment is gone.
  String? _historyExcerpt;
  final _turns = <_Exchange>[];
  final _saved = Set<Object>.identity();
  void clear() {
    _turns.clear();
    _saved.clear();
    manualExcerpt = null;
    _historyExcerpt = null;
    _scope = null;
  }

  bool hasStaleExcerpt(String current) =>
      (manualExcerpt != null && manualExcerpt != current) ||
      (_historyExcerpt != null && _historyExcerpt != current);

  void enter(String scope, String currentExcerpt) {
    if (_scope != scope || hasStaleExcerpt(currentExcerpt)) {
      clear();
    }
    _scope = scope;
  }

  static const maxMessages = 20;

  void remember(String question, AssistantReply reply) {
    _turns.add((question: question, reply: reply));
    while (_turns.length * 2 > maxMessages) {
      final removed = _turns.removeAt(0);
      _saved.remove(removed.reply);
    }
  }

  String? get history {
    if (_turns.isEmpty) return null;
    // Keep every retained message in context; bound unusually long responses
    // individually so they cannot crowd older messages out of the window.
    String bounded(String text, int limit) =>
        String.fromCharCodes(text.runes.take(limit));
    return _turns
        .map(
          (turn) =>
              'Usuario: ${bounded(turn.question, 2000)}\nNocky: ${bounded(turn.reply.plainText, 5000)}',
        )
        .join('\n\n');
  }
}

class AssistantPage extends StatelessWidget {
  const AssistantPage({
    super.key,
    required this.auth,
    required this.userId,
    required this.cubit,
    required this.protection,
    required this.listId,
    this.noteId,
    this.viewBuilder,
    this.compose,
    this.initialPrompt = '',
    this.initialUsesExcerpt = false,
    this.memory,
    this.onReviewList,
    this.createClient,
    this.pickReceipt,
  });
  final AuthRepository auth;
  final String userId;
  final NotesCubit cubit;
  final ListProtectionController protection;
  final String? listId, noteId;
  final AssistantViewBuilder? viewBuilder;
  final AssistantMode? compose;
  final String initialPrompt;
  final bool initialUsesExcerpt;
  final AssistantChatMemory? memory;
  final Future<bool> Function(AssistantListDraft)? onReviewList;
  final AssistantClient Function()? createClient;
  final Future<List<NoteAttachment>> Function(BuildContext)? pickReceipt;

  AssistantView _view(NotesState state) {
    if (viewBuilder != null) return viewBuilder!(state);
    final list = assistantList(state, listId, protection);
    if (list != null) return AssistantView.list(list, state);
    return const AssistantView(
      'general',
      'NockNock',
      'Ayuda con la app',
      '¿Cómo comparto una lista y asigno tareas?',
    );
  }

  bool _writable(NoteList l) =>
      !l.isFinancial &&
      l.canEdit &&
      !l.isEncryptionKeyPending &&
      !protection.isProtected(l.id);
  Future<bool> _reviewNote(
    BuildContext page,
    AssistantDraft draft,
    bool Function() current,
  ) async {
    final choices = cubit.state.lists.where(_writable).toList();
    var target = choices.where((l) => l.id == listId).firstOrNull;
    target ??= await showDialog<NoteList>(
      context: page,
      builder: (c) => SimpleDialog(
        title: const Text('¿Dónde guardar la nota?'),
        children: [
          for (final list in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, list),
              child: Text(list.name),
            ),
        ],
      ),
    );
    final id = target?.id;
    NoteList? destination() =>
        cubit.state.lists.where((l) => l.id == id && _writable(l)).firstOrNull;
    if (!page.mounted || !current() || destination() == null) return false;
    final author = auth.currentUser!.displayName, now = DateTime.now();
    final reviewed = await showCreateNoteDialog(
      context: page,
      defaultAuthorName: author,
      showAuthorField: false,
      assignees: destination()!.collaborators,
      initialNote: Note(
        id: 'assistant-draft',
        boardId: id!,
        title: draft.title,
        content: draft.content,
        color: NoteColor.yellow,
        authorName: author,
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        createdAt: now,
        updatedAt: now,
        checklist: [
          for (final text in draft.checklist)
            NoteChecklistItem(id: const Uuid().v4(), text: text),
        ],
      ),
    );
    if (reviewed == null ||
        !page.mounted ||
        !current() ||
        destination() == null) {
      return false;
    }
    await cubit.createCapturedNote(id, reviewed);
    return true;
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const AmbientPageBackground(),
      SafeArea(
        bottom: false,
        child: StreamBuilder<AppUser?>(
          stream: auth.authStateChanges,
          initialData: auth.currentUser,
          builder: (context, _) {
            if (auth.currentUser?.id != userId) {
              memory?.clear();
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(
                  child: Stack(
                    children: [
                      const Center(
                        child: Text(
                          'Tu sesión cambió. Vuelve a abrir el asistente.',
                        ),
                      ),
                      const Align(
                        alignment: Alignment.topRight,
                        child: _CloseChatButton(),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListenableBuilder(
              listenable: protection,
              builder: (context, _) => BlocBuilder<NotesCubit, NotesState>(
                bloc: cubit,
                builder: (context, state) {
                  final view = _view(state),
                      scope = '$userId/${view.key}/${compose?.name ?? "chat"}';
                  final currentList = assistantList(state, listId, protection);
                  bool current() =>
                      !cubit.isClosed &&
                      auth.currentUser?.id == userId &&
                      _view(cubit.state).key == view.key;
                  return _Chat(
                    key: ValueKey(scope),
                    scope: scope,
                    view: view,
                    compose: compose,
                    initialPrompt: initialPrompt,
                    initialUsesExcerpt:
                        initialUsesExcerpt && view.excerpt.isNotEmpty,
                    memory: memory,
                    createClient: createClient,
                    pickReceipt: pickReceipt,
                    current: current,
                    liveExcerpt: () => _view(cubit.state).excerpt,
                    getToken: auth.getIdToken,
                    noteLabel: currentList != null && _writable(currentList)
                        ? 'Revisar nota en «${currentList.name}»'
                        : 'Elegir lista para la nota',
                    reviewNote: state.lists.any(_writable)
                        ? (page, draft) => _reviewNote(page, draft, current)
                        : null,
                    reviewList: onReviewList,
                    actions: AssistantActionReview(
                      cubit: cubit,
                      protection: protection,
                      current: current,
                      listId: listId,
                      noteId: noteId,
                      author: auth.currentUser!.displayName,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _CloseChatButton extends StatelessWidget {
  const _CloseChatButton();
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Cerrar chat',
    icon: const Icon(Icons.close_rounded),
    onPressed: () => Navigator.maybePop(context),
  );
}

class _Chat extends StatefulWidget {
  const _Chat({
    super.key,
    required this.scope,
    required this.view,
    required this.compose,
    required this.initialPrompt,
    required this.initialUsesExcerpt,
    required this.memory,
    required this.current,
    required this.liveExcerpt,
    required this.getToken,
    required this.createClient,
    required this.pickReceipt,
    required this.noteLabel,
    required this.reviewNote,
    required this.reviewList,
    required this.actions,
  });
  final AssistantActionReview actions;
  final String scope, initialPrompt, noteLabel;
  final bool initialUsesExcerpt;
  final AssistantView view;
  final AssistantMode? compose;
  final AssistantChatMemory? memory;
  final bool Function() current;
  final String Function() liveExcerpt;
  final Future<String?> Function() getToken;
  final AssistantClient Function()? createClient;
  final Future<List<NoteAttachment>> Function(BuildContext)? pickReceipt;
  final Future<bool> Function(BuildContext, AssistantDraft)? reviewNote;
  final Future<bool> Function(AssistantListDraft)? reviewList;
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> with WidgetsBindingObserver {
  late final _client = widget.createClient?.call() ?? AssistantClient();
  late final _memory = widget.memory ?? AssistantChatMemory();
  late final _question = TextEditingController(text: widget.initialPrompt);
  late AssistantMode _mode = widget.compose ?? AssistantMode.chat;
  final _scroll = ScrollController();
  final _excerptPreview = ExpansibleController();
  final _focus = FocusNode();
  late final _voice = AssistantDictation(_question);
  Set<Object> get _saved => _memory._saved;
  String? _sending, _error;
  bool _suggestionUsesExcerpt = false;
  String? get _attachedExcerpt =>
      _memory.manualExcerpt ??
      (_suggestionUsesExcerpt && widget.view.excerpt.isNotEmpty
          ? widget.view.excerpt
          : null);
  NoteAttachment? _receipt;
  bool _picking = false;
  bool _reviewing = false;
  bool get _busy => _sending != null || _reviewing || _picking || _voice.active;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice.addListener(_refresh);
    _focus.addListener(_refresh);
    _memory.enter(widget.scope, widget.view.excerpt);
    _suggestionUsesExcerpt = widget.initialUsesExcerpt;
    if (_memory._turns.isNotEmpty) _toBottom();
  }

  @override
  void didUpdateWidget(_Chat old) {
    super.didUpdateWidget(old);
    if (_memory.hasStaleExcerpt(widget.view.excerpt)) {
      final wasSuggested = _suggestionUsesExcerpt;
      _reset();
      _suggestionUsesExcerpt = wasSuggested;
      _error =
          'La vista cambió. Revisa el contexto actualizado antes de enviar.';
    }
  }

  void _refresh() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _voice.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _voice.cancel();
    }
  }

  void _reset() {
    _receipt = null;
    _voice.cancel();
    _voice.error = null;
    _memory.clear();
    _memory.enter(widget.scope, widget.view.excerpt);
    _saved.clear();
    _error = null;
    _suggestionUsesExcerpt = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_refresh);
    _voice.dispose();
    _focus.removeListener(_refresh);
    _focus.dispose();
    _client.close();
    _question.dispose();
    _scroll.dispose();
    _excerptPreview.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        return;
      }
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  });

  void _pickIdea(ChatIdea idea) {
    setState(() {
      _mode = widget.compose ?? AssistantMode.chat;
      _suggestionUsesExcerpt = idea.usesExcerpt;
      _voice.error = null;
      _error = null;
      _question.value = TextEditingValue(
        text: idea.prompt,
        selection: TextSelection.collapsed(offset: idea.prompt.length),
      );
    });
  }

  Future<void> _attachReceipt() async {
    if (_busy || !widget.current()) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final selected =
          await (widget.pickReceipt?.call(context) ??
              pickNoteAttachments(
                context: context,
                remaining: 1,
                includeCamera: true,
                imagesOnly: true,
              ));
      if (mounted && widget.current() && selected.isNotEmpty) {
        setState(() {
          _receipt = selected.single;
          _mode = AssistantMode.chat;
        });
      }
    } on NoteAttachmentPickFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo abrir la foto. Revisa el acceso a la cámara o a tus fotos.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _ask() async {
    final receipt = _receipt;
    final typed = _question.text.trim();
    final q = typed.isEmpty && receipt != null
        ? 'Lee esta boleta y propón registrar el gasto y una lista donde guardarlo.'
        : typed;
    if (_busy || !widget.current()) return;
    if (q.isEmpty) {
      setState(() => _error = 'Escribe una pregunta para Nocky.');
      return;
    }
    final excerpt = _attachedExcerpt;
    final source = excerpt ?? _memory._historyExcerpt;
    bool sourceIsCurrent() => source == null || widget.liveExcerpt() == source;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sending = q;
      _voice.error = null;
      _error = null;
    });
    _toBottom();
    try {
      final token = await widget.getToken();
      if (!mounted || !widget.current()) return;
      if (token == null || token.isEmpty) {
        throw const AssistantFailure('Inicia sesión para hablar con Nocky.');
      }
      if (!sourceIsCurrent() || _attachedExcerpt != excerpt) {
        throw const AssistantFailure(
          'El extracto cambió. Revísalo antes de enviar.',
        );
      }
      final reply = await _client.ask(
        token: token,
        question: q,
        mode: _mode,
        excerpt: excerpt,
        previousExchange: _memory.history,
        screen: widget.view.key.split('/').first,
        receipt: receipt,
      );
      if (!mounted || !widget.current() || !sourceIsCurrent()) {
        return;
      }
      setState(() {
        if (excerpt != null) _memory._historyExcerpt = excerpt;
        _memory.remember(q, reply);
        _question.clear();
        if (reply.expenses.isNotEmpty ||
            reply.listDraft != null ||
            reply.draft != null ||
            reply.edit != null) {
          _receipt = null;
        }
        _suggestionUsesExcerpt = false;
      });
      _toBottom();
    } on AssistantFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No pudimos conectar. Puedes reintentar tu mensaje.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _apply(
    Object key,
    Future<bool> Function() review,
    String success,
  ) async {
    if (_busy || _saved.contains(key) || !widget.current()) return;
    setState(() {
      _reviewing = true;
      _error = null;
    });
    try {
      final saved = await review();
      if (mounted && saved && widget.current()) {
        setState(() => _saved.add(key));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = e is AssistantFailure ? e.message : notesErrorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _review(AssistantReply reply) async {
    if (_busy || !widget.current()) return;
    if (widget.compose != null) {
      Navigator.of(context).pop(reply);
      return;
    }
    await _apply(
      reply,
      () => reply.listDraft != null
          ? widget.reviewList!(reply.listDraft!)
          : widget.reviewNote!(context, reply.draft!),
      reply.listDraft != null ? 'Lista creada.' : 'Nota guardada.',
    );
  }

  Widget? _action(AssistantReply r) {
    if (r.edit case final edit?) {
      return FilledButton.tonalIcon(
        onPressed: _busy || _saved.contains(edit)
            ? null
            : () => _apply(
                edit,
                () => widget.actions.edit(context, edit),
                'Cambios guardados.',
              ),
        icon: const Icon(Icons.edit_note),
        label: Text(
          _saved.contains(edit) ? 'Nota actualizada' : 'Revisar cambios',
        ),
      );
    }
    if (r.expenses.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final expense in r.expenses)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lista sugerida: ${expense.suggestedList}'),
                  if (expense.date == null)
                    const Text(
                      'Sin fecha indicada. Puedes elegirla en el editor.',
                    ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    onPressed: _busy || _saved.contains(expense)
                        ? null
                        : () => _apply(
                            expense,
                            () => widget.actions.expense(
                              context,
                              expense,
                              r.receipt,
                            ),
                            'Gasto guardado.',
                          ),
                    label: Text(
                      _saved.contains(expense)
                          ? 'Gasto guardado'
                          : r.expenses.length == 1
                          ? 'Revisar gasto'
                          : 'Revisar · ${expense.title}',
                    ),
                  ),
                  if (!_saved.contains(expense.createListAction) &&
                      widget.actions.matchingExpenseList(expense) == null)
                    TextButton.icon(
                      icon: const Icon(Icons.playlist_add_rounded),
                      onPressed: _busy
                          ? null
                          : () => _apply(
                              expense.createListAction,
                              () async =>
                                  await widget.actions.createSuggestedList(
                                    context,
                                    expense,
                                  ) !=
                                  null,
                              'Lista de gastos disponible.',
                            ),
                      label: Text('Crear lista «${expense.suggestedList}»'),
                    ),
                ],
              ),
            ),
        ],
      );
    }
    final isList = r.listDraft != null;
    if (r.draft == null && !isList) return null;
    final enabled =
        widget.compose != null ||
        (isList ? widget.reviewList != null : widget.reviewNote != null);
    if (!enabled) return null;
    return FilledButton.tonalIcon(
      onPressed: _busy || _saved.contains(r) ? null : () => _review(r),
      icon: const Icon(Icons.edit_note),
      label: Text(
        widget.compose != null
            ? 'Usar propuesta'
            : _saved.contains(r)
            ? (isList ? 'Lista creada' : 'Nota guardada')
            : isList
            ? 'Revisar lista'
            : widget.noteLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final available =
          (bounds.maxHeight - keyboard - MediaQuery.paddingOf(context).bottom)
              .clamp(0.0, bounds.maxHeight);
      final compact = available < 330;
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _heading(context, compact: compact),
                // Scaffold supplies the measured bar height (including the safe
                // area and keyboard) as bottom padding inside this builder.
                Expanded(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) {
                      final fade = bounds.height > 0
                          ? (28 / bounds.height).clamp(0.0, 1.0)
                          : 0.0;
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                        ],
                        stops: [0, fade, 1],
                      ).createShader(bounds);
                    },
                    child: Builder(builder: _conversation),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 660,
                  maxHeight: available * .65,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChatIdeas(
                      view: widget.view,
                      compact: compact,
                      onSelect: _busy ? null : _pickIdea,
                    ),
                    Flexible(child: _composer(context, compact: compact)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _conversation(BuildContext context) {
    final v = widget.view,
        composing = widget.compose != null,
        turns = _memory._turns;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      children: [
        if (v.excerpt.isNotEmpty)
          ChatGlass(
            accent: colors.tertiaryContainer,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    v.key.startsWith('list/')
                        ? 'Incluir extracto de la lista'
                        : 'Incluir extracto de esta vista',
                  ),
                  value: _attachedExcerpt != null,
                  onChanged: _busy ? null : _setExcerptIncluded,
                ),
                if (_attachedExcerpt case final excerpt?)
                  ExpansionTile(
                    controller: _excerptPreview,
                    initiallyExpanded: true,
                    title: const Text('Texto que se enviará'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: SingleChildScrollView(
                          child: SelectableText(excerpt),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (turns.isEmpty) ...[
          ChatMessageBubble(
            composing
                ? (widget.compose == AssistantMode.list
                      ? 'Cuéntame para qué necesitas la lista. Te propondré un nombre y una configuración.'
                      : '¿Qué quieres anotar? Puedo darte un título, una descripción y subtareas.')
                : v.greeting,
          ),
        ],
        for (final turn in turns) ...[
          ChatMessageBubble(
            turn.question,
            mine: true,
            key: ValueKey((turn.reply, true)),
          ),
          ChatMessageBubble(
            turn.reply.plainText,
            action: _action(turn.reply),
            key: ObjectKey(turn.reply),
          ),
        ],
        if (_sending case final q?) ...[
          ChatMessageBubble(q, mine: true),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: ChatActivity(),
          ),
        ],
      ],
    );
  }

  Widget _heading(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final v = widget.view;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, compact ? 0 : 12, 10, compact ? 0 : 6),
      child: Row(
        children: [
          NockFace(size: compact ? 34 : 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!compact)
                  Text(
                    'Nocky · Asistente de NockNock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  v.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!compact && v.detail.isNotEmpty)
                  Text(
                    v.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (_memory._turns.isNotEmpty)
            IconButton(
              tooltip: 'Nueva consulta',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _reset();
                      _question.clear();
                    }),
              icon: const Icon(Icons.add_comment_outlined),
            ),
          const _CloseChatButton(),
        ],
      ),
    );
  }

  void _setExcerptIncluded(bool include) {
    setState(() {
      if (!include && _memory.manualExcerpt == null) {
        _suggestionUsesExcerpt = false;
        return;
      }
      // Changing the shared context starts a fresh history. The selected
      // receipt belongs to the current draft and is independent of the excerpt.
      final receipt = _receipt;
      _reset();
      _receipt = receipt;
      _memory.manualExcerpt = include ? widget.view.excerpt : null;
    });
  }

  void _setMode(AssistantMode mode) {
    if (_mode == mode || _busy) return;
    setState(() {
      _mode = mode;
      if (mode != AssistantMode.chat) _receipt = null;
      _suggestionUsesExcerpt = false;
    });
  }

  static const _toolsMenuStyle = MenuStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
  );

  Widget _composerTools() {
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: _toolsMenuStyle,
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_a_photo_outlined),
          onPressed: _busy ? null : _attachReceipt,
          child: const Text('Adjuntar boleta'),
        ),
        const Divider(height: 9),
        for (final mode in AssistantMode.values)
          MenuItemButton(
            leadingIcon: Icon(switch (mode) {
              AssistantMode.chat => Icons.chat_bubble_outline_rounded,
              AssistantMode.draft => Icons.edit_note_rounded,
              AssistantMode.list => Icons.checklist_rounded,
            }),
            trailingIcon: _mode == mode
                ? Icon(Icons.check_rounded, color: colors.primary)
                : null,
            onPressed: _busy ? null : () => _setMode(mode),
            child: Text(switch (mode) {
              AssistantMode.chat => 'Chat',
              AssistantMode.draft => 'Crear borrador',
              AssistantMode.list => 'Crear lista',
            }),
          ),
      ],
      builder: (context, menu, _) {
        void toggle() => menu.isOpen ? menu.close() : menu.open();
        if (_mode != AssistantMode.chat) {
          return TextButton.icon(
            onPressed: _busy ? null : toggle,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: Text(_mode == AssistantMode.list ? 'Lista' : 'Borrador'),
          );
        }
        return IconButton(
          tooltip: 'Más opciones',
          onPressed: _busy ? null : toggle,
          icon: const Icon(Icons.add_rounded),
        );
      },
    );
  }

  void _previewReceipt(NoteAttachment photo) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Boleta que se enviará'),
      content: Image.memory(
        base64Decode(photo.dataBase64!),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Text('Vista previa no disponible para este formato.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  Widget _composerAttachments(BuildContext context) {
    final photo = _receipt;
    final excerpt = _attachedExcerpt != null;
    if (photo == null && !excerpt) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    void removeExcerpt() => _setExcerptIncluded(false);
    void previewExcerpt() {
      _focus.unfocus();
      _excerptPreview.expand();
      if (!_scroll.hasClients) return;
      final top = _scroll.position.minScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(top);
      } else {
        _scroll.animateTo(
          top,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }

    if (photo != null && excerpt) {
      return MenuAnchor(
        style: _toolsMenuStyle,
        consumeOutsideTap: true,
        menuChildren: [
          MenuItemButton(
            onPressed: () => _previewReceipt(photo),
            child: const Text('Ver boleta'),
          ),
          MenuItemButton(
            onPressed: () => setState(() => _receipt = null),
            child: const Text('Quitar boleta'),
          ),
          MenuItemButton(
            onPressed: previewExcerpt,
            child: const Text('Ver extracto'),
          ),
          MenuItemButton(
            onPressed: removeExcerpt,
            child: const Text('Quitar extracto'),
          ),
        ],
        builder: (_, menu, _) => TextButton.icon(
          onPressed: _busy
              ? null
              : () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.attach_file_rounded, size: 16),
          label: const Text(
            '2 adjuntos',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    final isPhoto = photo != null;
    return InputChip(
      avatar: Icon(
        isPhoto ? Icons.receipt_long_outlined : Icons.attach_file_rounded,
        size: 15,
      ),
      label: Text(
        isPhoto ? 'Boleta adjunta' : 'Extracto adjunto',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: colors.onSurfaceVariant),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      backgroundColor: colors.onSurface.withValues(alpha: .055),
      shape: const StadiumBorder(),
      side: BorderSide.none,
      deleteIcon: const Icon(Icons.close_rounded, size: 15),
      deleteButtonTooltipMessage: isPhoto ? 'Quitar boleta' : 'Quitar extracto',
      onPressed: _busy
          ? null
          : isPhoto
          ? () => _previewReceipt(photo)
          : previewExcerpt,
      onDeleted: _busy
          ? null
          : isPhoto
          ? () => setState(() => _receipt = null)
          : removeExcerpt,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _composer(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final voiceActive = _voice.active;
    final error = _error ?? _voice.error;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final microphoneLabel = switch (_voice.phase) {
      DictationPhase.idle => 'Dictar mensaje',
      DictationPhase.preparing => 'Cancelar dictado',
      DictationPhase.listening => 'Terminar dictado',
      DictationPhase.finishing => 'Terminando dictado',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, compact ? 4 : 10),
      child: ChatGlass(
        key: const ValueKey('assistant-floating-composer'),
        frosted: true,
        highlighted: _focus.hasFocus || voiceActive,
        radius: BorderRadius.circular(26),
        child: SingleChildScrollView(
          primary: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _question,
                  focusNode: _focus,
                  enabled: _sending == null && !_reviewing,
                  readOnly: voiceActive,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: compact ? 1 : 3,
                  maxLength: AssistantDictation.maxLength,
                  onChanged: (text) {
                    if (_voice.error != null ||
                        _error != null ||
                        (_suggestionUsesExcerpt && text.trim().isEmpty)) {
                      setState(() {
                        _voice.error = null;
                        _error = null;
                        if (text.trim().isEmpty) _suggestionUsesExcerpt = false;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(
                      10,
                      compact ? 5 : 10,
                      10,
                      compact ? 7 : 12,
                    ),
                    hintText: voiceActive
                        ? 'Tu dictado…'
                        : switch (_mode) {
                            AssistantMode.list => 'Describe tu lista…',
                            AssistantMode.draft => 'Describe tu nota…',
                            AssistantMode.chat =>
                              _memory._turns.isEmpty
                                  ? 'Tu consulta'
                                  : 'Responder…',
                          },
                  ),
                ),
                Row(
                  children: [
                    if (widget.compose == null) _composerTools(),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _composerAttachments(context),
                      ),
                    ),
                    IconButton(
                      tooltip: microphoneLabel,
                      onPressed:
                          _sending != null ||
                              _reviewing ||
                              _picking ||
                              _voice.phase == DictationPhase.finishing
                          ? null
                          : () {
                              if (voiceActive) {
                                _voice.stop();
                              } else {
                                setState(() => _error = null);
                                _focus.unfocus();
                                _voice.start(
                                  View.of(context).platformDispatcher.locale,
                                );
                              }
                            },
                      color: voiceActive
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      icon: AnimatedSwitcher(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: Icon(
                          voiceActive
                              ? Icons.stop_rounded
                              : Icons.mic_none_rounded,
                          key: ValueKey(voiceActive),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _question,
                      builder: (context, draft, _) {
                        final ready =
                            !_busy &&
                            (draft.text.trim().isNotEmpty || _receipt != null);
                        return IconButton.filled(
                          tooltip: 'Enviar',
                          onPressed: ready ? _ask : null,
                          icon: AnimatedScale(
                            scale: ready ? 1 : .86,
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: const Icon(Icons.rocket_launch_rounded),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (voiceActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(5, 5, 5, 2),
                    child: _voice.phase == DictationPhase.listening
                        ? const ChatActivity(voice: true)
                        : Text(
                            _voice.phase == DictationPhase.preparing
                                ? 'Preparando el micrófono…'
                                : 'Terminando el dictado…',
                            style: theme.textTheme.labelMedium,
                          ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(5, 4, 5, 2),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
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
