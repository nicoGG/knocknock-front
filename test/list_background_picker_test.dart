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

  testWidgets('presents compact styles with a distinct gallery action', (
    tester,
  ) async {
    ListAppearance? result;
    tester.view.physicalSize = const Size(430, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _PickerHost(
        initialAppearance: const ListAppearance(),
        imagePicker: () async => null,
        onResult: (appearance) => result = appearance,
        theme: ThemeData.dark(useMaterial3: true),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-background-picker')));
    await tester.pumpAndSettle();

    final preview = find.byKey(const ValueKey('background-live-preview'));
    final paper = find.byKey(const ValueKey('background-preset-paper'));
    final sunrise = find.byKey(const ValueKey('background-preset-sunrise'));
    final lagoon = find.byKey(const ValueKey('background-preset-lagoon'));
    final botanical = find.byKey(const ValueKey('background-preset-botanical'));
    final cherry = find.byKey(const ValueKey('background-preset-cherry'));
    final aurora = find.byKey(const ValueKey('background-preset-aurora'));
    final mist = find.byKey(const ValueKey('background-preset-mist'));
    final mocha = find.byKey(const ValueKey('background-preset-mocha'));
    final citrus = find.byKey(const ValueKey('background-preset-citrus'));
    final coral = find.byKey(const ValueKey('background-preset-coral'));
    final cobalt = find.byKey(const ValueKey('background-preset-cobalt'));
    final sage = find.byKey(const ValueKey('background-preset-sage'));
    final custom = find.byKey(const ValueKey('background-preset-custom'));
    final blur = find.byKey(const ValueKey('background-blur-control'));
    final save = find.byKey(const ValueKey('save-background-button'));

    expect(tester.getSize(preview).height, 276);
    expect(
      find.byKey(const ValueKey('background-sheet-glass-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('background-blur-glass-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('background-preset-grid')),
      findsOneWidget,
    );
    expect(find.text('16 opciones'), findsOneWidget);
    expect(
      tester.getCenter(paper).dy,
      closeTo(tester.getCenter(sunrise).dy, 0.01),
    );
    expect(
      tester.getCenter(sunrise).dy,
      closeTo(tester.getCenter(lagoon).dy, 0.01),
    );
    expect(
      tester.getCenter(lagoon).dy,
      closeTo(tester.getCenter(botanical).dy, 0.01),
    );
    expect(tester.getCenter(paper).dx, lessThan(tester.getCenter(sunrise).dx));
    expect(tester.getCenter(sunrise).dx, lessThan(tester.getCenter(lagoon).dx));
    expect(tester.getSize(paper).width, lessThan(100));
    expect(
      tester.getCenter(cherry).dy,
      closeTo(tester.getCenter(aurora).dy, 0.01),
    );
    expect(
      tester.getCenter(aurora).dy,
      closeTo(tester.getCenter(mist).dy, 0.01),
    );
    expect(
      tester.getCenter(mist).dy,
      closeTo(tester.getCenter(mocha).dy, 0.01),
    );
    expect(
      tester.getCenter(citrus).dy,
      closeTo(tester.getCenter(coral).dy, 0.01),
    );
    expect(
      tester.getCenter(coral).dy,
      closeTo(tester.getCenter(cobalt).dy, 0.01),
    );
    expect(
      tester.getCenter(cobalt).dy,
      closeTo(tester.getCenter(sage).dy, 0.01),
    );
    expect(
      tester.getRect(custom).top,
      greaterThanOrEqualTo(tester.getRect(preview).top),
    );
    expect(
      tester.getRect(custom).bottom,
      lessThanOrEqualTo(tester.getRect(preview).bottom),
    );
    expect(
      tester.getRect(blur).top,
      greaterThanOrEqualTo(tester.getRect(preview).top),
    );
    expect(
      tester.getRect(blur).bottom,
      lessThanOrEqualTo(tester.getRect(preview).bottom),
    );
    expect(tester.getRect(blur).bottom, lessThan(tester.getRect(save).top));
    expect(find.text('Aplicar Papel'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('background-blur-preset-16')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('background-blur-value')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '16',
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('background-blur-slider')))
          .value,
      16,
    );

    await tester.tap(lagoon);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('background-preview-preset-label')),
          )
          .data,
      'Laguna',
    );
    expect(find.text('Aplicar Laguna'), findsOneWidget);

    await tester.ensureVisible(sage);
    await tester.pumpAndSettle();
    await tester.tap(sage);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('background-preview-preset-label')),
          )
          .data,
      'Salvia',
    );
    expect(find.text('Aplicar Salvia'), findsOneWidget);

    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(result?.backgroundPreset, ListBackgroundPreset.sage);
    expect(result?.backgroundBlur, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a preferred photo directly from the preview', (
    tester,
  ) async {
    ListAppearance? result;
    var pickerCalls = 0;
    await tester.pumpWidget(
      _PickerHost(
        initialAppearance: const ListAppearance(),
        imagePicker: () async {
          pickerCalls++;
          return Uint8List.fromList(base64Decode(replacementGif));
        },
        onResult: (appearance) => result = appearance,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-background-picker')));
    await tester.pumpAndSettle();

    final preview = find.byKey(const ValueKey('background-live-preview'));
    final photoButton = find.byKey(const ValueKey('background-preset-custom'));
    expect(photoButton, findsOneWidget);
    expect(
      tester.getRect(photoButton).top,
      greaterThanOrEqualTo(tester.getRect(preview).top),
    );
    expect(
      tester.getRect(photoButton).bottom,
      lessThanOrEqualTo(tester.getRect(preview).bottom),
    );

    await tester.tap(photoButton);
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('background-preview-preset-label')),
          )
          .data,
      'Tu foto',
    );
    expect(
      find.byKey(const ValueKey('change-custom-background-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remove-custom-background-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('save-background-button')));
    await tester.pumpAndSettle();

    expect(result?.backgroundPreset, ListBackgroundPreset.custom);
    expect(result?.customBackgroundImage, replacementGif);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays usable on a short screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _PickerHost(
        initialAppearance: const ListAppearance(),
        imagePicker: () async => null,
        onResult: (_) {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-background-picker')));
    await tester.pumpAndSettle();

    final blur = find.byKey(const ValueKey('background-blur-control'));
    await tester.ensureVisible(blur);
    await tester.pumpAndSettle();

    expect(blur, findsOneWidget);
    expect(
      find.byKey(const ValueKey('save-background-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _PickerHost extends StatelessWidget {
  const _PickerHost({
    required this.initialAppearance,
    required this.imagePicker,
    required this.onResult,
    this.theme,
  });

  final ListAppearance initialAppearance;
  final ListBackgroundImagePicker imagePicker;
  final ValueChanged<ListAppearance?> onResult;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: theme,
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
