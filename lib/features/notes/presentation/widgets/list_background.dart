import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

class ListBoardBackground extends StatelessWidget {
  const ListBoardBackground({
    required this.appearance,
    required this.child,
    super.key,
  });

  final ListAppearance appearance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          child: _BackgroundVisual(
            key: ValueKey(
              '${appearance.backgroundPreset.name}-'
              '${appearance.customBackgroundImage?.hashCode}',
            ),
            appearance: appearance,
          ),
        ),
        if (appearance.backgroundBlur > 0)
          ClipRect(
            child: BackdropFilter(
              key: const ValueKey('board-background-blur'),
              filter: ImageFilter.blur(
                sigmaX: appearance.backgroundBlur,
                sigmaY: appearance.backgroundBlur,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ColoredBox(
          color: (isDark ? Colors.black : Colors.white).withValues(
            alpha: appearance.backgroundPreset == ListBackgroundPreset.paper
                ? (isDark ? 0.08 : 0.12)
                : (isDark ? 0.46 : 0.32),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackgroundVisual extends StatelessWidget {
  const _BackgroundVisual({required this.appearance, super.key});

  final ListAppearance appearance;

  @override
  Widget build(BuildContext context) {
    if (appearance.backgroundPreset == ListBackgroundPreset.custom &&
        appearance.hasCustomBackground) {
      try {
        return SizedBox.expand(
          child: Image.memory(
            base64Decode(appearance.customBackgroundImage!),
            key: const ValueKey('custom-board-background'),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                _gradientBackground(context, ListBackgroundPreset.paper),
          ),
        );
      } on FormatException {
        return _gradientBackground(context, ListBackgroundPreset.paper);
      }
    }
    return _gradientBackground(context, appearance.backgroundPreset);
  }

  Widget _gradientBackground(
    BuildContext context,
    ListBackgroundPreset preset,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = preset.backgroundColors(isDark: isDark);
    return SizedBox.expand(
      child: DecoratedBox(
        key: ValueKey('preset-background-${preset.name}'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: CustomPaint(painter: _BackgroundPatternPainter(preset, isDark)),
      ),
    );
  }
}

class _BackgroundPatternPainter extends CustomPainter {
  const _BackgroundPatternPainter(this.preset, this.isDark);

  final ListBackgroundPreset preset;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (preset == ListBackgroundPreset.paper ||
        preset == ListBackgroundPreset.custom) {
      return;
    }
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.white).withValues(alpha: 0.12);
    canvas
      ..drawCircle(Offset(size.width * 0.82, size.height * 0.12), 150, paint)
      ..drawCircle(Offset(size.width * 0.08, size.height * 0.78), 210, paint);
    paint.color = Colors.black.withValues(alpha: isDark ? 0.07 : 0.035);
    canvas.drawCircle(
      Offset(size.width * 0.58, size.height * 0.68),
      110,
      paint,
    );
  }

  @override
  bool shouldRepaint(_BackgroundPatternPainter oldDelegate) =>
      oldDelegate.preset != preset || oldDelegate.isDark != isDark;
}

extension ListBackgroundPresetStyle on ListBackgroundPreset {
  String get displayName => switch (this) {
    ListBackgroundPreset.paper => 'Papel',
    ListBackgroundPreset.sunrise => 'Amanecer',
    ListBackgroundPreset.lagoon => 'Laguna',
    ListBackgroundPreset.botanical => 'Botánico',
    ListBackgroundPreset.lavender => 'Lavanda',
    ListBackgroundPreset.midnight => 'Medianoche',
    ListBackgroundPreset.custom => 'Tu foto',
  };

  List<Color> backgroundColors({required bool isDark}) => switch (this) {
    ListBackgroundPreset.paper =>
      isDark
          ? const [Color(0xFF171714), Color(0xFF24231F)]
          : const [Color(0xFFF7F3EA), Color(0xFFFFFCF5)],
    ListBackgroundPreset.sunrise => const [
      Color(0xFFFFB199),
      Color(0xFFFFE0A3),
      Color(0xFFF9A8C9),
    ],
    ListBackgroundPreset.lagoon => const [
      Color(0xFF3CAEA3),
      Color(0xFF69D2C8),
      Color(0xFFBCECE7),
    ],
    ListBackgroundPreset.botanical => const [
      Color(0xFF527A5A),
      Color(0xFF93B58C),
      Color(0xFFD8E4C8),
    ],
    ListBackgroundPreset.lavender => const [
      Color(0xFF8E7CC3),
      Color(0xFFC6B7E8),
      Color(0xFFF1D5E7),
    ],
    ListBackgroundPreset.midnight => const [
      Color(0xFF10172A),
      Color(0xFF263B63),
      Color(0xFF6D5A93),
    ],
    ListBackgroundPreset.custom => const [Color(0xFFB9B3A8), Color(0xFFE8E1D6)],
  };
}

Future<ListAppearance?> showListBackgroundPicker(
  BuildContext context, {
  required ListAppearance initialAppearance,
}) => showModalBottomSheet<ListAppearance>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ListBackgroundSheet(initialAppearance: initialAppearance),
);

class _ListBackgroundSheet extends StatefulWidget {
  const _ListBackgroundSheet({required this.initialAppearance});

  final ListAppearance initialAppearance;

  @override
  State<_ListBackgroundSheet> createState() => _ListBackgroundSheetState();
}

class _ListBackgroundSheetState extends State<_ListBackgroundSheet> {
  static const _maximumImageBytes = 2250000;
  late ListBackgroundPreset _preset = widget.initialAppearance.backgroundPreset;
  late double _blur = widget.initialAppearance.backgroundBlur;
  late String? _customImage = widget.initialAppearance.customBackgroundImage;
  bool _isPicking = false;
  String? _error;

  ListAppearance get _appearance => ListAppearance(
    backgroundPreset: _preset,
    backgroundBlur: _blur,
    customBackgroundImage: _preset == ListBackgroundPreset.custom
        ? _customImage
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Fondo de esta lista',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      Text(
                        'Elige un estilo incluido o una foto de tu galería.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          key: const ValueKey('background-live-preview'),
                          height: 150,
                          child: ListBoardBackground(
                            appearance: _appearance,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withValues(
                                    alpha: 0.82,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Text(
                                  'Así se verá tu lista',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('ESTILOS', style: _sectionStyle(theme)),
                      const SizedBox(height: 10),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: MediaQuery.sizeOf(context).width < 430
                            ? 3
                            : 4,
                        childAspectRatio: 1.12,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: ListBackgroundPreset.values
                            .map((preset) => _presetTile(theme, preset))
                            .toList(),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text('DESENFOQUE', style: _sectionStyle(theme)),
                          const Spacer(),
                          Text(
                            _blur == 0 ? 'Sin blur' : '${_blur.round()}',
                            key: const ValueKey('background-blur-value'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      Slider(
                        key: const ValueKey('background-blur-slider'),
                        value: _blur,
                        min: 0,
                        max: 20,
                        divisions: 20,
                        label: _blur == 0
                            ? 'Sin blur'
                            : _blur.round().toString(),
                        onChanged: (value) => setState(() => _blur = value),
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: 4),
                        Text(
                          error,
                          key: const ValueKey('background-picker-error'),
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('save-background-button'),
                  onPressed: _isPicking ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aplicar fondo'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetTile(ThemeData theme, ListBackgroundPreset preset) {
    final selected = preset == _preset;
    return Semantics(
      selected: selected,
      button: true,
      label: preset.displayName,
      child: InkWell(
        key: ValueKey('background-preset-${preset.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: _isPicking ? null : () => _selectPreset(preset),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (preset == ListBackgroundPreset.custom &&
                    _customImage != null)
                  Image.memory(base64Decode(_customImage!), fit: BoxFit.cover)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: preset.backgroundColors(
                          isDark: theme.brightness == Brightness.dark,
                        ),
                      ),
                    ),
                  ),
                ColoredBox(color: Colors.black.withValues(alpha: 0.1)),
                Center(
                  child: preset == ListBackgroundPreset.custom && _isPicking
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : preset == ListBackgroundPreset.custom
                      ? const Icon(Icons.add_photo_alternate_outlined)
                      : null,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    color: Colors.black.withValues(alpha: 0.42),
                    child: Text(
                      preset.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _sectionStyle(ThemeData theme) => TextStyle(
    color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
    fontSize: 11,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.1,
  );

  Future<void> _selectPreset(ListBackgroundPreset preset) async {
    if (preset != ListBackgroundPreset.custom) {
      setState(() {
        _preset = preset;
        _error = null;
      });
      return;
    }
    if (_customImage != null) {
      setState(() {
        _preset = preset;
        _error = null;
      });
      return;
    }

    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 76,
        requestFullMetadata: false,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > _maximumImageBytes) {
        setState(() {
          _error =
              'La foto sigue siendo muy pesada. Elige una de menor tamaño.';
        });
        return;
      }
      setState(() {
        _customImage = base64Encode(bytes);
        _preset = ListBackgroundPreset.custom;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No pudimos abrir la galería. Revisa el permiso de fotos.';
        });
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _save() {
    if (_preset == ListBackgroundPreset.custom && _customImage == null) {
      setState(() => _error = 'Primero elige una foto de tu galería.');
      return;
    }
    Navigator.pop(context, _appearance);
  }
}
