import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

class ListBoardBackground extends StatelessWidget {
  const ListBoardBackground({
    required this.appearance,
    required this.child,
    this.useThemeBackground = false,
    super.key,
  });

  final ListAppearance appearance;
  final Widget child;
  final bool useThemeBackground;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 650),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) =>
              _BlurredBackgroundTransition(animation: animation, child: child),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          ),
          child: useThemeBackground
              ? _ThemeBackgroundLayer(
                  key: ValueKey((
                    Theme.of(context).colorScheme.primary,
                    isDark,
                  )),
                  isDark: isDark,
                )
              : _BackgroundLayer(
                  key: ValueKey((appearance, isDark)),
                  appearance: appearance,
                  isDark: isDark,
                ),
        ),
        child,
      ],
    );
  }
}

class _ThemeBackgroundLayer extends StatelessWidget {
  const _ThemeBackgroundLayer({required this.isDark, super.key});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.surface;
    return DecoratedBox(
      key: const ValueKey('loading-theme-background'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              colorScheme.primary.withValues(alpha: isDark ? 0.24 : 0.12),
              surface,
            ),
            Color.alphaBlend(
              colorScheme.secondary.withValues(alpha: isDark ? 0.14 : 0.07),
              surface,
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredBackgroundTransition extends StatelessWidget {
  const _BlurredBackgroundTransition({
    required this.animation,
    required this.child,
  });

  static const _maximumBlur = 14.0;
  static const _maximumScale = 1.018;

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final progress = animation.value.clamp(0.0, 1.0).toDouble();
          final blur = _maximumBlur * (1 - progress);
          final scale = 1 + ((_maximumScale - 1) * (1 - progress));
          return Transform.scale(
            scale: scale,
            child: ImageFiltered(
              key: const ValueKey('background-transition-blur'),
              enabled: blur > 0.01,
              imageFilter: ImageFilter.blur(
                sigmaX: blur,
                sigmaY: blur,
                tileMode: TileMode.clamp,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({
    required this.appearance,
    required this.isDark,
    super.key,
  });

  final ListAppearance appearance;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _BackgroundVisual(appearance: appearance),
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
      ],
    );
  }
}

class _BackgroundVisual extends StatelessWidget {
  const _BackgroundVisual({required this.appearance});

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
    ListBackgroundPreset.ocean => 'Océano',
    ListBackgroundPreset.desert => 'Desierto',
    ListBackgroundPreset.cherry => 'Cerezo',
    ListBackgroundPreset.aurora => 'Aurora',
    ListBackgroundPreset.mist => 'Bruma',
    ListBackgroundPreset.mocha => 'Moka',
    ListBackgroundPreset.citrus => 'Cítrico',
    ListBackgroundPreset.coral => 'Coral',
    ListBackgroundPreset.cobalt => 'Cobalto',
    ListBackgroundPreset.sage => 'Salvia',
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
    ListBackgroundPreset.ocean => const [
      Color(0xFF0B3C5D),
      Color(0xFF328CC1),
      Color(0xFF8ED1D5),
    ],
    ListBackgroundPreset.desert => const [
      Color(0xFF9C4F32),
      Color(0xFFE0A96D),
      Color(0xFFF3D9A4),
    ],
    ListBackgroundPreset.cherry => const [
      Color(0xFF7A284B),
      Color(0xFFD96C8D),
      Color(0xFFFFD6DC),
    ],
    ListBackgroundPreset.aurora => const [
      Color(0xFF192A56),
      Color(0xFF6C5CE7),
      Color(0xFF55E6C1),
    ],
    ListBackgroundPreset.mist => const [
      Color(0xFF415A77),
      Color(0xFF8DA3B8),
      Color(0xFFDCE6EC),
    ],
    ListBackgroundPreset.mocha => const [
      Color(0xFF4B2E2B),
      Color(0xFFA86F55),
      Color(0xFFE7C8A0),
    ],
    ListBackgroundPreset.citrus => const [
      Color(0xFF637A1F),
      Color(0xFFC9D94E),
      Color(0xFFFFF2A8),
    ],
    ListBackgroundPreset.coral => const [
      Color(0xFFB7474E),
      Color(0xFFFF7F6E),
      Color(0xFFFFC4A8),
    ],
    ListBackgroundPreset.cobalt => const [
      Color(0xFF102A66),
      Color(0xFF2864C7),
      Color(0xFF79B8FF),
    ],
    ListBackgroundPreset.sage => const [
      Color(0xFF52634F),
      Color(0xFF91A88C),
      Color(0xFFDCE3CE),
    ],
    ListBackgroundPreset.custom => const [Color(0xFFB9B3A8), Color(0xFFE8E1D6)],
  };
}

typedef ListBackgroundImagePicker = Future<Uint8List?> Function();

Future<Uint8List?> _pickListBackgroundImage() async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 76,
    requestFullMetadata: false,
  );
  return image?.readAsBytes();
}

