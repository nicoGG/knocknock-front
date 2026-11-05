import 'package:flutter/material.dart';
import 'package:nocknock/features/assistant/assistant_view.dart';
import 'package:nocknock/features/finance/list_configuration.dart';

class ChatIdea {
  const ChatIdea(
    this.label,
    this.icon,
    this.prompt, {
    this.usesExcerpt = false,
  });
  final String label, prompt;
  final IconData icon;
  final bool usesExcerpt;

  static List<ChatIdea> forView(AssistantView view) {
    final screen = view.key.split('/').first;
    final hasData = view.excerpt.isNotEmpty;
    const designList = ChatIdea(
      'Diseñar una lista',
      Icons.playlist_add_rounded,
      'Ayúdame a diseñar una lista. Pregúntame primero qué quiero organizar.',
    );
    const planNote = ChatIdea(
      'Preparar una nota',
      Icons.edit_note_rounded,
      'Ayúdame a crear una nota. Pregúntame qué quiero anotar antes de preparar el borrador.',
    );
    const weeklyPlan = ChatIdea(
      'Plan semanal',
      Icons.calendar_view_week_outlined,
      'Ayúdame a organizar la semana. Pregúntame mis compromisos, prioridades y el tiempo disponible antes de proponer un plan.',
    );
    const shopping = ChatIdea(
      'Compras pendientes',
      Icons.shopping_basket_outlined,
      'Ayúdame a preparar una nota de compras con subtareas. Pregúntame qué necesito comprar y para cuántas personas.',
    );
    const reminder = ChatIdea(
      'Un recordatorio',
      Icons.notifications_active_outlined,
      'Quiero preparar una nota con un recordatorio. Pregúntame qué debo recordar, la fecha y la hora; muéstrame el borrador antes de guardarlo.',
    );
    if (screen == 'createList') {
      return const [
        ChatIdea(
          'Lista de compras',
          Icons.shopping_basket_outlined,
          'Crea una lista para organizar las compras de la casa.',
        ),
        ChatIdea(
          'Gastos del mes',
          Icons.savings_outlined,
          'Propón una lista de gastos del mes en pesos chilenos.',
        ),
        ChatIdea(
          'Preparar un viaje',
          Icons.luggage_outlined,
          'Diseña una lista de pendientes para preparar un viaje.',
        ),
        ChatIdea(
          'Proyecto en equipo',
          Icons.group_work_outlined,
          'Crea una lista para coordinar las tareas de un proyecto en equipo.',
        ),
        ChatIdea(
          'Rutinas del hogar',
          Icons.home_outlined,
          'Diseña una lista para organizar las tareas del hogar. Pregúntame qué tareas hay y quiénes participan.',
        ),
        ChatIdea(
          'Plan de estudio',
          Icons.school_outlined,
          'Ayúdame a diseñar una lista para estudiar. Pregúntame la materia, mi objetivo y la fecha límite.',
        ),
        ChatIdea(
          'Organizar evento',
          Icons.celebration_outlined,
          'Propón una lista para organizar un evento. Pregúntame el tipo de evento, la fecha y cuántas personas asistirán.',
        ),
        ChatIdea(
          'Metas personales',
          Icons.flag_outlined,
          'Ayúdame a organizar mis metas en una lista con pasos concretos. Pregúntame cuáles son y qué plazo tengo.',
        ),
      ];
    }
    if (screen == 'createNote') {
      return const [
        ChatIdea(
          'Lista de pasos',
          Icons.checklist_rounded,
          'Ayúdame a convertir una tarea en una nota con pasos. Pregúntame primero cuál es la tarea.',
        ),
        ChatIdea(
          'Preparar reunión',
          Icons.groups_outlined,
          'Prepara una nota con una agenda breve y espacio para los acuerdos de una reunión.',
        ),
        ChatIdea(
          'Plan de la semana',
          Icons.date_range_outlined,
          'Prepara una nota para organizar mis prioridades de esta semana.',
        ),
        ChatIdea(
          'Anotar una idea',
          Icons.lightbulb_outline_rounded,
          'Ayúdame a escribir una nota a partir de una idea. Pregúntame de qué se trata.',
        ),
        shopping,
        reminder,
        ChatIdea(
          'Preparar viaje',
          Icons.luggage_outlined,
          'Prepara un borrador de nota con los pendientes para un viaje. Pregúntame el destino, la duración y la fecha.',
        ),
        ChatIdea(
          'Guardar acuerdos',
          Icons.handshake_outlined,
          'Ayúdame a convertir los acuerdos de una conversación en una nota con responsables y próximos pasos. Pregúntame cuáles fueron los acuerdos.',
        ),
      ];
    }

    final finance =
        view.listType != null && view.listType != NoteListType.normal;
    return [
      if (view.question.isNotEmpty && (hasData || screen == 'general'))
        ChatIdea(
          view.suggestion,
          Icons.auto_awesome_rounded,
          view.question,
          usesExcerpt: hasData,
        ),
      if (finance && hasData) ...[
        ChatIdea(
          switch (view.listType) {
            NoteListType.expenses => 'Comparar gastos',
            NoteListType.quotations => 'Comparar ofertas',
            NoteListType.receivables => 'Comparar cobros',
            _ => 'Comparar montos',
          },
          Icons.bar_chart_rounded,
          'Compara los importes más altos del extracto dentro de cada moneda. Indica qué registros explican la diferencia.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Revisar pendientes',
          Icons.pending_actions_rounded,
          'Identifica los registros pendientes en el extracto y explica qué revisar primero. Separa los saldos por moneda cuando estén disponibles.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Ver vencimientos',
          Icons.event_available_outlined,
          'Ordena por fecha los vencimientos o vigencias que figuren en el extracto. Separa los registros sin fecha.',
          usesExcerpt: true,
        ),
      ] else if (screen == 'budget') ...[
        const ChatIdea(
          'Ver disponible',
          Icons.account_balance_wallet_outlined,
          'Explica cuánto queda del presupuesto a partir del gasto y del límite guardado. Si no hay un límite, indícalo.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Probar otro límite',
          Icons.tune_rounded,
          'Ayúdame a simular otro límite. Pregúntame el monto y compara el saldo con el presupuesto actual sin guardar cambios.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Planificar gastos',
          Icons.calendar_month_outlined,
          'Con este presupuesto, sugiere cómo repartir el saldo disponible en los gastos que faltan. Pregúntame cuáles son.',
          usesExcerpt: true,
        ),
      ] else if (screen == 'today' && hasData) ...[
        const ChatIdea(
          'Elegir tres tareas',
          Icons.filter_3_outlined,
          'Elige hasta tres pendientes del extracto para hoy y explica por qué empezar por ellos.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Qué puede esperar',
          Icons.snooze_outlined,
          'Separa lo urgente de aquello que podría esperar según los recordatorios visibles.',
          usesExcerpt: true,
        ),
      ] else if (hasData) ...[
        const ChatIdea(
          'Siguiente paso',
          Icons.near_me_outlined,
          'Propón una acción concreta para avanzar con lo que aparece en el extracto.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Armar un checklist',
          Icons.checklist_rounded,
          'Convierte los pendientes del extracto en un borrador de nota con subtareas, respetando lo que ya está completado.',
          usesExcerpt: true,
        ),
      ],
      if (hasData) ...[
        const ChatIdea(
          'Detectar faltantes',
          Icons.fact_check_outlined,
          'Revisa el extracto e identifica información que falta para poder avanzar. Distingue lo confirmado de lo que debes preguntarme.',
          usesExcerpt: true,
        ),
        const ChatIdea(
          'Preguntas clave',
          Icons.help_outline_rounded,
          'A partir del extracto, sugiere tres preguntas concretas que ayuden a aclarar los próximos pasos, sin inventar datos.',
          usesExcerpt: true,
        ),
      ],
      if (hasData)
        const ChatIdea(
          'Resumir',
          Icons.short_text_rounded,
          'Resume el extracto de esta pantalla en tres puntos y señala el siguiente paso.',
          usesExcerpt: true,
        ),
      if (screen == 'list' && !finance && hasData)
        ChatIdea(
          'Editar una nota',
          Icons.edit_note_rounded,
          view.key.contains('/note/')
              ? 'Quiero editar esta nota. Pregúntame qué cambio quiero hacer.'
              : 'Quiero editar una nota de esta lista. Pregúntame cuál y qué cambio quiero hacer.',
          usesExcerpt: true,
        ),
      if (finance || screen == 'general')
        const ChatIdea(
          'Registrar un gasto',
          Icons.receipt_long_outlined,
          'Quiero registrar un gasto. Pregúntame el concepto, el monto y la moneda.',
        ),
      if (finance)
        const ChatIdea(
          'Preparar preguntas',
          Icons.question_answer_outlined,
          'Ayúdame a preparar preguntas para aclarar un gasto, una cotización o un cobro. Pregúntame qué registro quiero revisar y no supongas información que no te he dado.',
        ),
      if (finance)
        const ChatIdea(
          'Organizar registros',
          Icons.folder_open_rounded,
          '¿Cómo puedo organizar los registros de una lista financiera para que después sea más fácil revisarlos?',
        ),
      if (!finance && screen != 'budget') ...[
        planNote,
        reminder,
        shopping,
        weeklyPlan,
      ],
      if (!hasData || screen == 'today') designList,
      if (!hasData)
        const ChatIdea(
          'Ordenar prioridades',
          Icons.low_priority_rounded,
          'Ayúdame a priorizar tareas. Pregúntame cuáles son y qué plazos tengo.',
        ),
    ];
  }
}

