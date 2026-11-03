/// Short invitations for the floating mascot. A tap prepares an editable
/// question; displaying a bubble never reads notes or contacts the assistant.
enum MascotTip {
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
    explore || design || draft => false,
    _ => true,
  };
  const MascotTip(this.label, this.prompt);
  final String label, prompt;
}

enum MascotTopic {
  general([MascotTip.explore, MascotTip.design, MascotTip.draft]),
  emptyList([MascotTip.draft, MascotTip.design]),
  list([MascotTip.priorities, MascotTip.draft, MascotTip.summary]),
  finance([MascotTip.movements, MascotTip.dueDates, MascotTip.summary]),
  today([MascotTip.today, MascotTip.three, MascotTip.summary]),
  budget([MascotTip.balance, MascotTip.limit, MascotTip.summary]),
  note([MascotTip.steps, MascotTip.summary, MascotTip.draft]);

  const MascotTopic(this.tips);
  final List<MascotTip> tips;
}
