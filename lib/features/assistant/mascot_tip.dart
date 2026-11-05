/// Short invitations for the floating mascot. A tap prepares an editable
/// question; displaying a bubble never reads notes or contacts the assistant.
enum MascotTip {
  firstStep(
    'Un pasito y empezamos ✨',
    'Ayúdame a encontrar un primer paso pequeño en esta vista.',
  ),
  ideas(
    '¡Tengo ganas de crear algo! 💡',
    'Dame ideas para una nueva lista. Pregúntame qué quiero organizar.',
  ),
  capture(
    'Que no se escape esa idea 💭',
    'Ayúdame a escribir una idea en una nota. Pregúntame qué tengo en mente.',
  ),
  simplify(
    '¿Lo hacemos más simple?',
    'Ayúdame a simplificar la información de esta vista.',
  ),
  celebrate(
    'Cada pasito cuenta 🌟',
    'Ayúdame a revisar lo completado y a elegir un siguiente paso pequeño.',
  ),
  tomorrow(
    'Dejemos mañana más liviano ☀️',
    'Ayúdame a preparar un plan para mañana con mis pendientes.',
  ),
  expenses(
    '¿A dónde se fue el dinero? 🔎',
    'Ayúdame a agrupar los gastos de esta vista por categoría y moneda.',
  ),
  savings(
    '¿Buscamos dónde ahorrar? 🌱',
    'Ayúdame a identificar posibles ahorros en este presupuesto sin modificar nada.',
  ),
  details(
    '¿Le damos forma a esta idea? ✏️',
    'Ayúdame a desarrollar esta nota. Pregúntame qué detalles quiero agregar.',
  ),
  explore(
    '¿Exploramos esta pantalla?',
    '¿Qué puedo hacer en esta pantalla y por dónde me conviene empezar?',
  ),
  design(
    '¿Diseñamos una lista?',
    'Ayúdame a diseñar una lista. Pregúntame qué quiero organizar.',
  ),
  priorities(
    '¿Ordenamos tus pendientes?',
    'Ayúdame a elegir por dónde empezar con los pendientes de esta lista.',
  ),
  draft(
    '¿Preparamos una nota?',
    'Quiero preparar una nota. Pregúntame qué necesito anotar.',
  ),
  movements(
    '¿Revisamos los movimientos?',
    'Ayúdame a revisar los movimientos de esta lista, separando los importes por moneda.',
  ),
  dueDates(
    '¿Vemos qué vence primero?',
    'Ayúdame a identificar las próximas fechas y los registros pendientes en esta lista.',
  ),
  today(
    '¿Planeamos tu día?',
    'Ayúdame a preparar un plan con mis pendientes de hoy.',
  ),
  three(
    '¿Elegimos tres prioridades?',
    'Ayúdame a elegir hasta tres tareas para hoy y dime por cuál empezar.',
  ),
  balance(
    '¿Revisamos tu saldo?',
    'Ayúdame a entender el gasto y el saldo de este presupuesto.',
  ),
  limit(
    '¿Probamos otro límite?',
    'Quiero simular otro límite de presupuesto sin guardar cambios. Pregúntame el monto.',
  ),
  steps(
    '¿La dividimos en pasos?',
    'Ayúdame a convertir esta nota en una lista de pasos concretos.',
  ),
  summary(
    '¿Quieres un resumen?',
    'Ayúdame a resumir lo más importante de esta vista.',
  );

  bool get usesExcerpt => switch (this) {
    explore || design || draft || ideas || capture => false,
    _ => true,
  };
  const MascotTip(this.label, this.prompt);
  final String label, prompt;
}

enum MascotTopic {
  general([
    MascotTip.explore,
    MascotTip.design,
    MascotTip.draft,
    MascotTip.ideas,
    MascotTip.capture,
  ]),
  emptyList([
    MascotTip.draft,
    MascotTip.design,
    MascotTip.ideas,
    MascotTip.capture,
  ]),
  list([
    MascotTip.priorities,
    MascotTip.draft,
    MascotTip.summary,
    MascotTip.firstStep,
    MascotTip.celebrate,
    MascotTip.simplify,
  ]),
  finance([
    MascotTip.movements,
    MascotTip.dueDates,
    MascotTip.summary,
    MascotTip.expenses,
    MascotTip.simplify,
  ]),
  today([
    MascotTip.today,
    MascotTip.three,
    MascotTip.summary,
    MascotTip.firstStep,
    MascotTip.celebrate,
    MascotTip.tomorrow,
  ]),
  budget([
    MascotTip.balance,
    MascotTip.limit,
    MascotTip.summary,
    MascotTip.savings,
    MascotTip.expenses,
  ]),
  note([
    MascotTip.steps,
    MascotTip.summary,
    MascotTip.draft,
    MascotTip.details,
    MascotTip.simplify,
  ]);

  const MascotTopic(this.tips);
  final List<MascotTip> tips;
}
