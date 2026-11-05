import 'dart:convert';

import 'package:nocknock/features/assistant/assistant_client.dart';
import 'package:nocknock/features/assistant/assistant_mascot.dart';
import 'package:nocknock/features/home_widgets/home_widget_controller.dart';
import 'package:nocknock/features/notes/data/quick_capture_inbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/core/update/google_play_update_prompt.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/board_page.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:nocknock/features/notes/presentation/list_protection_guard.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NockNockApp extends StatefulWidget {
  const NockNockApp({
    required this.repository,
    required this.authRepository,
    this.themeController,
    this.boardViewModeController,
    this.listProtectionController,
    this.notificationsController,
    this.navigatorObservers = const [],
    this.createAssistantClient,
    this.preferences,
    super.key,
  });

  final NotesRepository repository;
  final AuthRepository authRepository;
  final AppThemeController? themeController;
  final BoardViewModeController? boardViewModeController;
  final ListProtectionController? listProtectionController;
  final NotificationsController? notificationsController;
  final List<NavigatorObserver> navigatorObservers;
  final AssistantClient Function()? createAssistantClient;
  final SharedPreferences? preferences;

  @override
  State<NockNockApp> createState() => _NockNockAppState();
}

class _NockNockAppState extends State<NockNockApp> {
  late final _captureInbox = QuickCaptureInbox(preferences: widget.preferences);
  late final _mascotPosition = ValueNotifier<Alignment?>(
    _savedMascotPosition(),
  );
  late final Map<String, Alignment> _mascotPlacements = _loadMascotPlacements();

  Map<String, Alignment> _loadMascotPlacements() {
    final raw = widget.preferences?.getString('nock_surface_positions_v1');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (entry.value is List &&
              entry.value.length == 2 &&
              entry.value[0] is num &&
              entry.value[1] is num &&
              (entry.value[0] as num).isFinite &&
              (entry.value[1] as num).isFinite)
            entry.key: Alignment(
              (entry.value[0] as num).toDouble().clamp(-1, 1),
              (entry.value[1] as num).toDouble().clamp(-1, 1),
            ),
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  late final _dismissedTips =
      (widget.preferences?.getStringList('nock_dismissed_tips_v1') ??
              <String>[])
          .toSet();

  Alignment? _savedMascotPosition() {
    final x = widget.preferences?.getDouble('nock_position_x');
    final y = widget.preferences?.getDouble('nock_position_y');
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return Alignment(x.clamp(-1.0, 1.0), y.clamp(-1.0, 1.0));
  }

  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppThemeController _themeController =
      widget.themeController ?? AppThemeController();
  late final bool _ownsThemeController = widget.themeController == null;
  late final BoardViewModeController _boardViewModeController =
      widget.boardViewModeController ?? BoardViewModeController();
  late final bool _ownsBoardViewModeController =
      widget.boardViewModeController == null;
  late final ListProtectionController _listProtectionController =
      widget.listProtectionController ??
      ListProtectionController(preferences: widget.preferences);
  late final bool _ownsListProtectionController =
      widget.listProtectionController == null;

  late final _homeWidgets = HomeWidgetController(
    repository: widget.repository,
    auth: widget.authRepository,
    protection: _listProtectionController,
    themeController: _themeController,
  );

  @override
  void initState() {
    super.initState();
    _captureInbox.start();
    _homeWidgets.start();
    if (_ownsThemeController) _themeController.load();
    if (_ownsBoardViewModeController) _boardViewModeController.load();
  }

  @override
  void dispose() {
    if (_ownsThemeController) _themeController.dispose();
    if (_ownsBoardViewModeController) _boardViewModeController.dispose();
    _mascotPosition.dispose();
    _homeWidgets.dispose();
    if (_ownsListProtectionController) _listProtectionController.dispose();
    _captureInbox.dispose();
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
          final appWithUpdatePrompt = preferences == null
              ? app
              : GooglePlayUpdatePrompt(
                  preferences: preferences,
                  navigatorKey: _navigatorKey,
                  child: app,
                );
          return ListProtectionPrivacyGuard(
            controller: _listProtectionController,
            child: MascotPosition(
              position: _mascotPosition,
              placements: _mascotPlacements,
              onSurfacePlaced: (surface, point) {
                _mascotPlacements[surface] = point;
                widget.preferences?.setString(
                  'nock_surface_positions_v1',
                  jsonEncode(
                    _mascotPlacements.map(
                      (key, value) => MapEntry(key, [value.x, value.y]),
                    ),
                  ),
                );
              },
              dismissedTips: _dismissedTips,
              onDismiss: (tip) {
                _dismissedTips.add(tip.name);
                widget.preferences?.setStringList(
                  'nock_dismissed_tips_v1',
                  _dismissedTips.toList(),
                );
              },
              onPlaced: (point) {
                widget.preferences?.setDouble('nock_position_x', point.x);
                widget.preferences?.setDouble('nock_position_y', point.y);
              },
              child: appWithUpdatePrompt,
            ),
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
            createAssistantClient: widget.createAssistantClient,
            captureInbox: _captureInbox,
            homeWidgets: _homeWidgets,
            themeController: _themeController,
            viewModeController: _boardViewModeController,
            listProtectionController: _listProtectionController,
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
