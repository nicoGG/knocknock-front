import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';
import 'package:nocknock/core/telemetry/app_telemetry.dart';
import 'package:nocknock/core/telemetry/telemetry_dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _notificationChannel = AndroidNotificationChannel(
  'nocknock_notifications',
  'Notificaciones de NockNock',
  description: 'Cambios en listas compartidas y recordatorios.',
  importance: Importance.high,
);

class NotificationsController extends ChangeNotifier
    with WidgetsBindingObserver {
  NotificationsController({
    required this.authRepository,
    required String apiBaseUrl,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    Dio? dio,
    AppTelemetry? telemetry,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _telemetry = telemetry,
       _dio =
           dio ??
           createTelemetryDio(
             BaseOptions(baseUrl: apiBaseUrl),
             telemetry: telemetry,
           );

  final AuthRepository authRepository;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final Dio _dio;
  final AppTelemetry? _telemetry;
  final _tapEvents = StreamController<Map<String, String>>.broadcast();

  StreamSubscription<AppUser?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  List<AppNotification> _notifications = const [];
  Map<String, String>? _pendingTap;
  bool _isLoading = false;
  bool _initialized = false;
  bool _localNotificationsAvailable = false;
  bool _firebaseMessagingAvailable = false;
  String? _message;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((item) => !item.isRead).length;
  bool get isLoading => _isLoading;
  String? get message => _message;
  Stream<Map<String, String>> get tapEvents => _tapEvents.stream;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    try {
      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _handleTapPayload(payload);
        },
      );
      _localNotificationsAvailable = true;
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_notificationChannel);
    } on MissingPluginException catch (error) {
      debugPrint(
        'Notificaciones locales aún no están registradas. '
        'Detén la app y ejecútala nuevamente: $error',
      );
    }

    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _firebaseMessagingAvailable = true;
      _messageSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleTap(message.data),
      );
      _tokenSubscription = _messaging.onTokenRefresh.listen(
        (token) => _registerToken(token),
      );
    } on MissingPluginException catch (error) {
      debugPrint(
        'Firebase Messaging aún no está registrado. '
        'Detén la app y ejecútala nuevamente: $error',
      );
    }
    _authSubscription = authRepository.authStateChanges.listen(
      _handleAuthChanged,
    );

    if (_localNotificationsAvailable) {
      final launchDetails = await _localNotifications
          .getNotificationAppLaunchDetails();
      final localPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          localPayload != null) {
        _handleTapPayload(localPayload);
      }
    }
    if (_firebaseMessagingAvailable) {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) _handleTap(initialMessage.data);
    }
    await _handleAuthChanged(authRepository.currentUser);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        authRepository.currentUser != null) {
      unawaited(syncCurrentDevice());
      unawaited(load());
    }
  }

  Future<void> load() async {
    if (authRepository.currentUser == null) {
      _notifications = const [];
      _message = null;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _message = null;
    notifyListeners();
    try {
      final response = await _authorizedGet<List<dynamic>>('/notifications');
      _notifications = (response.data ?? const [])
          .map(
            (item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      _message = 'No pudimos actualizar tus notificaciones.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) return;
    final readAt = DateTime.now();
    _notifications = _notifications
        .map(
          (item) => item.id == notification.id ? item.markRead(readAt) : item,
        )
        .toList();
    notifyListeners();
    try {
      await _authorizedPatch<void>('/notifications/${notification.id}/read');
    } catch (_) {
      await load();
    }
  }

  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    final readAt = DateTime.now();
    _notifications = _notifications
        .map((item) => item.isRead ? item : item.markRead(readAt))
        .toList();
    notifyListeners();
    try {
      await _authorizedPatch<void>('/notifications/read-all');
    } catch (_) {
      await load();
    }
  }

  Future<void> syncCurrentDevice() async {
    if (authRepository.currentUser == null ||
        kIsWeb ||
        !_firebaseMessagingAvailable) {
      return;
    }
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (error) {
      debugPrint('No se pudo registrar FCM: $error');
    }
  }

  Future<void> unregisterCurrentDevice() async {
    if (kIsWeb) return;
    try {
      final deviceId = await _deviceId();
      await _authorizedDelete<void>('/notifications/devices/$deviceId');
    } catch (error) {
      debugPrint('No se pudo desvincular el dispositivo: $error');
    } finally {
      if (_firebaseMessagingAvailable) {
        await _messaging.deleteToken().catchError((_) {});
      }
      _notifications = const [];
      notifyListeners();
    }
  }

  Map<String, String>? takePendingTap() {
    final value = _pendingTap;
    _pendingTap = null;
    return value;
  }

  Future<void> _handleAuthChanged(AppUser? user) async {
    if (user == null) {
      _notifications = const [];
      notifyListeners();
      return;
    }
    await Future.wait([syncCurrentDevice(), load()]);
  }

  Future<void> _registerToken(String token) async {
    if (authRepository.currentUser == null || !_firebaseMessagingAvailable) {
      return;
    }
    try {
      await _authorizedPost<void>(
        '/notifications/devices',
        data: {
          'deviceId': await _deviceId(),
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (error) {
      debugPrint('No se pudo actualizar el token FCM: $error');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await load();
    final notification = message.notification;
    if (notification == null ||
        !Platform.isAndroid ||
        !_localNotificationsAvailable) {
      return;
    }
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification.title ?? 'NockNock',
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'nocknock_notifications',
          'Notificaciones de NockNock',
          channelDescription: 'Cambios en listas compartidas y recordatorios.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleTapPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _handleTap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // An invalid notification payload should simply open the app.
    }
  }

  void _handleTap(Map<String, dynamic> data) {
    final normalized = data.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
    _pendingTap = normalized;
    _tapEvents.add(normalized);
    unawaited(_telemetry?.logNotificationOpened(normalized['type']));
    unawaited(load());
  }

  Future<String> _deviceId() async {
    final preferences = await SharedPreferences.getInstance();
    const key = 'nocknock_notification_device_id';
    final existing = preferences.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = const Uuid().v4();
    await preferences.setString(key, value);
    return value;
  }

  Future<Options> _authOptions() async {
    final token = await authRepository.getIdToken();
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<Response<T>> _authorizedGet<T>(String path) async =>
      _dio.get<T>(path, options: await _authOptions());

  Future<Response<T>> _authorizedPost<T>(String path, {Object? data}) async =>
      _dio.post<T>(path, data: data, options: await _authOptions());

  Future<Response<T>> _authorizedPatch<T>(String path) async =>
      _dio.patch<T>(path, options: await _authOptions());

  Future<Response<T>> _authorizedDelete<T>(String path) async =>
      _dio.delete<T>(path, options: await _authOptions());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
    unawaited(_tokenSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_openedSubscription?.cancel());
    unawaited(_tapEvents.close());
    _dio.close();
    super.dispose();
  }
}
