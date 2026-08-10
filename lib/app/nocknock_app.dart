import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/core/update/google_play_update_prompt.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/board_page.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NockNockApp extends StatefulWidget {
  const NockNockApp({
    required this.repository,
    required this.authRepository,
    this.themeController,
    this.boardViewModeController,
    this.notificationsController,
    this.navigatorObservers = const [],
    this.preferences,
    super.key,
  });

  final NotesRepository repository;
  final AuthRepository authRepository;
  final AppThemeController? themeController;
  final BoardViewModeController? boardViewModeController;
  final NotificationsController? notificationsController;
  final List<NavigatorObserver> navigatorObservers;
  final SharedPreferences? preferences;

  @override
  State<NockNockApp> createState() => _NockNockAppState();
}

class _NockNockAppState extends State<NockNockApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppThemeController _themeController =
      widget.themeController ?? AppThemeController();
  late final bool _ownsThemeController = widget.themeController == null;
  late final BoardViewModeController _boardViewModeController =
      widget.boardViewModeController ?? BoardViewModeController();
  late final bool _ownsBoardViewModeController =
      widget.boardViewModeController == null;

  @override
  void initState() {
    super.initState();
    if (_ownsThemeController) _themeController.load();
    if (_ownsBoardViewModeController) _boardViewModeController.load();
  }

  @override
  void dispose() {
    if (_ownsThemeController) _themeController.dispose();
    if (_ownsBoardViewModeController) _boardViewModeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'NockNock',
        debugShowCheckedModeBanner: false,
        navigatorObservers: widget.navigatorObservers,
        theme: AppTheme.lightFor(_themeController.colorTheme),
        darkTheme: AppTheme.darkFor(_themeController.colorTheme),
        themeMode: _themeController.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 260),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: FlutterQuillLocalizations.supportedLocales,
        onGenerateInitialRoutes: (initialRoute) => [
          _boardRoute(
            RouteSettings(
              name: _isSupportedRoute(initialRoute) ? initialRoute : '/',
            ),
          ),
        ],
        onGenerateRoute: (settings) =>
            _isSupportedRoute(settings.name) ? _boardRoute(settings) : null,
        builder: (context, child) {
          final app = child ?? const SizedBox.shrink();
          final preferences = widget.preferences;
          if (preferences == null) return app;
          return GooglePlayUpdatePrompt(
            preferences: preferences,
            navigatorKey: _navigatorKey,
            child: app,
          );
        },
      ),
    );
  }

  Route<void> _boardRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => RepositoryProvider<AuthRepository>.value(
        value: widget.authRepository,
        child: BlocProvider(
          create: (_) => NotesCubit(widget.repository)..load(),
          child: BoardPage(
            themeController: _themeController,
            viewModeController: _boardViewModeController,
            notificationsController: widget.notificationsController,
          ),
        ),
      ),
    );
  }

  bool _isSupportedRoute(String? routeName) {
    if (routeName == null) return false;
    final uri = Uri.tryParse(routeName);
    return uri?.path == '/' || uri?.path == '/invitations';
  }
}
