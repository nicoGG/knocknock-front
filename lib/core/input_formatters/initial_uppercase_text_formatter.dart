import 'package:flutter/services.dart';

/// Keeps the first Spanish letter in a text value uppercase.
class InitialUppercaseTextFormatter extends TextInputFormatter {
  const InitialUppercaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;

    final capitalizedText = capitalizeInitialLetter(newValue.text);
    if (capitalizedText == newValue.text) return newValue;

    return newValue.copyWith(text: capitalizedText);
  }
}

String capitalizeInitialLetter(String text) {
  final firstLetter = RegExp(
    r'[a-záéíóúüñ]',
    caseSensitive: false,
  ).firstMatch(text);
  if (firstLetter == null) return text;

  final letter = firstLetter.group(0)!;
  final uppercaseLetter = letter.toUpperCase();
  if (letter == uppercaseLetter) return text;

  return text.replaceRange(firstLetter.start, firstLetter.end, uppercaseLetter);
}
