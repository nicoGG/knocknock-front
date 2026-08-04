import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';

abstract final class NotePalette {
  static Color color(NoteColor color) => switch (color) {
    NoteColor.yellow => const Color(0xFFFFE58A),
    NoteColor.pink => const Color(0xFFFFB8C6),
    NoteColor.blue => const Color(0xFFACDDF2),
    NoteColor.green => const Color(0xFFBDE6C0),
    NoteColor.purple => const Color(0xFFD6C2F1),
  };
}
