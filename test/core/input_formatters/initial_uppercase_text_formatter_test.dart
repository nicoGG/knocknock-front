import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';

void main() {
  const formatter = InitialUppercaseTextFormatter();

  test('capitalizes the first letter and preserves leading punctuation', () {
    const value = TextEditingValue(
      text: '  ¿qué comprar?',
      selection: TextSelection.collapsed(offset: 14),
    );

    final result = formatter.formatEditUpdate(TextEditingValue.empty, value);

    expect(result.text, '  ¿Qué comprar?');
    expect(result.selection, value.selection);
  });

  test('capitalizes accented Spanish letters', () {
    expect(capitalizeInitialLetter('árbol grande'), 'Árbol grande');
    expect(capitalizeInitialLetter('ñandú'), 'Ñandú');
  });

  test('keeps empty and already capitalized values unchanged', () {
    expect(capitalizeInitialLetter(''), '');
    expect(capitalizeInitialLetter('Detalle listo'), 'Detalle listo');
  });
}
