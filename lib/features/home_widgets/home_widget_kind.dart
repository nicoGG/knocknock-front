/// Android launcher options. The launcher can resize each variant after pinning.
enum HomeWidgetKind {
  capture('Captura rápida', '1 × 1', 'Un toque para guardar una nota.'),
  summary(
    'Resumen compacto',
    '2 × 2',
    'El estado de tu lista en poco espacio.',
  ),
  upcoming(
    'Próximas tareas',
    '4 × 2',
    'Solo pendientes, en una tarjeta horizontal.',
  ),
  list('Lista', '4 × 3', 'Casillas, tareas y acceso para crear notas.'),
  expanded('Lista ampliada', '4 × 5', 'Más tareas y subtareas a la vista.');

  const HomeWidgetKind(this.label, this.sizeLabel, this.description);
  final String label;
  final String sizeLabel;
  final String description;
}
