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
    NoteCategory.study => 'Estudio',
    NoteCategory.finance => 'Finanzas',
    NoteCategory.home => 'Hogar',
    NoteCategory.ideas => 'Ideas',
  };

  static IconData icon(NoteCategory category) => switch (category) {
    NoteCategory.general => Icons.sticky_note_2_outlined,
    NoteCategory.personal => Icons.favorite_outline_rounded,
    NoteCategory.work => Icons.work_outline_rounded,
    NoteCategory.shopping => Icons.shopping_bag_outlined,
    NoteCategory.health => Icons.spa_outlined,
    NoteCategory.travel => Icons.landscape_outlined,
    NoteCategory.study => Icons.school_outlined,
    NoteCategory.finance => Icons.account_balance_wallet_outlined,
    NoteCategory.home => Icons.home_outlined,
    NoteCategory.ideas => Icons.lightbulb_outline_rounded,
  };

  static String? assetPath(NoteCategory category) => switch (category) {
    NoteCategory.general => null,
    NoteCategory.personal => 'assets/note_backgrounds/personal.jpg',
    NoteCategory.work => 'assets/note_backgrounds/work.jpg',
    NoteCategory.shopping => 'assets/note_backgrounds/shopping.jpg',
    NoteCategory.health => 'assets/note_backgrounds/health.jpg',
    NoteCategory.travel => 'assets/note_backgrounds/travel.jpg',
    NoteCategory.study => 'assets/note_backgrounds/study.jpg',
    NoteCategory.finance => 'assets/note_backgrounds/finance.jpg',
    NoteCategory.home => 'assets/note_backgrounds/home.jpg',
    NoteCategory.ideas => 'assets/note_backgrounds/ideas.jpg',
  };

  static Color baseColor(NoteCategory category) => switch (category) {
    NoteCategory.general => const Color(0xFFFFF1A8),
    NoteCategory.personal => const Color(0xFF8B4E62),
    NoteCategory.work => const Color(0xFF71465D),
    NoteCategory.shopping => const Color(0xFF9A594F),
    NoteCategory.health => const Color(0xFF536E68),
    NoteCategory.travel => const Color(0xFF654D7B),
    NoteCategory.study => const Color(0xFF385D78),
    NoteCategory.finance => const Color(0xFF426B55),
    NoteCategory.home => const Color(0xFF8A6049),
    NoteCategory.ideas => const Color(0xFF84662E),
  };

  static Color foregroundColor(NoteCategory category) =>
      category == NoteCategory.general
      ? const Color(0xFF282621)
      : const Color(0xFFF9F4F6);
}
