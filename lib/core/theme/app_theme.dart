import 'package:flutter/material.dart';

enum AppColorTheme {
  sunset(seedColor: Color(0xFFEC5B3F), secondaryColor: Color(0xFFF3A94C)),
  ocean(seedColor: Color(0xFF356FD6), secondaryColor: Color(0xFF2AB7B8)),
  forest(seedColor: Color(0xFF2F8A62), secondaryColor: Color(0xFF83A94A)),
  violet(seedColor: Color(0xFF7657C8), secondaryColor: Color(0xFFD05E9B)),
  cherry(seedColor: Color(0xFFD24F83), secondaryColor: Color(0xFFF08A9D)),
  amber(seedColor: Color(0xFFC77700), secondaryColor: Color(0xFFF3B53D)),
  mint(seedColor: Color(0xFF168F8A), secondaryColor: Color(0xFF58C7A5)),
  midnight(seedColor: Color(0xFF344C8A), secondaryColor: Color(0xFF7768C5)),
  coral(seedColor: Color(0xFFD85645), secondaryColor: Color(0xFFF08B72)),
  gold(seedColor: Color(0xFFB98500), secondaryColor: Color(0xFFE8C34E)),
  lime(seedColor: Color(0xFF5F8E25), secondaryColor: Color(0xFFA6C957)),
  turquoise(seedColor: Color(0xFF007F84), secondaryColor: Color(0xFF56C7C1)),
  sky(seedColor: Color(0xFF287FB8), secondaryColor: Color(0xFF72BFE1)),
  indigo(seedColor: Color(0xFF4A5AB5), secondaryColor: Color(0xFF7F8FE0)),
  lavender(seedColor: Color(0xFF8D5DB7), secondaryColor: Color(0xFFC594D8)),
  graphite(seedColor: Color(0xFF586571), secondaryColor: Color(0xFF8D9AA6));

  const AppColorTheme({required this.seedColor, required this.secondaryColor});

  final Color seedColor;
  final Color secondaryColor;
}

abstract final class AppTheme {
  static const ink = Color(0xFF282621);
  static const canvas = Color(0xFFF7F3EA);
  static const accent = Color(0xFFEC5B3F);
  static const darkCanvas = Color(0xFF171714);

  static ThemeData get light => lightFor(AppColorTheme.sunset);

  static ThemeData get dark => darkFor(AppColorTheme.sunset);

  static ThemeData lightFor(AppColorTheme colorTheme) =>
      _build(Brightness.light, colorTheme);

  static ThemeData darkFor(AppColorTheme colorTheme) =>
      _build(Brightness.dark, colorTheme);

  static ThemeData _build(Brightness brightness, AppColorTheme colorTheme) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colorTheme.seedColor,
      brightness: brightness,
      surface: isDark ? darkCanvas : canvas,
    );
    final foreground = colorScheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: 'Avenir',
      textTheme: TextTheme(
        displaySmall: TextStyle(
          color: foreground,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineSmall: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: foreground, height: 1.45),
        bodyMedium: TextStyle(
          color: foreground.withValues(alpha: 0.76),
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHigh
            : Colors.white.withValues(alpha: 0.75),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorTheme.seedColor, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NockNockPageTransitionsBuilder(),
          TargetPlatform.iOS: _NockNockPageTransitionsBuilder(),
          TargetPlatform.macOS: _NockNockPageTransitionsBuilder(),
          TargetPlatform.windows: _NockNockPageTransitionsBuilder(),
          TargetPlatform.linux: _NockNockPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _NockNockPageTransitionsBuilder(),
        },
      ),
      dividerColor: foreground.withValues(alpha: 0.1),
    );
  }
}

class _NockNockPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NockNockPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || MediaQuery.disableAnimationsOf(context)) return child;

    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      key: const ValueKey('app-page-transition'),
      opacity: curvedAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curvedAnimation),
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }
}
