import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppTelemetry {
  AppTelemetry._()
    : _analytics = FirebaseAnalytics.instance,
      _crashlytics = FirebaseCrashlytics.instance;

  static final instance = AppTelemetry._();

  final FirebaseAnalytics _analytics;
  final FirebaseCrashlytics _crashlytics;
  StreamSubscription<String?>? _userSubscription;
  Future<String?>? _appInstanceId;
  Future<String>? _clientVersion;
  bool _collectionEnabled = false;
  bool _initialized = false;

  late final NavigatorObserver navigatorObserver = FirebaseAnalyticsObserver(
    analytics: _analytics,
    nameExtractor: _screenName,
    onError: (error) => debugPrint('Analytics no registró navegación: $error'),
  );

  bool get collectionEnabled => _collectionEnabled;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    const explicitlyEnabled = bool.fromEnvironment('ENABLE_FIREBASE_TELEMETRY');
    _collectionEnabled = kReleaseMode || explicitlyEnabled;
    var initializationFailed = false;

    try {
      // Configure each native plugin sequentially. Some plugin calls can throw
      // synchronously when the installed runner predates the plugin; starting
      // both calls before attaching error handlers would orphan the first
      // Future and surface it as an unhandled PlatformException.
      await _analytics.setAnalyticsCollectionEnabled(_collectionEnabled);
      if (_collectionEnabled) {
        await _analytics.setDefaultEventParameters({
          'telemetry_schema_version': 1,
        });
      }
      await _crashlytics.setCrashlyticsCollectionEnabled(_collectionEnabled);
      if (_collectionEnabled) {
        await _crashlytics.setCustomKey('telemetry_schema_version', 1);
      }
    } on PlatformException catch (error) {
      initializationFailed = true;
      _collectionEnabled = false;
      debugPrint(
        'La telemetría nativa aún no está disponible. '
        'Haz una reinstalación completa: $error',
      );
    } on MissingPluginException catch (error) {
      initializationFailed = true;
      _collectionEnabled = false;
      debugPrint(
        'La telemetría nativa aún no está registrada. '
        'Haz una reinstalación completa: $error',
      );
    } catch (error) {
      initializationFailed = true;
      _collectionEnabled = false;
      debugPrint(
        'La telemetría no pudo inicializarse: ${error.runtimeType}. '
        'Si agregaste plugins nativos, detén y reinstala la app.',
      );
    }

    if (initializationFailed) await _disableCollectionAfterFailure();

    _installErrorHandlers();
  }

  Future<void> bindUserChanges(
    Stream<String?> userIds, {
    String? initialUserId,
  }) async {
    await _setUserId(initialUserId);
    await _userSubscription?.cancel();
    _userSubscription = userIds.distinct().listen(
      (userId) => unawaited(_setUserId(userId)),
    );
  }

  Future<void> logLogin(String method) =>
      _guarded(() => _analytics.logLogin(loginMethod: _safeValue(method)));

  Future<void> logEvent(String name, {Map<String, Object>? parameters}) =>
      _guarded(() => _analytics.logEvent(name: name, parameters: parameters));

  Future<void> logNotificationOpened(String? type) => logEvent(
    'notification_opened',
    parameters: {'notification_type': _safeValue(type ?? 'unknown')},
  );

  Future<Map<String, String>> analyticsRequestHeaders() async {
    final headers = <String, String>{
      'X-Client-Version': await (_clientVersion ??= _loadClientVersion()),
    };
    if (!_collectionEnabled) return headers;

    try {
      final appInstanceId = await (_appInstanceId ??= _analytics.appInstanceId);
      final sessionId = await _analytics.getSessionId();
      if (appInstanceId != null && appInstanceId.isNotEmpty) {
        headers['X-Firebase-App-Instance-Id'] = appInstanceId;
        headers['X-Firebase-App-Id'] = Firebase.app().options.appId;
      }
      if (sessionId != null && sessionId > 0) {
        headers['X-Analytics-Session-Id'] = sessionId.toString();
      }
    } on PlatformException {
      // The API request must continue even if Analytics is unavailable.
    } on MissingPluginException {
      // A full reinstall will register newly added native plugins.
    }
    return headers;
  }

  Future<void> noteApiRequest({
    required String method,
    required String requestId,
    required String route,
  }) => _guarded(() async {
    await _crashlytics.setCustomKey('latest_request_id', requestId);
    await _crashlytics.setCustomKey('latest_http_method', method);
    await _crashlytics.setCustomKey('latest_http_route', route);
    await _crashlytics.log('$method $route request_id=$requestId');
  });

  Future<void> recordApiFailure({
    required String category,
    required String method,
    required String requestId,
    required String route,
    required bool reportToCrashlytics,
    int? statusCode,
  }) async {
    if (!_collectionEnabled) return;
    await logEvent(
      'api_request_failed',
      parameters: {
        'error_category': _safeValue(category),
        'http_method': _safeValue(method),
        'http_route': _safeValue(route),
        'status_code': statusCode ?? 0,
      },
    );
    if (!reportToCrashlytics) return;

    await _guarded(() async {
      await _crashlytics.setCustomKey('latest_request_id', requestId);
      await _crashlytics.setCustomKey('latest_http_status', statusCode ?? 0);
      await _crashlytics.recordError(
        StateError('$method $route failed: $category'),
        StackTrace.current,
        reason: 'api_request_failed',
        fatal: false,
      );
    });
  }

  Future<void> _setUserId(String? userId) {
    final normalized = userId?.trim();
    return _guarded(() async {
      await _analytics.setUserId(
        id: normalized == null || normalized.isEmpty ? null : normalized,
      );
      await _analytics.setUserProperty(
        name: 'auth_state',
        value: normalized == null || normalized.isEmpty ? 'guest' : 'signed_in',
      );
      await _crashlytics.setUserIdentifier(normalized ?? '');
    });
  }

  void _installErrorHandlers() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      if (_collectionEnabled) {
        unawaited(
          _guarded(() => _crashlytics.recordFlutterFatalError(details)),
        );
      }
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final previouslyHandled =
          previousPlatformHandler?.call(error, stack) ?? false;
      if (_collectionEnabled) {
        unawaited(
          _guarded(() => _crashlytics.recordError(error, stack, fatal: true)),
        );
        return true;
      }
      return previouslyHandled;
    };
  }

  Future<void> _guarded(Future<void> Function() operation) async {
    if (!_collectionEnabled) return;
    try {
      await operation();
    } on PlatformException catch (error) {
      debugPrint('Telemetría no registró la operación: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Telemetría nativa aún no está registrada: $error');
    } catch (error) {
      debugPrint('Telemetría omitida: ${error.runtimeType}');
    }
  }

  Future<void> _disableCollectionAfterFailure() async {
    try {
      await _analytics.setAnalyticsCollectionEnabled(false);
    } catch (_) {
      // The native plugin may not exist in the currently installed runner.
    }
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(false);
    } catch (_) {
      // The native plugin may not exist in the currently installed runner.
    }
  }

  Future<String> _loadClientVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } on PlatformException {
      return 'unknown';
    } on MissingPluginException {
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  static String? _screenName(RouteSettings settings) {
    return switch (settings.name) {
      '/' => 'board',
      '/invitations' => 'invitation',
      final name? when name.isNotEmpty => _safeValue(name),
      _ => null,
    };
  }

  static String _safeValue(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp('[^a-z0-9_./:-]'),
      '_',
    );
    return normalized.isEmpty
        ? 'unknown'
        : normalized.substring(0, normalized.length.clamp(0, 100));
  }
}
