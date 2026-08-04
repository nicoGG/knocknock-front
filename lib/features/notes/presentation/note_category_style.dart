import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';

abstract final class NoteCategoryStyle {
  static String label(NoteCategory category) => switch (category) {
    NoteCategory.general => 'General',
    NoteCategory.personal => 'Personal',
    NoteCategory.work => 'Trabajo',
    NoteCategory.shopping => 'Compras',
    NoteCategory.health => 'Salud',
    NoteCategory.travel => 'Viajes',
  };

  static IconData icon(NoteCategory category) => switch (category) {
    NoteCategory.general => Icons.sticky_note_2_outlined,
    NoteCategory.personal => Icons.favorite_outline_rounded,
    NoteCategory.work => Icons.work_outline_rounded,
    NoteCategory.shopping => Icons.shopping_bag_outlined,
    NoteCategory.health => Icons.spa_outlined,
    NoteCategory.travel => Icons.landscape_outlined,
  };

  static String? assetPath(NoteCategory category) => switch (category) {
    NoteCategory.general => null,
    NoteCategory.personal => 'assets/note_backgrounds/personal.jpg',
    NoteCategory.work => 'assets/note_backgrounds/work.jpg',
    NoteCategory.shopping => 'assets/note_backgrounds/shopping.jpg',
    NoteCategory.health => 'assets/note_backgrounds/health.jpg',
    NoteCategory.travel => 'assets/note_backgrounds/travel.jpg',
  };

  static Color baseColor(NoteCategory category) => switch (category) {
    NoteCategory.general => const Color(0xFFFFF1A8),
    NoteCategory.personal => const Color(0xFF8B4E62),
    NoteCategory.work => const Color(0xFF71465D),
    NoteCategory.shopping => const Color(0xFF9A594F),
    NoteCategory.health => const Color(0xFF536E68),
    NoteCategory.travel => const Color(0xFF654D7B),
  };

  static Color foregroundColor(NoteCategory category) =>
      category == NoteCategory.general
      ? const Color(0xFF282621)
      : const Color(0xFFF9F4F6);
}
