import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';

void main() {
  test('exposes the expanded note categories', () {
    expect(NoteCategoryStyle.label(NoteCategory.study), 'Estudio');
    expect(NoteCategoryStyle.label(NoteCategory.finance), 'Finanzas');
    expect(NoteCategoryStyle.label(NoteCategory.home), 'Hogar');
    expect(NoteCategoryStyle.label(NoteCategory.ideas), 'Ideas');
    expect(
      NoteCategory.values
          .where((category) => category != NoteCategory.general)
          .map(NoteCategoryStyle.assetPath),
      everyElement(isNotNull),
    );
  });

  test('exposes the expanded note color palette', () {
    expect(NotePalette.color(NoteColor.orange), isNotNull);
    expect(NotePalette.color(NoteColor.mint), isNotNull);
    expect(NotePalette.color(NoteColor.coral), isNotNull);
    expect(NotePalette.color(NoteColor.gray), isNotNull);
    expect(NotePalette.color(NoteColor.red), isNotNull);
    expect(NotePalette.color(NoteColor.teal), isNotNull);
    expect(NotePalette.color(NoteColor.brown), isNotNull);
  });

  test('exposes the expanded list backgrounds', () {
    expect(ListBackgroundPreset.ocean.displayName, 'Océano');
    expect(ListBackgroundPreset.desert.displayName, 'Desierto');
    expect(ListBackgroundPreset.cherry.displayName, 'Cerezo');
    expect(ListBackgroundPreset.aurora.displayName, 'Aurora');
    expect(ListBackgroundPreset.mist.displayName, 'Bruma');
    expect(ListBackgroundPreset.mocha.displayName, 'Moka');
    expect(ListBackgroundPreset.citrus.displayName, 'Cítrico');
    expect(ListBackgroundPreset.coral.displayName, 'Coral');
    expect(ListBackgroundPreset.cobalt.displayName, 'Cobalto');
    expect(ListBackgroundPreset.sage.displayName, 'Salvia');
    for (final preset in [
      ListBackgroundPreset.mist,
      ListBackgroundPreset.mocha,
      ListBackgroundPreset.citrus,
      ListBackgroundPreset.coral,
      ListBackgroundPreset.cobalt,
      ListBackgroundPreset.sage,
    ]) {
      expect(preset.backgroundColors(isDark: false), hasLength(3));
      final restored = ListAppearance.fromJson(
        ListAppearance(backgroundPreset: preset).toJson(),
      );
      expect(restored.backgroundPreset, preset);
    }
  });
}
