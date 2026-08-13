import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';

abstract final class NotePalette {
  static Color color(NoteColor color) => switch (color) {
    NoteColor.none => const Color(0xFFF7F3EA),
    NoteColor.yellow => const Color(0xFFFFE58A),
    NoteColor.pink => const Color(0xFFFFB8C6),
    NoteColor.blue => const Color(0xFFACDDF2),
    NoteColor.green => const Color(0xFFBDE6C0),
    NoteColor.purple => const Color(0xFFD6C2F1),
    NoteColor.orange => const Color(0xFFFFC58F),
    NoteColor.mint => const Color(0xFFA9E5D1),
    NoteColor.coral => const Color(0xFFFFAAA2),
    NoteColor.gray => const Color(0xFFD7D5D0),
    NoteColor.red => const Color(0xFFF29C9C),
    NoteColor.teal => const Color(0xFF8ED8D3),
    NoteColor.brown => const Color(0xFFD8B79E),
  };
}
