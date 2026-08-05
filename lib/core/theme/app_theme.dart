import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const ink = Color(0xFF282621);
  static const canvas = Color(0xFFF7F3EA);
  static const accent = Color(0xFFEC5B3F);
  static const darkCanvas = Color(0xFF171714);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
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
          borderSide: const BorderSide(color: accent, width: 1.5),
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
