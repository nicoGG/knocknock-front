import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

void main() {
  final now = DateTime(2026, 8, 12, 15, 30);

  test('formats recent note editions in Spanish', () {
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(seconds: 20)),
        relativeTo: now,
      ),
      'hace un momento',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(minutes: 1)),
        relativeTo: now,
      ),
      'hace 1 minuto',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(minutes: 18)),
        relativeTo: now,
      ),
      'hace 18 minutos',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(hours: 1)),
        relativeTo: now,
      ),
      'hace 1 hora',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(hours: 8)),
        relativeTo: now,
      ),
      'hace 8 horas',
    );
  });

  test('formats older note editions in days and months', () {
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(days: 1)),
        relativeTo: now,
      ),
      'hace 1 día',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(days: 12)),
        relativeTo: now,
      ),
      'hace 12 días',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(days: 30)),
        relativeTo: now,
      ),
      'hace 1 mes',
    );
    expect(
      formatRelativeNoteEdit(
        now.subtract(const Duration(days: 90)),
        relativeTo: now,
      ),
      'hace 3 meses',
    );
  });
}
