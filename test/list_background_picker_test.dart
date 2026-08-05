import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';

void main() {
  const initialPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
      'A8AAQUBAScY42YAAAAASUVORK5CYII=';
  const replacementGif = 'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==';

  testWidgets('replaces an existing custom list photo', (tester) async {
    ListAppearance? result;
    var pickerCalls = 0;
    await tester.pumpWidget(
      _PickerHost(
        initialAppearance: const ListAppearance(
          backgroundPreset: ListBackgroundPreset.custom,
          backgroundBlur: 5,
          customBackgroundImage: initialPng,
        ),
        imagePicker: () async {
          pickerCalls++;
          return Uint8List.fromList(base64Decode(replacementGif));
        },
        onResult: (appearance) => result = appearance,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-background-picker')));
    await tester.pumpAndSettle();

    final changeButton = find.byKey(
      const ValueKey('change-custom-background-button'),
    );
    expect(changeButton, findsOneWidget);
    await tester.ensureVisible(changeButton);
    await tester.tap(changeButton);
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    await tester.tap(find.byKey(const ValueKey('save-background-button')));
    await tester.pumpAndSettle();

    expect(result?.backgroundPreset, ListBackgroundPreset.custom);
    expect(result?.backgroundBlur, 5);
    expect(result?.customBackgroundImage, replacementGif);
  });

  testWidgets('removes a custom photo and returns to the paper background', (
    tester,
  ) async {
    ListAppearance? result;
    await tester.pumpWidget(
      _PickerHost(
        initialAppearance: const ListAppearance(
          backgroundPreset: ListBackgroundPreset.custom,
          backgroundBlur: 8,
          customBackgroundImage: initialPng,
        ),
        imagePicker: () async => null,
        onResult: (appearance) => result = appearance,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-background-picker')));
    await tester.pumpAndSettle();

    final removeButton = find.byKey(
      const ValueKey('remove-custom-background-button'),
    );
    expect(removeButton, findsOneWidget);
    await tester.ensureVisible(removeButton);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(removeButton, findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-background-button')));
    await tester.pumpAndSettle();

    expect(result?.backgroundPreset, ListBackgroundPreset.paper);
    expect(result?.backgroundBlur, 0);
    expect(result?.customBackgroundImage, isNull);
  });
}

class _PickerHost extends StatelessWidget {
  const _PickerHost({
    required this.initialAppearance,
    required this.imagePicker,
    required this.onResult,
  });

  final ListAppearance initialAppearance;
  final ListBackgroundImagePicker imagePicker;
  final ValueChanged<ListAppearance?> onResult;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const ValueKey('open-background-picker'),
              onPressed: () async {
                onResult(
                  await showListBackgroundPicker(
                    context,
                    initialAppearance: initialAppearance,
                    imagePicker: imagePicker,
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
  }
}