Future<ListAppearance?> showListBackgroundPicker(
  BuildContext context, {
  required ListAppearance initialAppearance,
  ListBackgroundImagePicker? imagePicker,
}) => showModalBottomSheet<ListAppearance>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(
    alpha: Theme.of(context).brightness == Brightness.dark ? 0.38 : 0.22,
  ),
  builder: (_) => _ListBackgroundSheet(
    initialAppearance: initialAppearance,
    imagePicker: imagePicker ?? _pickListBackgroundImage,
  ),
);

class _ListBackgroundSheet extends StatefulWidget {
  const _ListBackgroundSheet({
    required this.initialAppearance,
    required this.imagePicker,
  });

  final ListAppearance initialAppearance;
  final ListBackgroundImagePicker imagePicker;

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
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion = mediaQuery.disableAnimations;
    final motionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final usesLargeText = mediaQuery.textScaler.scale(14) > 18;
    final previewHeight = mediaQuery.size.height < 700
        ? usesLargeText
              ? 304.0
              : 258.0
        : 276.0;
    final includedPresets = ListBackgroundPreset.values
        .where((preset) => preset != ListBackgroundPreset.custom)
        .toList(growable: false);
    final sheetRadius = BorderRadius.vertical(top: Radius.circular(30));
    return ClipRRect(
      key: const ValueKey('background-picker-sheet'),
      borderRadius: sheetRadius,
      child: BackdropFilter(
        key: const ValueKey('background-sheet-glass-filter'),
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.94),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.86 : 0.82,
                ),
                theme.colorScheme.surfaceContainerLow.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.72 : 0.67,
                ),
              ],
            ),
            borderRadius: sheetRadius,
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.14 : 0.52,
                ),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.12),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.35,
                                      ),
                                ),
                              ),
                              IconButton.filledTonal(
                                key: const ValueKey(
                                  'close-background-picker-button',
                                ),
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(context),
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.surface
                                      .withValues(alpha: 0.52),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          Text(
                            'Elige un estilo incluido o una foto de tu galería.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _livePreview(theme, previewHeight, motionDuration),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Estilos incluidos',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                '${includedPresets.length} opciones',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns =
                                  constraints.maxWidth < 330 || usesLargeText
                                  ? 3
                                  : constraints.maxWidth < 520
                                  ? 4
                                  : 5;
                              return GridView.count(
                                key: const ValueKey('background-preset-grid'),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: columns,
                                childAspectRatio: usesLargeText ? 0.96 : 1.08,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                children: includedPresets
                                    .map(
                                      (preset) => _presetTile(
                                        theme,
                                        preset,
                                        motionDuration,
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                          if (_error case final error?) ...[
                            const SizedBox(height: 10),
                            Container(
                              key: const ValueKey('background-picker-error'),
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: theme.colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      error,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ClipRect(
                child: BackdropFilter(
                  key: const ValueKey('background-action-glass-filter'),
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.68),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.13
                                : 0.48,
                          ),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, -7),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            key: const ValueKey('save-background-button'),
                            onPressed: _isPicking ? null : _save,
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded),
                            label: Text('Aplicar ${_preset.displayName}'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _livePreview(ThemeData theme, double height, Duration motionDuration) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          key: const ValueKey('background-live-preview'),
          height: height,
          child: ListBoardBackground(
            appearance: _appearance,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _previewStyleBadge(theme)),
                      const SizedBox(width: 8),
                      _previewPhotoActions(context, theme),
                    ],
                  ),
                  const Spacer(),
                  _previewBlurControl(theme, motionDuration),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewStyleBadge(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.17),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.visibility_outlined,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vista previa',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _preset.displayName,
                        key: const ValueKey('background-preview-preset-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewPhotoActions(BuildContext context, ThemeData theme) {
    final hasImage = _customImage != null;
    final selected = _preset == ListBackgroundPreset.custom;
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    if (_isPicking) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 46,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      );
    }

    final buttonKey = hasImage && selected
        ? const ValueKey('change-custom-background-button')
        : const ValueKey('background-preset-custom');
    final label = !hasImage
        ? 'Tu foto'
        : selected
        ? 'Cambiar'
        : 'Usar foto';
    final onPressed = hasImage && !selected
        ? () => _selectPreset(ListBackgroundPreset.custom)
        : _pickCustomImage;
    final leading = hasImage
        ? SizedBox.square(
            dimension: 22,
            child: ClipOval(child: _customImageThumbnail(theme)),
          )
        : const Icon(Icons.add_photo_alternate_outlined, size: 18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          IconButton.outlined(
            key: buttonKey,
            tooltip: label,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              minimumSize: const Size(42, 42),
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.64,
              ),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            icon: leading,
          )
        else
          OutlinedButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.64,
              ),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: leading,
            label: Text(label),
          ),
        if (hasImage) ...[
          const SizedBox(width: 5),
          IconButton.outlined(
            key: const ValueKey('remove-custom-background-button'),
            tooltip: 'Quitar foto',
            onPressed: _removeCustomImage,
            style: IconButton.styleFrom(
              minimumSize: const Size(42, 42),
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.64,
              ),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
          ),
        ],
      ],
    );
  }

  Widget _previewBlurControl(ThemeData theme, Duration motionDuration) {
    final roundedValue = _blur.round();
    return ClipRRect(
      key: const ValueKey('background-blur-control'),
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        key: const ValueKey('background-blur-glass-filter'),
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: motionDuration,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface.withValues(alpha: 0.72),
                theme.colorScheme.primaryContainer.withValues(alpha: 0.34),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.blur_on_rounded,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Desenfoque',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    key: const ValueKey('background-blur-value'),
                    duration: motionDuration,
                    width: 32,
                    height: 27,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$roundedValue',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: _blurQuickButton(
                      theme,
                      label: 'Nítido',
                      value: 0,
                      motionDuration: motionDuration,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _blurQuickButton(
                      theme,
                      label: 'Suave',
                      value: 8,
                      motionDuration: motionDuration,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _blurQuickButton(
                      theme,
                      label: 'Intenso',
                      value: 16,
                      motionDuration: motionDuration,
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 22,
                      right: 22,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.16),
                              theme.colorScheme.primary.withValues(alpha: 0.58),
                              theme.colorScheme.primary,
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: theme.sliderTheme.copyWith(
                        trackHeight: 4,
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: theme.colorScheme.primary,
                        overlayColor: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                          elevation: 3,
                        ),
                      ),
                      child: Slider(
                        key: const ValueKey('background-blur-slider'),
                        value: _blur,
                        min: 0,
                        max: 20,
                        divisions: 20,
                        label: 'Desenfoque $roundedValue',
                        semanticFormatterCallback: (value) =>
                            'Desenfoque ${value.round()} de 20',
                        onChanged: (value) => setState(() => _blur = value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetTile(
    ThemeData theme,
    ListBackgroundPreset preset,
    Duration motionDuration,
  ) {
    final selected = preset == _preset;
    return Semantics(
      selected: selected,
      button: true,
      label: selected
          ? '${preset.displayName}, seleccionado'
          : preset.displayName,
      child: AnimatedScale(
        duration: motionDuration,
        curve: Curves.easeOutCubic,
        scale: selected ? 1 : 0.985,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('background-preset-${preset.name}'),
            borderRadius: BorderRadius.circular(15),
            onTap: _isPicking ? null : () => _selectPreset(preset),
            child: AnimatedContainer(
              duration: motionDuration,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.18,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
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
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xA6000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 7,
                      right: 7,
                      bottom: 7,
                      child: Text(
                        preset.displayName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.onPrimary,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _customImageThumbnail(ThemeData theme) {
    try {
      return Image.memory(
        base64Decode(_customImage!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } on FormatException {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
  }

  Widget _blurQuickButton(
    ThemeData theme, {
    required String label,
    required double value,
    required Duration motionDuration,
  }) {
    final selected = (_blur - value).abs() < 0.5;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('background-blur-preset-${value.round()}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _blur = value),
        child: AnimatedContainer(
          duration: motionDuration,
          curve: Curves.easeOutCubic,
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.18)
                : theme.colorScheme.surface.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectPreset(ListBackgroundPreset preset) async {
    if (preset != ListBackgroundPreset.custom) {
      setState(() {
        _preset = preset;
        _error = null;
      });
      return;
    }
    if (_customImage != null) {
      if (_preset == ListBackgroundPreset.custom) {
        await _pickCustomImage();
      } else {
        setState(() {
          _preset = preset;
          _error = null;
        });
      }
      return;
    }

    await _pickCustomImage();
  }

  Future<void> _pickCustomImage() async {
    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      final bytes = await widget.imagePicker();
      if (bytes == null || !mounted) return;
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

  void _removeCustomImage() {
    setState(() {
      _customImage = null;
      _error = null;
      if (_preset == ListBackgroundPreset.custom) {
        _preset = ListBackgroundPreset.paper;
        _blur = 0;
      }
    });
  }

  void _save() {
    if (_preset == ListBackgroundPreset.custom && _customImage == null) {
      setState(() => _error = 'Primero elige una foto de tu galería.');
      return;
    }
    Navigator.pop(context, _appearance);
  }
}