class ChatIdeas extends StatefulWidget {
  const ChatIdeas({
    super.key,
    required this.view,
    required this.onSelect,
    this.collapsible = true,
    this.compact = false,
  });
  final AssistantView view;
  final ValueChanged<ChatIdea>? onSelect;
  final bool collapsible;
  final bool compact;

  @override
  State<ChatIdeas> createState() => _ChatIdeasState();
}

class _ChatIdeasState extends State<ChatIdeas> {
  bool? _expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final ideas = ChatIdea.forView(widget.view);
    final accents = [colors.primary, colors.tertiary, colors.secondary];
    final expanded = _expanded ?? !widget.compact;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const ValueKey('assistant-ideas-toggle'),
          borderRadius: BorderRadius.circular(16),
          onTap: widget.collapsible
              ? () => setState(() => _expanded = !expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ideas para esta vista',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.collapsible)
                  Icon(
                    expanded
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
              ],
            ),
          ),
        ),
        if (expanded)
          SizedBox(
            height: 52 * scale,
            child: ListView.separated(
              key: const ValueKey('assistant-ideas-carousel'),
              primary: false,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              itemCount: ideas.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => SizedBox(
                width: 168 * scale,
                child: _IdeaChip(
                  idea: ideas[i],
                  color: accents[i % accents.length],
                  primary: i == 0,
                  onTap: widget.onSelect == null
                      ? null
                      : () => widget.onSelect!(ideas[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IdeaChip extends StatelessWidget {
  const _IdeaChip({
    required this.idea,
    required this.color,
    required this.primary,
    required this.onTap,
  });
  final ChatIdea idea;
  final Color color;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final radius = BorderRadius.circular(14);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  color.withValues(alpha: primary ? .22 : .12),
                  colors.surfaceContainerHigh,
                ),
                colors.surface.withValues(alpha: dark ? .78 : .9),
              ],
            ),
            border: Border.all(
              color: primary
                  ? color.withValues(alpha: .52)
                  : colors.outlineVariant.withValues(alpha: .78),
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(idea.icon, color: color, size: 16),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        idea.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: primary
                              ? FontWeight.w800
                              : FontWeight.w600,
                          height: 1.18,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
